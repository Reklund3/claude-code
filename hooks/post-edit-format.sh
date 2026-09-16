#!/usr/bin/env bash
set -euo pipefail
f=$(jq -r '.tool_input.file_path // empty')
[ -n "$f" ] || exit 0
case "$f" in
  *.go)        (cd "$(dirname "$f")" && go fmt ./...) ;;
  */Chart.yaml) helm lint "$(dirname "$f")" ;;
esac
