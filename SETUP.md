# Setup

This repository contains agent definitions and hooks for the multi-phase orchestration pipeline described in [README.md](README.md) and [AGENTS.md](AGENTS.md). Cloning the repo alone does not make anything work — `agents/*.md` sits at the repo root, which is **not** a path Claude Code loads agent definitions from. You have to copy the files into one of the two locations Claude Code actually reads:

- `~/.claude/agents/` — global, applies to every project and session on this machine.
- `.claude/agents/` (inside a specific project) — project-scoped, applies only when Claude Code is run from that project.

The same global-vs-project split applies to hooks and settings below. Pick one scope and be consistent — mixing global agents with project-scoped hooks (or vice versa) is fine, but the path *inside* `coding-lead.md`'s hook wiring (see step 2) has to match wherever you actually put the hook.

## 1. Install the agents

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
| `coding-lead-agent-guard.sh` | Stable |
| `post-edit-format.sh` | Stable |
| `pre-handback-architect-gate.sh` | Stable |

For all three stable hooks: copy the script to the hooks directory for your chosen scope, and make it executable.

**Global:**

```bash
mkdir -p ~/.claude/hooks
cp hooks/coding-lead-agent-guard.sh hooks/post-edit-format.sh hooks/pre-handback-architect-gate.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/coding-lead-agent-guard.sh ~/.claude/hooks/post-edit-format.sh ~/.claude/hooks/pre-handback-architect-gate.sh
```

**Project-scoped:**

```bash
mkdir -p .claude/hooks
cp hooks/coding-lead-agent-guard.sh hooks/post-edit-format.sh hooks/pre-handback-architect-gate.sh .claude/hooks/
chmod +x .claude/hooks/coding-lead-agent-guard.sh .claude/hooks/post-edit-format.sh .claude/hooks/pre-handback-architect-gate.sh
```

### `coding-lead-agent-guard.sh`

This hook enforces, at the tool-call level, that `coding-lead` can only dispatch `coder` — it denies any other `subagent_type` on `coding-lead`'s `Agent` calls. It is not wired through `settings.json`; it's wired directly in `agents/coding-lead.md`'s own frontmatter:

```yaml
hooks:
  PreToolUse:
    - matcher: "Agent"
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/hooks/coding-lead-agent-guard.sh"
```

**Gotcha:** `${CLAUDE_PROJECT_DIR}` only resolves correctly if you installed `coding-lead.md` and the hook *project-scoped*, in the same project. If you installed the agents and hooks **globally** (`~/.claude/agents/`, `~/.claude/hooks/`), this line will not resolve to your global hooks directory and the guard will silently fail to fire. Edit the `command` line in your installed copy of `coding-lead.md` to point at the global path instead:

```yaml
          command: "$HOME/.claude/hooks/coding-lead-agent-guard.sh"
```

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
            "command": "${CLAUDE_PROJECT_DIR}/hooks/post-edit-format.sh"
          }
        ]
      }
    ]
  }
}
```

(This repo's own `.claude/settings.json` demonstrates the project-scoped form.)

### `pre-handback-architect-gate.sh`

Purpose: validates the architect agent's final report (delivered via the `SubagentHandback` tool) against its output contract — `STATUS: DESIGN`/`STATUS: BLOCKED-AMBIGUOUS` preamble plus a citation requirement — denying once and failing open thereafter so a persistent mismatch never blocks the whole run.

Unlike `coding-lead-agent-guard.sh`, this hook is not embedded in an agent's frontmatter — it has to be wired into `settings.json`'s `hooks.PreToolUse` block, the same way `post-edit-format.sh` is wired into `hooks.PostToolUse` above:

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

The `command` path above (`$HOME/.claude/hooks/...`) is the global-install form. For a project-scoped install, swap in `${CLAUDE_PROJECT_DIR}/hooks/pre-handback-architect-gate.sh` instead — the same global-vs-project distinction described for the other hooks above.

This hook only fires when the session runs in auto mode — `SubagentHandback` is an auto-mode-only tool — so it has no effect under other permission modes. That is a known, accepted limitation, not a bug to fix here.

## 3. The spawn-depth safety net

`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` caps how many levels deep subagents can spawn further subagents, which backstops the "no peer leads" rule structurally rather than relying solely on `coding-lead-agent-guard.sh`. This repo's own project-scoped `.claude/settings.json` sets it:

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
- `ls ~/.claude/agents/` (or `.claude/agents/`) — confirm all five `agents/*.md` files copied over.
- Start a session and confirm `boss` is the active agent (it should identify itself as the executive orchestrator, not dispatch tests/code before decomposing the request).
- Give `boss` a trivial multi-step request and confirm the pipeline actually reaches `coding-lead`, and that `coding-lead` can successfully dispatch a `coder` (i.e. `coding-lead-agent-guard.sh` isn't blocking the one `subagent_type` it's supposed to allow).
