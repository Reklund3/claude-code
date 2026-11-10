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
# Re-run this script whenever the *set* of files under agents/ or hooks/
# changes (a file added, removed, or renamed). It links new files and removes
# links whose repo file is gone. Ordinary edits to existing files are picked
# up live through the symlinks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_DEST="$HOME/.claude/agents"
HOOKS_DEST="$HOME/.claude/hooks"

mkdir -p "$AGENTS_DEST" "$HOOKS_DEST"

# Remove links in a destination that point into this repo at files that no
# longer exist (a file removed or renamed upstream).
prune_dangling() {
  local dest="$1" link target
  for link in "$dest"/*; do
    [ -L "$link" ] || continue
    target="$(readlink "$link")"
    case "$target" in
      "$REPO_ROOT"/*)
        if [ ! -e "$link" ]; then
          rm "$link"
          echo "  pruned $(basename "$link") (target removed: $target)"
        fi
        ;;
    esac
  done
}

echo "Pruning stale links:"
prune_dangling "$AGENTS_DEST"
prune_dangling "$HOOKS_DEST"

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
echo "Done. Re-run whenever files under agents/ or hooks/ are added, removed, or renamed."
