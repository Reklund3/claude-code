#!/usr/bin/env bash
set -euo pipefail
t=$(jq -r '.tool_input.subagent_type // empty')
[ "$t" = "coder" ] && exit 0
jq -n --arg t "$t" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("coding-lead may dispatch only `coder`; refused subagent_type=`"+$t+"`. Re-slice and dispatch a fresh coder per coding-lead.md:33-37.")}}'
