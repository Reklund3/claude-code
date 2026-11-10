# Agent Orchestration Pipeline

This repository implements a multi-phase agent orchestration pipeline.

## Roles & Workflow

The pipeline follows a strict sequence to ensure design-led implementation:

1.  **`boss` (Executive Orchestrator)**: The main thread. Decomposes requests into phases. **Does not write code.** Holds Bash scoped in practice to `gh` (GitHub CLI) and `git` commands for interfacing with GitHub directly — an operational boundary, not a tool-enforced one.
2.  **`architect` (Design)**: Researches and produces a **Gherkin Behavioral Contract** or a **Technical Specification**. This is the source of truth for all downstream agents.
3.  **`test-lead` (Contract)**: Phase 2. Detects the target project's test stack, assigns each behavior in the architect's contract to exactly one specialist in a coverage map, dispatches them in test slices, and gates their output. **Writes no tests itself; all tests are written before implementation.**
    - **`gherkin-writer`**: `.feature` files and step definitions for named behaviors, only when the project already has a Gherkin runner.
    - **`parameter-tester`**: table-driven or property-style tests for a behavior's input space, in the project's own idiom.
    - **`test-writer`**: generic tests for everything else, and for named behaviors when there is no Gherkin runner.
4.  **`coding-lead` (Management)**: Decomposes the plan into atomic **Implementation Slices** and manages `coder` agents.
5.  **`coder` (Implementation)**: Executes a single, highly specific slice.

Support agents (not pipeline phases):

- **`docs` (Reference lookup)**: Read-only (`Read`, `WebFetch`, `WebSearch`). `boss` dispatches it to pull API reference pages verbatim with source URLs. Neither lead can dispatch it, because each lead's guard hook allows only its own specialists.
- **`mutation-tester` (On-demand mutation testing)**: The user runs it as its own session, `claude --agent mutation-tester`, after opening a pull request. It mutates only the PR's changed production files in a scratch git worktree, asks before using any tool the project does not declare and before restoring dependencies in the scratch copy (both in the same question to the user), and reports surviving mutants. It gates nothing, and no agent can dispatch it.

## Critical Operational Rules

- **The Contract is Prose**: The architect's output is the "contract." It must be pasted in full into the prompts for `test-lead` and `coding-lead`.
- **No Peer Leads**: Neither `coding-lead` nor `test-lead` ever dispatches a lead. Each lead's guard hook (`hooks/agent-allowlist-guard.sh`) allows only its own specialists.
- **The "New Eyes" Protocol**: If a `coder` or a test specialist fails, its lead must diagnose, re-slice, and dispatch a **fresh** agent of that type (do not use `SendMessage` to a failed one).
- **Verification**: `coding-lead` and `test-lead` must run tests via `Bash` to verify slices; do not trust a specialist's claim of success.
- **Test Coverage Map**: `test-lead` assigns each behavior to exactly one specialist: Gherkin covers named behaviors, parameter tests cover the input space, and `test-writer` covers the rest. Slices on disjoint files in different compilation units run in parallel; slices that share a file run in sequence.
- **EXPECTED-RED**: Tests are written before implementation, so a test that fails only because the behavior is not implemented is `EXPECTED-RED`, not a failure. This applies to every test specialist.
- **Test-Lead Status Preamble**: `test-lead`'s report begins with `TEST-STATUS: READY`, `TEST-STATUS: GAPS`, or `TEST-STATUS: BLOCKED`.
- **Architect Status Preamble**: The `architect`'s final message MUST begin with a fixed machine-readable status preamble on the very first line: `STATUS: DESIGN` for a complete design/contract, or `STATUS: BLOCKED-AMBIGUOUS` followed immediately by questions if the Ambiguity Gate is triggered.
- **Boss Escalation Stops**:
  - *Ambiguity*: If the architect returns `STATUS: BLOCKED-AMBIGUOUS`, `boss` halts the pipeline immediately (does not dispatch `test-lead`), presents questions to the user via `AskUserQuestion`, and re-dispatches `architect` with answers.
  - *Testability Gaps*: If `test-lead` returns `TEST-STATUS: GAPS`, `boss` re-dispatches `architect` with the `GAP:` lines before proceeding to Phase 3.
  - *Blocked Slices*: If `coding-lead` or `test-lead` reports blocked slices that cannot be resolved, `boss` reports them to the user and returns to `architect` to adjust design or re-slice (never dispatch a second lead of the same type over the same plan).
- **One Implementation Run per Task**: Before dispatching a `coding-lead`, a `test-lead`, or a fast-path `coder`, `boss` checks its task list (`TaskList`) and recent dispatches for a run already in flight on the same repository and task. If one exists, it sends the additional work to that run with `SendMessage` or waits for it to hand back, rather than dispatching a second. Concurrent runs on different tasks or different repositories are fine.
- **Two-Strike Stop**: If the same failure (same failing test or command, same error signature) recurs on a slice after one fresh re-dispatch, the lead (`coding-lead` or `test-lead`) stops that slice and reports it on a line beginning `BLOCKED:` with both verification outputs pasted. It never dispatches a third agent for that slice. `boss` then follows the Blocked Slices escalation.
- **Advisor Checkpoints (`boss` only)**: When an `advisor` tool is available, `boss` consults it (1) on a `coding-lead` or `test-lead` hand-back with a `BLOCKED:` slice, before choosing the next step, and (2) before its final synthesis of any request that dispatched `architect`, `test-lead`, `coding-lead`, or `coder`. There is no boss-side checkpoint before a plan locks, because `architect` already runs on Opus. Other agents do not take these checkpoints from this file; their own definitions govern them.

## Known Constraints & Quirks

- **Bash Boundary**: `architect`, `coding-lead`, and `test-lead` hold `Bash` access (for research/inspection, verification, and detection/verification respectively), but refraining from altering the codebase or implementing code is an operational boundary kept by the role, not a structural restriction enforced by the tool grant. `mutation-tester` holds Bash and no Edit or Write; that it writes only inside its scratch run directory is likewise an operational boundary, checked by its before/after snapshot of the working tree.
- **Duplicate-Dispatch Boundary**: The one-run-per-task rule is kept by `boss`'s judgment, not enforced by any hook or tool grant; nothing technically stops a second `coding-lead` or `test-lead` over the same task. A hook-enforced version was designed and tested but deferred.
- **Subagent Deadlock Rule**: Subagents (`architect`, `test-lead`, `gherkin-writer`, `parameter-tester`, `test-writer`, `coding-lead`, `coder`, `docs`) have no interactive channel to the user (cannot use `AskUserQuestion`) and must NEVER pause to wait for user approval; any ambiguities or blockers must be returned directly in the final report to halt execution cleanly rather than guessing speculatively or causing deadlocks. `mutation-tester` is a main-session agent, not a subagent, and asks the user directly.
- **Context Loss**: Subagents do not inherit the main conversation's "auto memory."
- **Relayed Consent Is Not User Consent**: Subagents will correctly refuse to edit `~/.claude/rules/` or `~/.claude/agents/` files even when a dispatching agent claims the user authorized it. This is documented Claude Code behavior, not a bug or over-caution: a relayed approval claim from another agent is never treated as user consent — only a direct main-session user message, or the permission system itself, can authorize config/permission changes.
- **Task Tools Are Opt-In**: Task tools are opt-in on 5.x models (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`). Subagents run in the background and never receive them, so the implementation-run ledger lives only in boss's task list.
- **Advisor Is Opt-In and Unenforceable**: The advisor is an experimental server tool, enabled by `/advisor`, the `advisorModel` setting, or `--advisor`, and available on the Anthropic API only. It has no tool name that `tools:`, permission rules, or hook matchers can reference, so the advisor checkpoints are prose that `boss` keeps, not a gate. Subagents inherit the configured advisor when their own model passes the pairing check.
- **Spawn Depth Is Per Settings File**: Both leads need two subagent layers (`boss` → lead → specialist). `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` defaults to 3 when unset, so the pipeline works without it; `2` adds the backstop that specialists cannot spawn; `1` breaks both leads. The value in this repo's `.claude/settings.json` applies only to this repo: set it in each target project's `.claude/settings.json`, or once in `~/.claude/settings.json`.
- **Guard Path Must Exist**: Both lead guards are wired with `onFailure: "block"`. If `~/.claude/hooks/agent-allowlist-guard.sh` is missing — for example after a `git pull` that added it, before `scripts/sync-claude-config.sh` is re-run — every `Agent` call from either lead is blocked until the script is linked.
