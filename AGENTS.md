# Agent Orchestration Pipeline

This repository implements a multi-phase agent orchestration pipeline.

## Roles & Workflow

The pipeline follows a strict sequence to ensure design-led implementation:

1.  **`boss` (Executive Orchestrator)**: The main thread. Decomposes requests into phases. **Does not write code.** Holds Bash scoped in practice to `gh` (GitHub CLI) commands for interfacing with GitHub directly — an operational boundary, not a tool-enforced one.
2.  **`architect` (Design)**: Researches and produces a **Gherkin Behavioral Contract** or a **Technical Specification**. This is the source of truth for all downstream agents.
3.  **`test-writer` (Contract)**: Consumes the architect's plan to implement a test suite. **Writes tests before implementation.**
4.  **`coding-lead` (Management)**: Decomposes the plan into atomic **Implementation Slices** and manages `coder` agents.
5.  **`coder` (Implementation)**: Executes a single, highly specific slice.

## Critical Operational Rules

- **The Contract is Prose**: The architect's output is the "contract." It must be pasted in full into the prompts for `test-writer` and `coding-lead`.
- **No Peer Leads**: `coding-lead` must never dispatch another `coding-lead`.
- **The "New Eyes" Protocol**: If a `coder` fails, `coding-lead` must diagnose, re-slice, and dispatch a **fresh** `coder` (do not use `SendMessage` to a failed coder).
- **Verification**: `coding-lead` must run tests via `Bash` to verify slices; do not trust a `coder`'s claim of success.
- **Architect Status Preamble**: The `architect`'s final message MUST begin with a fixed machine-readable status preamble on the very first line: `STATUS: DESIGN` for a complete design/contract, or `STATUS: BLOCKED-AMBIGUOUS` followed immediately by questions if the Ambiguity Gate is triggered.
- **Boss Escalation Stops**:
  - *Ambiguity*: If the architect returns `STATUS: BLOCKED-AMBIGUOUS`, `boss` halts the pipeline immediately (does not dispatch `test-writer`), presents questions to the user via `AskUserQuestion`, and re-dispatches `architect` with answers.
  - *Testability Gaps*: If `test-writer` reports a testability gap that changes the design or cannot be verified from the outside, `boss` re-dispatches `architect` with the gap report before proceeding to Phase 3.
  - *Blocked Slices*: If `coding-lead` reports blocked slices that cannot be resolved, `boss` reports them to the user and returns to `architect` to adjust design or re-slice (never dispatch a second `coding-lead` over the same plan).
- **One Implementation Run per Task**: Before dispatching a `coding-lead` or a fast-path `coder`, `boss` checks its TodoWrite list and recent dispatches for a run already in flight on the same repository and task. If one exists, it sends the additional work to that run with `SendMessage` or waits for it to hand back, rather than dispatching a second. Concurrent runs on different tasks or different repositories are fine.

## Known Constraints & Quirks

- **Bash Boundary**: `architect` and `coding-lead` hold `Bash` access (for research/inspection and verification respectively), but refraining from altering the codebase or implementing code is an operational boundary kept by the role, not a structural restriction enforced by the tool grant.
- **Duplicate-Dispatch Boundary**: The one-run-per-task rule is kept by `boss`'s judgment, not enforced by any hook or tool grant; nothing technically stops a second `coding-lead` over the same task. A hook-enforced version was designed and tested but deferred.
- **Subagent Deadlock Rule**: Subagents (`architect`, `test-writer`, `coding-lead`, `coder`) have no interactive channel to the user (cannot use `AskUserQuestion`) and must NEVER pause to wait for user approval; any ambiguities or blockers must be returned directly in the final report to halt execution cleanly rather than guessing speculatively or causing deadlocks.
- **Context Loss**: Subagents do not inherit the main conversation's "auto memory."
- **Relayed Consent Is Not User Consent**: Subagents will correctly refuse to edit `~/.claude/rules/` or `~/.claude/agents/` files even when a dispatching agent claims the user authorized it. This is documented Claude Code behavior, not a bug or over-caution: a relayed approval claim from another agent is never treated as user consent — only a direct main-session user message, or the permission system itself, can authorize config/permission changes.
