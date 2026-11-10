#!/usr/bin/env bash
# agent-allowlist-guard.sh: PreToolUse guard on the Agent tool for lead agents.
#
# Wired from a lead's frontmatter, with that lead's allowed specialist types as arguments:
#   command: "$HOME/.claude/hooks/agent-allowlist-guard.sh coder"
#   command: "$HOME/.claude/hooks/agent-allowlist-guard.sh gherkin-writer parameter-tester test-writer"
#
# Allow: exit 0 with no output when .tool_input.subagent_type equals one argument.
# Deny:  exit 0 with a permissionDecision "deny" JSON for every other type,
#        including a missing or empty one.
# Fail closed: exit 2 (blocks the call; stderr becomes the reason) when no types
#        are configured, jq is missing, or the input cannot be read or parsed.
#        Pair the hook entry with onFailure: "block" so a missing script, a crash,
#        or a timeout also blocks.
#
# The Agent(...) list in a subagent's tools: line is ignored at runtime; these
# arguments are the enforced allowlist. Keep the two lists identical.
set -uo pipefail

fail() {
  printf 'agent-allowlist-guard: %s; refusing this Agent call.\n' "$1" >&2
  exit 2
}

[ "$#" -ge 1 ] || fail "no allowed subagent types configured"
command -v jq >/dev/null 2>&1 || fail "jq not found on PATH"

input=$(cat) || fail "could not read hook input"
[ -n "$input" ] || fail "empty hook input"

t=$(jq -r '.tool_input.subagent_type // ""' <<<"$input" 2>/dev/null) || fail "malformed hook input"
lead=$(jq -r '.agent_type // "this agent"' <<<"$input" 2>/dev/null) || lead="this agent"

for allowed in "$@"; do
  if [ "$t" = "$allowed" ]; then
    exit 0
  fi
done

list=""
for allowed in "$@"; do
  list="${list:+$list, }\`$allowed\`"
done

jq -n --arg lead "$lead" --arg t "$t" --arg list "$list" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("\($lead) may dispatch only \($list); refused subagent_type=`\($t)`. Re-slice under the New Eyes protocol in your agent definition and dispatch an allowed type. Never dispatch a lead.")
  }
}' || fail "could not build the deny response"
exit 0
