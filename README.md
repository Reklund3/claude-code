# Agent Orchestration Pipeline

A multi-phase, design-led agent orchestration pipeline designed for use with [Claude Code](https://code.claude.com).

This repository provides a structured framework for decomposing complex software engineering tasks into manageable, verifiable, and high-quality implementation slices. By enforcing a strict sequence of design, testing, and implementation, the pipeline minimizes guesswork and ensures that every change is grounded in a formal contract.

## The Workflow

The pipeline follows a three-phase execution model:

1.  **Phase 1: Design (Architect)**
    The `architect` researches the codebase and produces either a **Gherkin Behavioral Contract** (for user flows) or a **Technical Specification** (for structural changes). This document serves as the single source of truth for all subsequent phases.

2.  **Phase 2: Contract (Test-Lead & Test Specialists)**
    The `test-lead` detects the target project's test stack, assigns every behavior in the architect's design to exactly one specialist in a coverage map (`gherkin-writer` for named behaviors when the project has a Gherkin runner, `parameter-tester` for input spaces, `test-writer` for the rest), and dispatches and verifies them. This establishes the "Contract of Success" *before* any implementation code is written; the new tests are expected to fail (`EXPECTED-RED`) until Phase 3.

3.  **Phase 3: Implementation (Coding-Lead & Coder)**
    The `coding-lead` decomposes the design and the test-lead's coverage map into atomic **Implementation Slices**. These slices are then dispatched to `coder` agents, which execute them with surgical precision. The `coding-lead` verifies each slice against the design and the test suite before proceeding.

## Agent Roles

| Agent | Role | Core Mission |
| :--- | :--- | :--- |
| **`boss`** | Executive Orchestrator | Decomposes requests into phases and manages the high-level pipeline. |
| **`architect`** | Senior Architect | Translates requirements into structured technical designs and specifications. |
| **`test-lead`** | Test Lead | Slices the contract into test slices, assigns each behavior to one specialist, and gates their output. |
| **`gherkin-writer`** | Gherkin Specialist | Writes `.feature` files and step definitions for the project's existing Gherkin runner. |
| **`parameter-tester`** | Input-Space Specialist | Writes table-driven or property-style tests in the project's idiom. |
| **`test-writer`** | Generic Test Specialist | Writes the tests that are neither Gherkin nor parameterized. |
| **`coding-lead`** | Technical Lead | Manages implementation by slicing tasks and overseeing `coder` agents. |
| **`coder`** | Implementation Specialist | Executes specific, atomic slices of code with minimal side effects. |
| **`docs`** | Reference Lookup | Pulls API reference pages verbatim, read-only, for `boss`. |
| **`mutation-tester`** | On-Demand Mutation Tester | Run by the user after opening a PR; reports surviving mutants; gates nothing. |

## Key Principles

- **Design-Led Implementation**: No code is written until a formal design and test contract exist.
- **Atomic Slicing**: Complex tasks are broken down into the smallest possible verifiable units of work.
- **The "New Eyes" Protocol**: Failed implementation attempts are met with re-diagnosis and re-slicing, rather than repetitive instruction.
- **Verification-First**: Every implementation slice must be verified against the established test contract.

## Critical Operational Rules

- **Architect Output Contract**: The `architect`'s final message MUST begin with a fixed machine-readable status preamble on the very first line: `STATUS: DESIGN` for a complete design/contract, or `STATUS: BLOCKED-AMBIGUOUS` followed immediately by questions if the Ambiguity Gate is triggered.
- **Boss Escalation Stops**:
  - *Ambiguity*: If the architect returns `STATUS: BLOCKED-AMBIGUOUS`, `boss` halts the pipeline immediately (does not dispatch `test-lead`), presents questions to the user via `AskUserQuestion`, and re-dispatches `architect` with answers.
  - *Testability Gaps*: If `test-lead` returns `TEST-STATUS: GAPS`, `boss` re-dispatches `architect` with the `GAP:` lines before proceeding to Phase 3.
  - *Blocked Slices*: If `coding-lead` or `test-lead` reports blocked slices that cannot be resolved, `boss` reports them to the user and returns to `architect` to adjust design or re-slice (never dispatch a second lead of the same type over the same plan).
- **One Implementation Run per Task**: `boss` does not dispatch a second `coding-lead`, `test-lead`, or fast-path `coder` for a repository and task that already has a run in flight; it uses `SendMessage` to that run or waits. Parallel runs on different tasks or repositories are unaffected. This is an operational rule kept by `boss`, not a hook-enforced guard.
- **Two-Strike Stop**: If the same failure (same failing test or command, same error signature) recurs on a slice after one fresh re-dispatch, the lead (`coding-lead` or `test-lead`) stops that slice and reports it on a line beginning `BLOCKED:` with both verification outputs pasted. It never dispatches a third agent for that slice. `boss` then follows the Blocked Slices escalation.
- **Advisor Checkpoints (`boss` only)**: When an `advisor` tool is available, `boss` consults it (1) on a `coding-lead` or `test-lead` hand-back with a `BLOCKED:` slice, before choosing the next step, and (2) before its final synthesis of any request that dispatched `architect`, `test-lead`, `coding-lead`, or `coder`. There is no boss-side checkpoint before a plan locks, because `architect` already runs on Opus. Other agents do not take these checkpoints from this file; their own definitions govern them.

## Guards & Operational Boundaries

- **Structural Guards (`coding-lead`, `test-lead`)**: Each lead's frontmatter wires `hooks/agent-allowlist-guard.sh` with its allowed specialist types as arguments: `coder` for `coding-lead`; `gherkin-writer`, `parameter-tester`, and `test-writer` for `test-lead`. The guard denies every other type and blocks the call if it cannot run (fail-closed, `onFailure: "block"`).
- **Bash Boundary**: Operational role boundary rather than structural tool restriction: `architect`, `coding-lead`, and `test-lead` hold `Bash` tool access (for research/inspection, verification, and detection/verification respectively), but refraining from altering codebase files or writing implementation code is an operational boundary maintained by role discipline, not a structural tool restriction. `mutation-tester` holds `Bash` and no Edit or Write; that it writes only inside its scratch run directory is likewise an operational boundary, checked by its before/after snapshot of the working tree.

## Usage

This repository contains agent definitions (found in `/agents`) intended to be used as part of a Claude Code session.

For concrete installation steps — copying the agent files and hooks into place, and wiring `settings.json` — see [SETUP.md](SETUP.md).

### Task Tracking (`boss`)

`boss` tracks implementation runs with the Task tools (`TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`). On Claude 5.x models these tools are off by default, so start the session with the opt-in environment variable set:

    CLAUDE_CODE_ENABLE_TODO_TOOLS=1 claude --agent boss

Subagents never receive the Task tools, so the run ledger lives only in `boss`'s task list. If the tools are missing, `boss` falls back to its recent dispatches and tells you once.

### Advisor (optional)

`boss`'s advisor checkpoints (see [AGENTS.md](AGENTS.md)) apply only when an advisor is enabled. Enable one with `/advisor opus`, the `advisorModel` setting, or the launch flag:

    CLAUDE_CODE_ENABLE_TODO_TOOLS=1 claude --agent boss --advisor opus

The flag is not listed in `claude --help`; see https://code.claude.com/docs/en/advisor.

The advisor is experimental and needs the Anthropic API. A Haiku 5.5 main session with an Opus advisor needs Claude Code v2.1.293 or later. Under `claude --agent boss` the main thread takes the `model:` set in `agents/boss.md` (per the Claude Code subagents docs); how a model flag, `ANTHROPIC_MODEL`, or a settings `model` ranks against it is undocumented, so these launch lines set none.

### Mutation testing (on demand)

After you open a pull request, run from the repository:

    claude --agent mutation-tester            # the PR for the current branch
    claude --agent mutation-tester "PR 123"   # a specific PR

It works in a scratch git worktree under `$TMPDIR/claude-mutation/`, never in your working tree, asks before using any mutation tool your project does not already declare and before restoring dependencies in the scratch copy (both in the same question), and reports surviving mutants. It posts nothing and blocks nothing.

*Note: This is a configuration and instruction repository. It is designed to be integrated into a Claude Code environment to provide specialized agent personas and workflows.*
