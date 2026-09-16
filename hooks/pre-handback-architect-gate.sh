#!/usr/bin/env bash
# PreToolUse / SubagentHandback gate for the `architect` agent.
#
# Reads the delivered report from .tool_input.message (NOT .last_assistant_message,
# which holds only the subagent's closing text on v2.1.271+) and enforces
# architect.md's output contract:
#   - first line is `STATUS: DESIGN` or `STATUS: BLOCKED-AMBIGUOUS`
#   - a STATUS: DESIGN report cites at least one file_path:line_number
#
# Denies at most once per subagent run, then lets the hand-back through with a
# warning, so a report the agent cannot fix never costs the whole run.
# Fails open (silent exit 0) on any unexpected input: a broken gate must not
# block valid reports.
set -uo pipefail

MAX_DENIES=1

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
[ -n "$input" ] || exit 0

agent=$(jq -r '.agent_type // empty' <<<"$input" 2>/dev/null) || exit 0
[ "$agent" = "architect" ] || exit 0

msg=$(jq -r '.tool_input.message // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$msg" ] || exit 0   # fail open: nothing to validate

first_line=${msg%%$'\n'*}
first_line=${first_line#$'\xef\xbb\xbf'}
first_line=${first_line%$'\r'}

reason=""
case "$first_line" in
  "STATUS: BLOCKED-AMBIGUOUS"*)
    ;;
  "STATUS: DESIGN"*)
    if ! grep -qE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' <<<"$msg"; then
      reason="architect.md:32 requires citing at least one \`file_path:line_number\` the design touches; this STATUS: DESIGN report has none. Add grounding citations and call SubagentHandback again with the corrected report. Do not end your turn without delivering a report."
    fi
    ;;
  *)
    reason="architect.md:36-38 requires the report's first line to be \`STATUS: DESIGN\` or \`STATUS: BLOCKED-AMBIGUOUS\`. Yours begins: \"${first_line:0:80}\". Call SubagentHandback again with the same report prefixed by the correct status line. Do not end your turn without delivering a report."
    ;;
esac

state_dir=${CLAUDE_HOOK_STATE_DIR:-${TMPDIR:-/tmp}/claude-architect-gate}
agent_id=$(jq -r '.agent_id // .session_id // empty' <<<"$input" 2>/dev/null) || agent_id=""
[ -n "$agent_id" ] || agent_id="unknown"
key=$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_.-' '_')
state_file="$state_dir/$key.denies"

if [ -z "$reason" ]; then
  rm -f "$state_file" 2>/dev/null
  exit 0
fi

mkdir -p "$state_dir" 2>/dev/null || exit 0   # fail open: no state, no gate
find "$state_dir" -type f -mtime +1 -delete 2>/dev/null

denies=$(cat "$state_file" 2>/dev/null) || denies=0
case "$denies" in ''|*[!0-9]*) denies=0 ;; esac

if [ "$denies" -ge "$MAX_DENIES" ]; then
  rm -f "$state_file" 2>/dev/null
  jq -n --arg r "$reason" --arg n "$MAX_DENIES" \
    '{systemMessage: ("architect report gate: contract still unmet after \($n) denial(s); letting the hand-back through so the run is not lost. Unmet requirement: \($r)")}'
  exit 0
fi

printf '%s' "$((denies + 1))" > "$state_file" 2>/dev/null

jq -n --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
