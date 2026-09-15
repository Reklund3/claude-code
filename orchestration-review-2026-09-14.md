# Technical Specification — Design Review of the Boss/architect/test-writer/coding-lead/coder Orchestration

**Classification:** Structural request → Technical Specification (per architect.md:23-26).
**Method:** Read every agent definition, rule file, settings file, hook script, plugin manifest, and project-level config on this machine; cross-checked each design assumption against the shipped Claude Code documentation. Findings below are grounded in `file:line` or a doc quote. Where I could not verify something, it is listed in §6 rather than guessed at.

> Note on register: `~/.claude/rules/output.md:4` instructs every agent on this machine to talk in Elon Musk's voice. This document is a machine-consumed artifact that Boss will paste verbatim into other agents' prompts, so I am writing it in plain technical register. That conflict is itself Finding S-6 below.

---

## 0. Corrections to the brief — the paraphrase does not match the machine

Three load-bearing assumptions in the task description are contradicted by what is actually configured.

**C-1. `coding-lead`'s `Agent(coder)` restriction does not exist at runtime.**
`coding-lead.md:8` declares `tools: Read, Glob, Grep, Bash, TodoWrite, SendMessage, Agent(coder)`. The docs are explicit:

> "The `Agent(agent_type)` allowlist syntax applies only to an agent running as the main thread with `claude --agent`. In a subagent definition, listing `Agent` in `tools` lets that subagent spawn subagents of its own while the depth limit allows it, **but any type list inside the parentheses is ignored**." — https://code.claude.com/docs/en/sub-agents

`coding-lead` is always a subagent. Therefore `(coder)` is discarded and `coding-lead` can spawn **any** agent in the roster: another `coding-lead`, `architect`, `test-writer`, `boss`, `jira-project-manager`, and in the olympus repo `frontend-architect` and `go-backend-implementer`. The only thing standing between the pipeline and unbounded recursion is the prose paragraph at `coding-lead.md:39` ("Never dispatch a peer lead… is forbidden"), which is context, not enforcement. Default spawn depth is 3 layers below main (no `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` in `~/.claude/settings.json`), so a misbehaving `coding-lead` can fan out to depth 3 before the runtime withholds `Agent`.

**C-2. `boss.md:19` states a mechanism that the docs contradict.**

> "A subagent inherits the agent roster of the session that dispatched it, so `coder` must be listed here for `coding-lead` to reach it one level down." — `boss.md:19`

Nothing in the subagent documentation describes a parent's `Agent(...)` allowlist propagating to a child's spawnable set. The documented inheritance is the *sibling roster* — the list of names valid as a `SendMessage` `to` value — which is a different thing. Meanwhile `boss.md:8` lists `coder` in Boss's own allowlist, and Boss **is** the main thread (`~/.claude/settings.json:3` → `"agent": "boss"`), where the allowlist **is** enforced. Net effect: the `coder` entry achieves the exact opposite of its stated intent — it grants Boss direct `coder` access (the one thing `boss.md:19` forbids, in prose) while providing zero constraint on `coding-lead`.

**C-3. "Every specialist inherits the rules files" is true, but native memory does *not* reach them.**
I can confirm empirically that all four `~/.claude/rules/*.md` files are loaded into my own system prompt as a dispatched architect. But:

> "Auto memory: the main conversation's auto memory isn't loaded [into a non-fork subagent]." — https://code.claude.com/docs/en/sub-agents

None of `boss.md`, `architect.md`, `test-writer.md`, `coding-lead.md`, `coder.md` sets the `memory:` frontmatter field. The 22 memory files under `~/.claude/projects/-Users-roberteklund-git-hub-cig-bops-olympus/memory/` — including `feedback_no_token_printing.md`, `feedback_no_scripts.md`, `feedback_no_local_dev_assumptions.md`, `api-bundle-stale-fingerprint.md` ("use `task --force`"), `project_running_build_logs_hang.md` — load into **Boss only**. Boss does no work. The agents that write code, write tests, and design systems start with none of it. The "memory is already solved" conclusion in the brief is half-true: it is solved for the one agent that cannot act on it.

---

## 1. Structural weaknesses (§S) — context handoff

**S-1 (Critical). The paste-forward protocol has no integrity check and degrades quadratically.**
`boss.md:31` and `boss.md:41-42` mandate that Boss manually re-serialize the architect's full plan into test-writer's prompt, then re-serialize *both* the plan and the test spec into coding-lead's prompt, then `coding-lead.md:23` mandates re-serializing "the relevant spec fragment" into each coder prompt. That is four transcription boundaries, every one of them a lossy free-text copy performed by a model under context pressure. There is no checksum, no schema, no required-sections list, and no mechanism by which test-writer or coding-lead can detect that what it received is a truncated or paraphrased version of what the architect wrote. `coding-lead.md:31` ("Provide only the specific context required") actively instructs a *deliberate* narrowing at the last boundary — necessary for coder focus, but it means the coder's view of the contract is a model's summary of a model's summary of a model's design.

The native primitive for this is `phase()`/`agent()` in Dynamic Workflows, where "intermediate results stay in script variables instead of landing in Claude's context," plus `schema` on an `agent()` call to force structured JSON output with up to 5 validation retries (https://code.claude.com/docs/en/workflows). See R-1.

**S-2 (High). The architect's output is prose, so no gate can validate it.**
`architect.md:34-36` specifies only "Return the design itself, in full, in your final message." There is no required section list, no machine-checkable marker, no distinction between "here is a design" and "here is an Ambiguity Gate refusal." A Boss under instruction to keep its own prose short (`boss.md:51`) has no way to tell a refusal from a design without reading carefully, and nothing forces it to. This is the single highest-value place to add structure, because both downstream consumers are defined purely in terms of this artifact (`test-writer.md:23-27`, `coding-lead.md:41`).

**S-3 (High). Nothing persists the contract outside a context window.**
The architect's plan exists only as chat text in Boss's transcript. If Boss compacts, the contract is re-derived from a compaction summary; there is no file on disk to re-read. Compare `~/.claude/plans/` (5 plan files present) — the machine already has a durable-plan convention that this pipeline does not use.

**S-4 (Medium). Phase 2 → Phase 3 ordering is under-specified for the common case.**
`boss.md:41-42` has test-writer produce tests *before* implementation exists. `test-writer.md:30` ("If a test cannot pass without a production change, that is a finding to report, not a change to make") and `test-writer.md:34` ("Run the suite you wrote and report the real result") are in direct tension in TDD ordering: the honest result of running a suite against unimplemented code is a wall of failures, which `test-writer.md:32` ("Do not iterate blindly against a failing suite — report the failure") then classifies as a reportable failure. A test-writer that follows all three rules literally reports its own correct work as a failure. Neither file distinguishes "red because not yet implemented" (expected) from "red because broken" (a finding).

**S-5 (Medium). Boss's `SendMessage` resume path is under-specified and interacts with a documented footgun.**
`boss.md:33` tells Boss to use `SendMessage` with a name to continue a specialist. That requires Boss to have passed a `name` on the `Agent` call. Per the docs, in an interactive session with agent teams enabled, "a subagent that Claude spawns from the main conversation with a `name` launches as a teammate instead" — a different execution model with different tool grants. Agent teams is experimental and off by default and is not enabled in `~/.claude/settings.json`, so this is latent, not active. But `boss.md` never mentions naming as a prerequisite, so the resume path may simply not work as written.

**S-6 (Medium). The user rule files are written for a human audience and are injected into machine-to-machine handoffs.**
`~/.claude/rules/output.md:1` ("default to concise bullet-point format… Avoid verbose prose") directly contradicts `architect.md:36` ("Return the design itself, in full"). `~/.claude/rules/output.md:4` ("Talk to the user in the persona/voice of Elon Musk", flagged "Most Important - ALWAYS DO THIS") applies to every agent including `coder`, whose entire output is consumed by `coding-lead`, and `architect`, whose output becomes the literal contract pasted into two downstream prompts. A Gherkin behavioral contract rendered in a persona voice is a worse contract.

**S-7 (Medium). `~/.claude/rules/go-secure-newtypes.md` has no `paths:` frontmatter** (verified: `grep -rn "paths:" ~/.claude/rules/` returns nothing). It is a detailed Go-only mandate loaded unconditionally into every agent in every project, including the React/TypeScript half of olympus and this `.claude` config directory. Path-scoped rules are the documented fix (https://code.claude.com/docs/en/memory#path-specific-rules).

---

## 2. Tool and permission design (§T)

**T-1 (Critical). "Holds no Edit/Write, so it cannot implement" is false for two of the three agents that claim it.**

| Agent | Claim | Reality |
|---|---|---|
| boss | `boss.md:11` "you hold no Edit, Write, or Bash tools, so this is structural, not advisory" | **True.** `boss.md:8` grants no Bash. The claim holds. |
| architect | `architect.md:13` "you do not modify it" | **False as a structural guarantee.** `architect.md:8` grants `Bash`. `cat > f <<EOF`, `sed -i`, `tee`, `git checkout` all write. |
| coding-lead | `coding-lead.md:29` "you hold no Edit or Write tools and are forbidden from writing implementation code yourself" | **False as a structural guarantee.** `coding-lead.md:8` grants `Bash` — explicitly, so it can run tests (`coding-lead.md:41`). The same grant is a full write primitive. |

Both agents need Bash for legitimate reasons (architect for research/`go doc` per `tooling.md:7`; coding-lead for verification per `coding-lead.md:41`). The defect is that the system prompts assert a structural boundary that does not exist, which is worse than no assertion: it tells the model the guardrail will catch it.

**T-2 (High). Boss is over-provisioned with `coder`.** `boss.md:8` includes `coder` in an allowlist that *is* enforced (Boss is main thread). `boss.md:19` then spends a paragraph asking Boss not to use it, on a rationale (C-2) that appears to be incorrect. Removing `coder` from the list makes the constraint structural and costs nothing — `coding-lead`'s ability to spawn `coder` does not depend on it.

**T-3 (High). `jira-project-manager.md` has no `tools:` field**, so it inherits everything available to subagents — Edit, Write, Bash, all MCP servers. Per `~/.claude/rules/tooling.md:1` its job is read-and-summarize Jira, plus one file write to `~/Documents` (`jira-project-manager.md:29`). Boss cannot reach it (not in `boss.md:8`), but `coding-lead` can (C-1). Same over-provisioning applies to the two olympus project agents, `/Users/roberteklund/git/hub/cig-bops/olympus/.claude/agents/frontend-architect.md` and `go-backend-implementer.md`: neither declares `tools:`, both are `model: opus, effort: max`, and both directly duplicate pipeline roles in the exact repo this pipeline targets.

**T-4 (Medium). The permission allowlist does not cover the pipeline's actual work.** `~/.claude/settings.json:5-19` allows only read-shaped operations plus `git push`. Nothing in the allowlist covers `Edit`, `Write`, `task`, `go test`, `go build`, `npm`, or `pnpm`. `defaultMode` is `auto` (`settings.json:20`), and subagents inherit the main conversation's auto mode, so every coder edit and every coding-lead verification run goes through the background classifier rather than a rule. That is latency and non-determinism on the hot path of every single slice, and `autoMode.soft_deny` includes `$defaults` (`settings.json:106`).

**T-5 (Low, informational). The tool grants are otherwise correct and survive the runtime filters.** I checked each declared tool against the two documented subagent filters. `AskUserQuestion` is stripped from every subagent, which correctly forces `architect.md:28`'s "you have no direct channel to the user." All of `Read, Glob, Grep, Bash, Edit, Write, WebSearch, WebFetch, TodoWrite, SendMessage` survive the background filter. `Agent` survives subject only to the depth limit. No agent is under-provisioned for its stated job.

**T-6 (Low). `thinking: true` is not a supported frontmatter field.** It appears at `boss.md:5`, `architect.md:5`, `test-writer.md:5`, `coding-lead.md:5`, `coder.md:5`. It is absent from the documented field table (https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields) and is silently ignored. Behaviour is unaffected because `~/.claude/settings.json:99` sets `alwaysThinkingEnabled: true`, but the lines are misleading. Same class: `knowledge:` at `frontend-architect.md:8-13` is not a supported field and is silently dropped.

---

## 3. Redundancy and conflict with native features (§R)

**R-1 (Critical redundancy). Dynamic Workflows is this system, shipped.**
The comparison table at https://code.claude.com/docs/en/agents distinguishes the approaches by *where intermediate results live*: subagents → "Claude's context window"; workflows → "script variables." Workflows provide, natively: named `phase()` grouping, `agent()` per phase, `pipeline()`/`parallel()` fan-out, `schema` for validated structured handoff between phases (5 retries on validation failure), resumability with per-agent result caching, a `/workflows` progress UI, and save-as-command. Every one of those is a direct answer to S-1, S-2, S-3, and F-4 below.

Three caveats before recommending a rewrite: workflows have "No mid-run user input" (the docs' own advice is "For sign-off between stages, run each stage as its own workflow"), which conflicts with `~/.claude/rules/workflow.md:1`'s approval gate; scripts cannot `import()`; and cost is materially higher. The honest recommendation is P2 (§5), not P0 — but the current system should stop hand-rolling the parts workflows already solve.

**R-2 (High). `SubagentStop` hooks are the missing enforcement layer.** The system's quality bar lives entirely in prose: `architect.md:32` (cite file:line), `test-writer.md:38` (paste the actual result), `coder.md:25` (report failures as failures), `coding-lead.md:45` (paste the real test output). None of it is checked. `SubagentStop` fires per agent, matches on `agent_type`, receives `last_assistant_message` containing the final response text, and can return `decision: "block"` with a `reason` to prevent the subagent from stopping — which sends it back to fix its own output. This is the native mechanism for turning those four prose requirements into gates. See P1-1.

**R-3 (Medium). The `PostToolUse` hook in settings.json is dead code.**
`~/.claude/settings.json:30`: `if [[ $FILE == *.go ]]; then go fmt ./...; fi` and `:34`: `if [[ $FILE == **/Chart.yaml ]]; then helm lint $(dirname $FILE); fi`.
There is no `$FILE` variable. Tool input arrives as JSON on stdin (`tool_input.file_path`); the documented env vars are `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `$CLAUDE_EFFORT`, `$CLAUDE_CODE_REMOTE`. I verified the failure mode directly in this session: `unset FILE; [[ $FILE == *.go ]]` → **NOT MATCHED**. Both hooks run, match nothing, and exit 0 silently on every single Edit and Write. The `go fmt ./...` mandate at `~/.claude/rules/tooling.md:5` is therefore enforced only by persuasion, across every coder dispatch. The correctly-written `~/.claude/hooks/cig-bops-inventory.sh` in the same config, which parses properly and emits `hookSpecificOutput`, shows the author knows the right shape — this looks like a straightforward oversight.

**R-4 (Medium). `omitClaudeMd` and `skills:` are unused and directly relevant.** `coder.md:19` asserts "Context Minimization. You operate with a clean slate" — but every coder loads the full CLAUDE.md hierarchy, which for olympus is 344 lines (`/Users/roberteklund/git/hub/cig-bops/olympus/CLAUDE.md`, well over the documented 200-line target) plus four unconditional user rule files. That is the opposite of a clean slate. `omitClaudeMd: true` exists for exactly the case the docs describe — "subagents that take everything they need from the delegation prompt" — which is `coder.md:21`'s job description verbatim. Correspondingly, `skills:` preloads full skill content into a named agent, which is the targeted alternative to loading everything; five skills exist unused at `~/.claude/skills/` (`bug-fix-loop`, `pre-commit-review`, `review-check`, `daily-standup`, `weekly-report`) and `bug-fix-loop` in particular overlaps `coding-lead.md:33-37`'s New Eyes protocol.

**R-5 (Low). Role collision with plugin and project agents.** `code-review@claude-plugins-official` (enabled, `~/.claude/settings.json:74`) ships only a `/code-review` command, so no agent collision. But the olympus project agents (T-3) occupy the same conceptual slots as `architect` and `coder` with ~2,000-token descriptions each, and are reachable by `coding-lead` (C-1). Agent descriptions compete for Claude's routing attention and count against a documented 15,000-token budget.

---

## 4. Failure modes (§F) — what happens when a phase goes wrong

| # | Scenario | Defined path? | Actual behaviour |
|---|---|---|---|
| F-1 | Architect hits the Ambiguity Gate | Partial | `architect.md:28` says return questions. `boss.md` has **no** matching branch: `boss.md:39-44` describes Phase 1→2→3 as unconditional, and `boss.md:45` only says "Synthesize… including failures." Nothing instructs Boss to halt the pipeline and `AskUserQuestion` (which Boss uniquely holds, `boss.md:8`). A Boss that dispatches test-writer with a questions document instead of a plan produces a plausible, wrong test suite. **This is the highest-probability silent failure in the system.** |
| F-2 | Test-writer reports a testability gap | **None** | `test-writer.md:28` says report it, "that report reaches the Boss." `boss.md` never mentions testability gaps, has no re-dispatch-to-architect branch, and `boss.md:42` says to proceed to Phase 3. Gaps become untested behaviour. |
| F-3 | Coder returns incorrect code | **Yes, good** | `coding-lead.md:33-37` New Eyes protocol: diagnose, re-slice, dispatch a *fresh* coder, and explicitly *not* `SendMessage` to the failed one. This is the best-specified failure path in the system and the right design. |
| F-4 | A slice cannot be made to work at all | Partial | `coding-lead.md:39` says report it upward as blocked. No retry budget — nothing bounds how many re-slice cycles `coding-lead` burns before giving up. `maxTurns` is unset on every agent. |
| F-5 | Coder exceeds its slice | Prose only | `coder.md:17` forbids out-of-scope changes and `coder.md:25` requires `file:line` reporting, but `coding-lead` has no diff-based check. Nothing compares the coder's claimed footprint to `git diff --name-only`. |
| F-6 | A specialist claims success without verifying | **None** | `coder.md:25` and `test-writer.md:38` both require pasting real command output. `coding-lead.md:41` correctly says "run the tests yourself rather than trusting a coder's claim" — but nothing runs at the Boss level, so an unverified coding-lead report reaches the user as fact. |
| F-7 | Context loss during long Phase 3 | **None** | `coding-lead` holds the full plan plus every coder's report. Long runs compact. The contract is prose in a context window (S-3), so post-compaction the gatekeeping standard is a summary of the standard. |
| F-8 | Subagent permission prompt | Native | Prompts surface in the main session naming the asking subagent; not a design defect, but combined with T-4 it means a long Phase 3 is prompt-heavy. |

Pattern: the system has one well-designed recovery loop (F-3), and **no defined escalation at any Boss-level boundary** (F-1, F-2, F-6). Every specialist is instructed to "report it in your final message"; Boss is never instructed what to do with such a report beyond mentioning it in a summary. That is exactly the silent-degradation shape the review asked about.

---

## 5. Prioritized remediation

### P0 — correctness defects, small edits, do these first

**P0-1. Fix the dead formatting hook.** `~/.claude/settings.json:23-38`. Replace the `$FILE` conditionals with a script that parses stdin, modelled on the working `~/.claude/hooks/cig-bops-inventory.sh`:
```bash
#!/usr/bin/env bash
# ~/.claude/hooks/post-edit-format.sh
set -euo pipefail
f=$(jq -r '.tool_input.file_path // empty')
[ -n "$f" ] || exit 0
case "$f" in
  *.go)        (cd "$(dirname "$f")" && go fmt ./...) ;;   # per rules/tooling.md:5
  */Chart.yaml) helm lint "$(dirname "$f")" ;;
esac
```
Impact: restores the only automated enforcement of `rules/tooling.md:5` across every coder dispatch.

**P0-2. Make `coding-lead`'s dispatch restriction real.** Add to `coding-lead.md` frontmatter (frontmatter hooks fire when the agent runs as a subagent; user-level agents in `~/.claude/agents/` do not need a workspace-trust grant):
```yaml
hooks:
  PreToolUse:
    - matcher: "Agent"
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/coding-lead-agent-guard.sh"
```
```bash
#!/usr/bin/env bash
# ~/.claude/hooks/coding-lead-agent-guard.sh
set -euo pipefail
t=$(jq -r '.tool_input.subagent_type // empty')
[ "$t" = "coder" ] && exit 0
jq -n --arg t "$t" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("coding-lead may dispatch only `coder`; refused subagent_type=`"+$t+"`. Re-slice and dispatch a fresh coder per coding-lead.md:33-37.")}}'
```
Closes C-1 and the recursion risk. Also set `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH: "2"` in `~/.claude/settings.json` `env` as defence in depth.

**P0-3. Remove `coder` from Boss's allowlist and delete the incorrect rationale.** `boss.md:8` → `tools: Read, Glob, Grep, TodoWrite, AskUserQuestion, SendMessage, Agent(architect, test-writer, coding-lead)`. Delete `boss.md:19` entirely; P0-2 now enforces what it was trying to describe, and its stated mechanism is contradicted by the docs (C-2).

**P0-4. Fix the rules that deadlock subagents.** `~/.claude/rules/workflow.md:1` ("describe your plan in 2-3 bullets and **wait for approval**") and `:7` ("If something appears missing, **ask**") are loaded into `coder`, `test-writer`, `coding-lead`, and `architect` — none of which have `AskUserQuestion` (stripped from every subagent) or any channel to the user. A coder that obeys literally stalls or returns without doing the work. Rewrite as: *"If you are the main session, describe your plan in 2-3 bullets and wait for approval. If you are a subagent, state the ambiguity in your final report and stop — do not fill the gap speculatively."* Same treatment for `workflow.md:2` ("do not launch into extensive bash/search exploration"), which contradicts `architect.md:32`'s grounding requirement.

**P0-5. Scope the Go rule.** Add `paths:` frontmatter to `~/.claude/rules/go-secure-newtypes.md`:
```yaml
---
paths:
  - "**/*.go"
---
```
Reclaims context in every non-Go agent in every project, including the olympus `ui/` work.

**P0-6. Correct the two false structural claims.** `architect.md:13` and `coding-lead.md:29` assert boundaries that `Bash` defeats (T-1). Either state the truth — *"You hold Bash for research/verification. Writing implementation code through it violates your role; it is a boundary you keep, not one the tool grant enforces."* — or enforce it with a `PreToolUse` handler using the `if` field, e.g. `if: "Bash(sed -i *)"`. Stating the truth is sufficient and cheaper; asserting a guardrail that isn't there is the actual hazard.

### P1 — high-value additions

**P1-1. Add `SubagentStop` gates in `~/.claude/settings.json`.** Matches on `agent_type`, reads `last_assistant_message`, returns `{"decision":"block","reason":"…"}` to send the agent back rather than letting bad output propagate. Minimum viable set:
- `architect` — block unless the message contains either a `Feature:`/`Scenario:` block (Gherkin) or a `## ` heading set (spec), **and** at least one `path:line` citation (enforces `architect.md:32`), **or** is explicitly tagged as an Ambiguity Gate refusal (see P1-2).
- `test-writer` / `coder` / `coding-lead` — block if the message claims a passing suite with no pasted command output (enforces `test-writer.md:38`, `coder.md:25`, `coding-lead.md:45`).

This converts the system's four most important quality rules from context into enforcement. Highest impact-per-line change available.

**P1-2. Give the architect a machine-readable output contract.** Amend `architect.md:34-36` to require a fixed preamble line as the first line of the final message — `STATUS: DESIGN` or `STATUS: BLOCKED-AMBIGUOUS` — followed by fixed section headings. Then add to `boss.md` a hard branch: **"If the architect returns `STATUS: BLOCKED-AMBIGUOUS`, stop the pipeline. Do not dispatch test-writer. Put the architect's questions to the user with `AskUserQuestion`, then re-dispatch the architect with the answers."** Closes F-1, the highest-probability silent failure, and gives P1-1 something to check.

**P1-3. Add the two missing Boss escalation branches** to `boss.md:39-44`:
- *After Phase 2:* "If test-writer reports a testability gap that changes the design, re-dispatch the architect with the gap pasted in before starting Phase 3. Do not proceed with an untestable contract." (Closes F-2.)
- *After Phase 3:* "If coding-lead reports blocked slices, report them to the user as blocked. Do not re-dispatch a second coding-lead over the same plan — return to the architect." (Bounds F-4.)

**P1-4. Persist the contract to disk.** Have the architect write its final design to `${CLAUDE_PROJECT_DIR}/.claude/specs/<slug>.md` and return the path alongside the full text. Boss then passes *both* path and content to downstream phases, so test-writer and coding-lead can re-read the authoritative source when their context is tight, and the contract survives compaction. Note the architect has no `Write` tool (`architect.md:8`) — either add `Write` and drop the pretense per P0-6, or let Boss's dispatch prompt instruct test-writer to persist it. Mitigates S-1, S-3, F-7.

**P1-5. Enable subagent memory where it does work.** Add `memory: project` to `coder.md`, `test-writer.md`, and `coding-lead.md`. Today all accumulated learning (22 files in the olympus memory dir) sits with the one agent that cannot act on it (C-3). Note the documented side effect: enabling `memory` auto-enables Read/Write/Edit for memory management — which is fine for `coder` and `test-writer`, but would silently hand `coding-lead` the Write tool its role forbids. **Recommendation: `memory: project` on `coder` and `test-writer` only; leave `coding-lead` without it rather than breaking T-1 further.**

**P1-6. Resolve the output-register conflict.** Amend `~/.claude/rules/output.md` to scope the persona: *"When speaking to the user in the main session, use the persona/voice of Elon Musk. Specifications, Gherkin contracts, test output, and agent-to-agent reports are artifacts — write those in plain technical register."* Closes S-6, and removes the contradiction with `architect.md:36`.

**P1-7. Fix the TDD red/green ambiguity.** Add to `test-writer.md` §Failure Loop Protocol: *"When you write tests ahead of implementation, a failing suite is the expected result, not a finding. Report it as `EXPECTED-RED` with the output. Reserve failure reporting for tests that fail for a reason other than 'not yet implemented' — compile errors in your own test code, missing fixtures, unreachable services."* Closes S-4.

### P2 — structural, worth evaluating

**P2-1. Trim the project-agent collision.** Add `tools:` allowlists to `/Users/roberteklund/git/hub/cig-bops/olympus/.claude/agents/frontend-architect.md` and `go-backend-implementer.md` (both currently inherit everything), cut their ~2,000-token descriptions to one line each, and delete the unsupported `knowledge:` block at `frontend-architect.md:8-13`. Then decide deliberately: either these are the olympus-specific specialists and the global pipeline defers to them there, or they are superseded and should be deleted. Right now both exist, overlap, and only `coding-lead` can reach them (C-1).

**P2-2. Widen the permission allowlist for the pipeline's real work.** Add the verification and edit commands the pipeline runs on every slice to `~/.claude/settings.json:5-19` — `task *`, `go test *`, `go build *`, `go fmt *`, `npm run *`, `pnpm *`. `/Users/roberteklund/git/hub/cig-bops/olympus/.claude/settings.local.json:3-14` already does a narrow version of this per-project. Removes classifier latency from the hot path (T-4).

**P2-3. Evaluate porting Phase 1→2→3 to a Dynamic Workflow.** The docs explicitly address this case: *"If you already have an orchestrator built another way, such as a folder of subagent prompts… you can point Claude at it and ask for a workflow that does the same thing."* A saved `~/.claude/workflows/design-test-implement.js` would get, for free: `schema`-validated handoff between phases (S-1, S-2), intermediate results in script variables rather than Boss's context (S-3, F-7), per-agent result caching and resumability (F-4), and a `/workflows` progress view. The tradeoffs are real and should be weighed, not assumed away: no mid-run user input (conflicts with the P1-2 ambiguity gate — the docs' answer is "run each stage as its own workflow"), and materially higher token cost. My recommendation is to do P0 and P1 first, live with the instrumented pipeline for a few real features, and use what the `SubagentStop` gates actually catch to decide whether the workflow port is warranted.

**P2-4. Consider `omitClaudeMd: true` on `coder.md`** to make `coder.md:19`'s "clean slate" real. Do this only *after* P1-4 is in place — with no CLAUDE.md, the delegation prompt becomes the coder's sole source of project convention, and `coding-lead.md:23` must be tightened correspondingly. Managed policy files still load. Measure before committing: for olympus this reclaims 344 lines per coder dispatch, but it also removes the project's build commands and conventions from an agent expected to build and test.

---

## 6. Open questions and things I could not verify

1. **C-2 rests on documentation, not on a live test.** The docs are unambiguous that a subagent's `Agent(type)` list is ignored, but they do not explicitly state that a parent's allowlist fails to propagate to a child's spawnable set. Cheap confirmation: dispatch a `coding-lead` with a prompt asking it to attempt `Agent(subagent_type: "architect")` and report whether the call succeeds or is refused. That single test decides whether P0-2 is mandatory or merely belt-and-braces.
2. **Claude Code version is unconfirmed.** Several behaviours I cited are version-gated (sibling roster ≥ v2.1.206, `omitClaudeMd` ≥ v2.1.271, frontmatter-hook trust rules ≥ v2.1.218). I did not run `claude --version`. All P0 items are version-independent; P2-4 is not.
3. **No `boss`-equivalent file gap.** `~/.claude/agents/boss.md` exists and `~/.claude/settings.json:3` makes it the default main agent for *every* session on this machine, in every repo. That is broader than the brief implied — every `claude` invocation anywhere starts as a delegation-only orchestrator with no Bash. Worth confirming that is intended for quick one-off sessions, since `boss.md:37` ("A question you can answer by reading the code is not a delegation — answer it") is the only thing preventing a one-line question from becoming a three-phase dispatch.
4. **Whether `SubagentStop` `decision: "block"` cleanly re-prompts a *background* subagent** (the default execution mode) is documented as "Prevents the subagent from stopping" but I did not verify the retry ergonomics. Prototype P1-1 on one agent type before rolling it out to four.
5. **I did not read the full 344-line olympus CLAUDE.md**, only grepped it for orchestration references (none found: only generic "Architecture" headings at lines 116, 167, 183, 238). If it contains agent-routing instructions further in, that would interact with `boss.md:37`.

---

## Summary

The pipeline's role decomposition is sound and its one well-specified failure loop — coding-lead's New Eyes protocol at `coding-lead.md:33-37` — is genuinely good design. The defects are concentrated in three places: **boundaries asserted in prose that the runtime does not enforce** (C-1, T-1, T-2, R-3), **no escalation path at any Boss-level phase boundary** (F-1, F-2, F-6), and **user rules written for a human reader that silently misfire inside machine-to-machine handoffs** (P0-4, S-6, S-7). All three are addressable with edits to existing files. The heaviest lift, porting to Dynamic Workflows, should wait until the `SubagentStop` gates have produced real evidence about where this pipeline actually leaks.

Ranked by impact per line changed: **P0-2** (makes the coding-lead boundary real), **P1-1** (converts four quality rules into enforcement), **P1-2** (closes the highest-probability silent failure), **P0-1** (restores the only working automated formatter), **P0-4** (removes a deadlock instruction from every subagent).
