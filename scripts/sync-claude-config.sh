#!/usr/bin/env bash
#
# sync-claude-config.sh
#
# Symlinks every agent/hook file in this repo into the user's global Claude
# Code config directory (~/.claude/agents, ~/.claude/hooks), so that after
# this one-time bootstrap, `git pull` in this repo keeps the installed
# files' content live automatically (they are symlinks, not copies).
#
# WARNING: this OVERWRITES (clobbers) whatever currently exists at each
# destination path, including a user's own manual customizations or prior
# manual copies of these files. This is by design.
#
# Re-run this script only if the *set* of files under agents/ or hooks/
# changes (a file added, removed, or renamed) — not for ordinary edits to
# existing files, since those are picked up live through the symlinks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_DEST="$HOME/.claude/agents"
HOOKS_DEST="$HOME/.claude/hooks"

mkdir -p "$AGENTS_DEST" "$HOOKS_DEST"

echo "Syncing agents:"
for f in "$REPO_ROOT"/agents/*.md; do
  base="$(basename "$f")"
  ln -sf "$f" "$AGENTS_DEST/$base"
  echo "  $base -> $AGENTS_DEST/$base"
done

echo "Syncing hooks:"
for f in "$REPO_ROOT"/hooks/*.sh; do
  base="$(basename "$f")"
  chmod +x "$f"
  ln -sf "$f" "$HOOKS_DEST/$base"
  echo "  $base -> $HOOKS_DEST/$base"
done

echo
echo "Done. This is a one-time/occasional bootstrap — re-run only if the set of files under agents/ or hooks/ changes, not for ordinary content edits."
