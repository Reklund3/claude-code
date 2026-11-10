# Setup

This repository contains agent definitions and hooks for the multi-phase orchestration pipeline described in [README.md](README.md) and [AGENTS.md](AGENTS.md). Cloning the repo alone does not make anything work — `agents/*.md` sits at the repo root, which is **not** a path Claude Code loads agent definitions from. You have to copy the files into one of the two locations Claude Code actually reads:

- `~/.claude/agents/` — global, applies to every project and session on this machine.
- `.claude/agents/` (inside a specific project) — project-scoped, applies only when Claude Code is run from that project.

The same global-vs-project split applies to hooks and settings below. Pick one scope and be consistent — mixing global agents with project-scoped hooks (or vice versa) is fine, but the path *inside* the hook wiring of `coding-lead.md` and `test-lead.md` (see step 2) has to match wherever you actually put `agent-allowlist-guard.sh`.

## 1. Install the agents

**Shortcut:** for a **global** install, you can skip the manual `cp` commands in this section and in step 2 below by running `./scripts/sync-claude-config.sh` once after cloning. It symlinks every file in `agents/*.md` and `hooks/*.sh` (including `coding-lead.md` and `test-lead.md`) into `~/.claude/agents/` and `~/.claude/hooks/`, so `git pull` alone keeps their content current afterward — re-run the script only if agent or hook *files* are added, removed, or renamed upstream, not for ordinary edits to existing files. It only supports the global scope; for a project-scoped install, use the manual steps below instead (see the note on `coding-lead.md` and `test-lead.md` in the Project-scoped block just below).

Pick one:

**Global (all projects, all sessions):**

```bash
cp agents/*.md ~/.claude/agents/
```

**Project-scoped (this project only):**

```bash
mkdir -p .claude/agents
cp agents/*.md .claude/agents/
```

**Note on `coding-lead.md` and `test-lead.md` specifically:** this repo's copies of those files hardcode the *global* hook path (`$HOME/.claude/hooks/agent-allowlist-guard.sh <types>`) directly in their frontmatter. If you copy them into a project-scoped `.claude/agents/` here, edit that one `command:` line in each copy back to the project-scoped form before it will work, keeping each file's own types:

```yaml
          command: "${CLAUDE_PROJECT_DIR}/.claude/hooks/agent-allowlist-guard.sh <types>"
```

See the `agent-allowlist-guard.sh` subsection under step 2 for why.

### Making `boss` the main agent

`boss.md`'s own description says it is "Best as the main agent of a session." To make it the default, add an `agent` key to `settings.json`. This is normally done globally, in `~/.claude/settings.json`:

```json
{
  "agent": "boss"
}
```

If `~/.claude/settings.json` already has content (e.g. an `env` block — see step 3), merge this key in rather than overwriting the file.

## 2. Install the hooks

The `hooks/` directory has three scripts, all stable and documented below.

| Script | Status |
| :--- | :--- |
| `agent-allowlist-guard.sh` | Stable |
| `post-edit-format.sh` | Stable |
| `pre-handback-architect-gate.sh` | Stable |

For all three stable hooks: copy the script to the hooks directory for your chosen scope, and make it executable.

**Global:**

```bash
mkdir -p ~/.claude/hooks
cp hooks/agent-allowlist-guard.sh hooks/post-edit-format.sh hooks/pre-handback-architect-gate.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/agent-allowlist-guard.sh ~/.claude/hooks/post-edit-format.sh ~/.claude/hooks/pre-handback-architect-gate.sh
```

*(Or run `./scripts/sync-claude-config.sh` once instead of the manual steps above — see the shortcut note in step 1.)*

**Project-scoped:**

```bash
mkdir -p .claude/hooks
cp hooks/agent-allowlist-guard.sh hooks/post-edit-format.sh hooks/pre-handback-architect-gate.sh .claude/hooks/
chmod +x .claude/hooks/agent-allowlist-guard.sh .claude/hooks/post-edit-format.sh .claude/hooks/pre-handback-architect-gate.sh
```

### `agent-allowlist-guard.sh`

This hook enforces, at the tool-call level, that a lead agent can dispatch only the subagent types on its allowlist. The allowlist is passed to the script as arguments, and any other `subagent_type` on the lead's `Agent` calls is denied. It is not wired through `settings.json`; it's wired directly in each lead's own frontmatter. `agents/coding-lead.md` reads:

```yaml
hooks:
  PreToolUse:
    - matcher: "Agent"
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-allowlist-guard.sh coder"
          timeout: 10
          onFailure: "block"
```

`agents/test-lead.md` reads:

```yaml
hooks:
  PreToolUse:
    - matcher: "Agent"
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-allowlist-guard.sh gherkin-writer parameter-tester test-writer"
          timeout: 10
          onFailure: "block"
```

The guard fails closed: on a malformed payload or any other internal failure it exits 2, and `onFailure: "block"` makes any other hook failure block the `Agent` call too. `onFailure` requires Claude Code v2.1.295 or later.

The `tools: Agent(...)` list in each lead's frontmatter must match the arguments passed to the guard. Change one without the other and the two layers disagree.

These are the **global**-install form, so a global install (including via `scripts/sync-claude-config.sh`) works with no edits needed. **Gotcha (project-scoped installs only):** if you instead copy `coding-lead.md` or `test-lead.md` into a project-scoped `.claude/agents/`, `$HOME` will resolve to your real home directory rather than that project's hooks folder, and the guard will fire against the wrong (or a nonexistent) path. Edit the `command` line in your project-scoped copy back to the project-scoped form, keeping each file's own types:

```yaml
          command: "${CLAUDE_PROJECT_DIR}/.claude/hooks/agent-allowlist-guard.sh <types>"
```

After pulling the change that introduced this script, re-run `./scripts/sync-claude-config.sh`. Until you do, both leads' `Agent` calls are blocked.

### `post-edit-format.sh`

This hook runs `go fmt` (for `.go` files) or `helm lint` (for `Chart.yaml` files) after an edit. Unlike the guard above, it is not embedded in any agent's frontmatter — it has to be wired into `settings.json`'s `hooks.PostToolUse` block yourself.

**Global** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/post-edit-format.sh"
          }
        ]
      }
    ]
  }
}
```

**Project-scoped** (`.claude/settings.json`):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/post-edit-format.sh"
          }
        ]
      }
    ]
  }
}
```

(This repo's own `.claude/settings.json` uses `${CLAUDE_PROJECT_DIR}/hooks/` because its hooks live at the repo root.)

### `pre-handback-architect-gate.sh`

Purpose: validates the architect agent's final report (delivered via the `SubagentHandback` tool) against its output contract — `STATUS: DESIGN`/`STATUS: BLOCKED-AMBIGUOUS` preamble plus a citation requirement — denying once and failing open thereafter so a persistent mismatch never blocks the whole run.

Unlike `agent-allowlist-guard.sh`, this hook is not embedded in an agent's frontmatter — it has to be wired into `settings.json`'s `hooks.PreToolUse` block, the same way `post-edit-format.sh` is wired into `hooks.PostToolUse` above:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "SubagentHandback",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/pre-handback-architect-gate.sh",
            "timeout": 10,
            "statusMessage": "Checking architect report contract"
          }
        ]
      }
    ]
  }
}
```

The `command` path above (`$HOME/.claude/hooks/...`) is the global-install form. For a project-scoped install, swap in `${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-handback-architect-gate.sh` instead — the same global-vs-project distinction described for the other hooks above.

This hook only fires when the session runs in auto mode — `SubagentHandback` is an auto-mode-only tool — so it has no effect under other permission modes. That is a known, accepted limitation, not a bug to fix here.

## 3. The spawn-depth safety net

`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` counts subagent layers below the main conversation, and defaults to 3 when unset. The pipeline needs two: `boss` (main) → a lead (`coding-lead` or `test-lead`, layer 1) → a specialist (layer 2). `2` is the backstop: specialists cannot spawn anything. Unset (3) also works but drops the backstop; `1` breaks both leads. The value is per settings file: this repo's `.claude/settings.json` applies only here, so every target project that runs the pipeline sets it in its own `.claude/settings.json`, or you set it once globally (second block below). In a project's `.claude/settings.json`, as this repo's own file does:

```json
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"
  }
}
```

For a global install, add the same `env` block to `~/.claude/settings.json`. Global configs do not have an `env` block by default, so this is usually a net-new top-level key rather than a merge:

```json
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"
  }
}
```

If `~/.claude/settings.json` already has other top-level keys (e.g. `agent` from step 1, or `hooks` from step 2), merge this in as a sibling key — don't overwrite the file.

## 4. Verify the install

- `ls -la ~/.claude/hooks/` (or `.claude/hooks/`) — confirm all three hook scripts are present and executable (`-rwxr-xr-x`).
- `ls ~/.claude/agents/` (or `.claude/agents/`) — confirm all ten `agents/*.md` files copied over. A global install made with `scripts/sync-claude-config.sh` before `agents/docs.md` existed needs the script re-run once (see step 1).
- Start a session and confirm `boss` is the active agent (it should identify itself as the executive orchestrator, not dispatch tests/code before decomposing the request).
- Give `boss` a trivial multi-step request and confirm the pipeline actually reaches `coding-lead`, and that `coding-lead` can successfully dispatch a `coder` (i.e. `agent-allowlist-guard.sh` isn't blocking the one `subagent_type` it's supposed to allow). Also confirm that Phase 2 reaches `test-lead`, that `test-lead` can dispatch `gherkin-writer`, `parameter-tester`, and `test-writer`, and that it is refused `coder`.
- After a `git pull` that adds, removes, or renames files under `agents/` or `hooks/`, re-run `./scripts/sync-claude-config.sh`. Then `find ~/.claude/agents ~/.claude/hooks -type l ! -exec test -e {} \; -print` must print nothing.
