---
name: forge
description: Isolated, high-quality, high-efficiency plan execution. Environment-aware, dependency-driven, adaptive. Use when you have an implementation plan to execute.
jit_keywords: forge, /forge
---

# Forge

Isolated, high-quality, high-efficiency plan execution.

**Invoke:** `/forge path/to/plan.md`

## Modes

| Mode | Invoke | Behavior |
|------|--------|----------|
| **Normal** (default) | `/forge plan.md` | Present classification table → wait for user confirmation → execute |
| **Yolo** | `/forge plan.md --yolo` | No confirmation. Sense → Analyze → Execute → Verify → Merge → Push. Fully autonomous. |

**Yolo mode** skips the confirmation checkpoint but keeps all safety nets:
- Worktree isolation still applies
- Verification gates still enforce (zero tolerance)
- Rollback still triggers on failure
- Agent pause/resume still runs

What yolo mode removes: the classification table confirmation step. Forge decides everything — classification, execution order, merge — and only stops if verification fails.

## Three Pillars

| Pillar | How |
|--------|-----|
| **Isolation** | Always work in a git worktree on a feature branch. Main stays clean. No race conditions with auto-commit agents, CI, or teammates. |
| **Quality** | Every task gets the right level of review. Subagent tasks get two-stage review (spec + code quality). Typecheck + tests gate every merge. Rollback on failure. |
| **Efficiency** | Classify tasks by uncertainty + dependency graph. Independent certain tasks run in parallel. Uncertain tasks get subagent attention. Trivial tasks run direct. No wasted cycles. |

## The Flow

```
Plan file
  |
  v
[0. SENSE]    Detect project environment — language, build/test commands, agents, conventions
  |
  v
[1. ANALYZE]  Read plan, build dependency DAG, classify each task, present table
  |
  v
[2. ISOLATE]  Create worktree + feature branch
  |
  v
[3. EXECUTE]  Run tasks respecting dependency order + classification:
  |            Subagent (uncertain) — sequential, two-stage review
  |            Parallel (certain, independent) — simultaneous
  |            Direct (trivial) — inline
  |            Adapt in real-time based on results
  |
  v
[4. VERIFY]   Run detected build + typecheck + test commands (zero tolerance)
  |
  v
[5. MERGE]    Safe merge to main — pause agents, merge, verify, resume
  |
  v
[6. PUSH]     Push to trigger CI/CD
```

---

## Phase 0: Environment Sensing

Before touching any code, sense the project environment. **Do not assume — detect.**

### LLM Capability Detection

Forge is designed for any LLM that can read files and execute shell commands. Detect your own capabilities to choose the best execution strategy.

| Capability | Check | Impact on execution |
|------------|-------|---------------------|
| **Subagent spawn** | Can you dispatch independent AI agents? (e.g., Claude Code `Agent` tool, Cursor background agents) | Yes → Parallel + Subagent modes available. No → all tasks run sequentially as Direct. |
| **Shell execution** | Can you run shell commands? | Yes → full workflow. No → forge cannot run (needs git, build, test). |
| **File read/write** | Can you read and edit files? | Required for all modes. |
| **Worktree support** | Can you `cd` into another directory and work there? | Yes → full isolation. No → use branch-only isolation (`git checkout -b`). |
| **Concurrent agents** | How many subagents can run simultaneously? | Determines max parallelism for Parallel tasks. |

**Default (Claude Code / Anthropic models):** All capabilities available. `Agent` tool for subagents with worktree isolation. Up to 4 concurrent agents.

**Fallback for limited LLMs:** If subagent spawn is unavailable, all tasks execute sequentially as Direct. The isolation + verification + merge protocol still applies — quality gates don't degrade.

```
Capability profile:
  Subagent:    yes/no  → determines Parallel/Subagent availability
  Max parallel: N      → determines batch size for Parallel tasks
  Worktree:    yes/no  → determines isolation strategy
  Shell:       yes     → required (no shell = cannot use forge)
```

### Project Profile

| Detect | How | Store as |
|--------|-----|----------|
| Language / framework | `package.json`? `Cargo.toml`? `go.mod`? `pyproject.toml`? `Makefile`? | `$LANG` |
| Build command | `"build"` script in package.json → `pnpm build`; `Makefile` → `make build`; etc. | `$BUILD_CMD` |
| Test command | `"test"` script → `pnpm test`; `pytest`; `go test ./...`; `cargo test` | `$TEST_CMD` |
| Typecheck command | `"typecheck"` script → `pnpm typecheck`; `mypy .`; `go vet ./...` | `$TYPECHECK_CMD` |
| Lint command | `"lint"` script; `eslint`; `clippy`; `golangci-lint` | `$LINT_CMD` |
| Project conventions | `CLAUDE.md`, `.cursor/rules`, `.github/copilot-instructions.md`, `CONVENTIONS.md` | Read + follow |
| Existing worktrees | `git worktree list` | Avoid name conflicts |
| Stale forge worktrees | `git worktree list \| grep -- '-dev'` | Prompt user to clean up before creating new one |

### Agent / Automation Detection

Check for anything that reacts to file changes or git events on main:

| Agent type | Detection | Implication |
|------------|-----------|-------------|
| HTTP API agent (Kuro, custom) | `curl -sf "${AGENT_URL:-http://localhost:3001}/status"` or `curl -sf "${AGENT_URL:-http://localhost:3001}/health"` | Pause before merge, resume after |
| File watcher / auto-commit | `ps aux \| grep -i "fswatch\|watchman\|nodemon\|chokidar"` or `launchctl list \| grep agent` | Worktree mandatory |
| Git hooks (post-commit, pre-push) | Check `.git/hooks/` and `.husky/` | Be aware of side effects |
| CI on push | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile` | Push triggers CI — verify before push |
| Other AI agents | `ps aux \| grep -i "cursor\|copilot\|aider\|continue"` | Worktree mandatory to avoid conflicts |

**Rule:** If any automation is detected that reacts to file changes on main → worktree is mandatory regardless of task count.

### Multi-Agent Discovery

To build `$DETECTED_AGENTS` (list of agent URLs to pause/resume during merge):

```bash
# 1. Check explicit env var
if [ -n "$AGENT_URL" ]; then AGENTS+=("$AGENT_URL"); fi

# 2. Scan common ports for HTTP API agents
for PORT in 3001 3002 3003 8001 8080; do
  if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
    AGENTS+=("http://localhost:$PORT")
  fi
done

# 3. Check project config for agent URLs
# Look in: .env, .env.local, docker-compose.yml, agent-compose.yaml
grep -h 'AGENT_URL\|agent.*url\|localhost:[0-9]' .env* 2>/dev/null
```

Store all discovered agents as `$DETECTED_AGENTS`. Merge phase iterates over all of them.

---

## Phase 1: Intelligent Plan Analysis

Read the plan file. Auto-detect task structure (headings, numbered lists, checkboxes — don't require a specific format).

### For each task, determine:

1. **Files touched** — create new vs modify existing? Read existing files to understand complexity.
2. **Dependencies** — does this task import/use output from another task? Shared types? Call sites?
3. **Uncertainty** — is the code complete in the plan, or does it say "find and update"?
4. **Scope** — how many files, how many lines of change?

### Build Dependency DAG

```
Task 1 (no deps)     Task 3 (no deps)
    |                     |
    v                     v
Task 2 (needs #1)    Task 4 (needs #1 + #3)
    |                     |
    +----------+----------+
               |
               v
           Task 5 (needs #2 + #4)
```

Tasks at the same dependency level with no shared dependencies can run simultaneously.

### Classify by reasoning

| Signal | Points toward |
|--------|---------------|
| Creates new file + plan has complete code | **Parallel** |
| Creates new file + plan is vague | **Subagent** |
| Modifies existing file (any complexity) | **Subagent** |
| Depends on previous task's output | **Subagent** (must be sequential) |
| < 10 lines, single file, no ambiguity | **Direct** |
| Independent test file with clear spec | **Parallel** |
| First task of a new pattern | **Subagent** (once proven, upgrade similar tasks) |

### Present classification table

```
| # | Task | Mode | Reason | Depends On |
|---|------|------|--------|------------|
| 1 | Validation helper | Parallel | New file, complete spec | — |
| 2 | Update registration | Subagent | Modifies existing fn | #1 |
| 3 | Add tests | Parallel | Independent test file | #1 |

Execution order:
  Level 0: #1 (Parallel)
  Level 1: #2 (Subagent) + #3 (Parallel) — simultaneously after #1 completes

Detected: TypeScript project, pnpm build/test, no agents detected.
Worktree: ../project-dev (feature/my-feature)

Proceed? (y/n)
```

**Normal mode:** User confirms or overrides before proceeding.

**Yolo mode:** Log the classification table for traceability, then proceed immediately without waiting.

---

## Phase 2: Isolate

```bash
FEATURE_NAME=$(basename "$PLAN_FILE" .md)
BRANCH="feature/$FEATURE_NAME"
WORKTREE_DIR="../$(basename $PWD)-dev"
git worktree add "$WORKTREE_DIR" -b "$BRANCH"
# All work happens in the worktree from here
```

**Skip worktree only when ALL of these are true:**
- 1-2 tasks only
- All Direct classification
- All create new files (no modifications)
- No agents or automation detected

---

## Phase 3: Adaptive Execution

Execute tasks **respecting the dependency DAG**. Strategy depends on detected LLM capabilities.

### Execution Strategy by LLM Capability

**Full capability (Claude Code — default):**

Uses Claude Code's `Agent` tool for both Subagent and Parallel modes. This is the optimized path.

| Mode | Claude Code tool | Isolation |
|------|-----------------|-----------|
| Subagent | `Agent` tool (sequential, single instance) | Shares worktree |
| Parallel | Multiple `Agent` tool calls (simultaneous, up to 4) | Each gets `isolation: "worktree"` (see note) |
| Direct | Inline (no tool) | Current worktree |

Two-stage review for Subagent tasks also uses `Agent` tool — one agent implements, separate agents review.

> **Parallel isolation note:** When using Claude Code's `Agent` tool with `isolation: "worktree"`, each parallel agent gets its own temporary worktree branched from the feature branch. Claude Code manages the creation, execution, and merge of these sub-worktrees internally. For other LLMs without this built-in mechanism, parallel tasks should share the feature worktree and be carefully ordered to avoid file conflicts.

**Partial capability (other LLMs with shell but no subagent spawn):**

All tasks execute sequentially. Classification still matters for review depth:

| Classification | Execution | Review |
|----------------|-----------|--------|
| Was-Subagent | Sequential, self-review carefully before proceeding | Run verification after each task |
| Was-Parallel | Sequential, but can batch file writes | Run verification after batch |
| Direct | Inline | Verify at end |

**Minimal capability (shell only, no file editing tools):**

Use shell commands (`cat`, `sed`, `echo >>`) for file operations. Sequential execution. Full verification protocol still applies.

### Subagent Tasks — Full Detail (Claude Code)

1. **Dispatch implementer subagent** via `Agent` tool — provide full task text + relevant file contents + project conventions
2. **Subagent implements** — explores, asks questions, writes code + tests, self-reviews
3. **Dispatch spec compliance reviewer** via `Agent` tool — does code match what the plan asked for?
4. **Dispatch code quality reviewer** via `Agent` tool — clean code, follows project conventions, no bugs?
5. **Fix loop** — if either review finds issues, dispatch fix agent, then re-review
6. **Mark complete** — move to next task

### Parallel Tasks — Full Detail (Claude Code)

- Dispatch multiple `Agent` tool calls simultaneously (respect `Max parallel` from Phase 0)
- Each agent gets: complete task spec + file paths + project conventions + test requirements
- Agents work independently, no shared state
- Collect all results, verify each passes tests

### Direct Tasks (All LLMs)

Execute trivially yourself. No subagent overhead.

### Real-Time Adaptation

Modes can change during execution based on evidence:

| Observation | Action |
|-------------|--------|
| Subagent completes easily, no questions | Upgrade similar remaining tasks → Parallel |
| Subagent asks many questions / hits complications | Keep similar remaining tasks as Subagent |
| Parallel agent fails or produces bad code | Downgrade similar remaining tasks → Subagent |
| Direct change causes test failure | Escalate → Subagent |
| Task reveals new dependency not in plan | Re-order remaining tasks |
| Verification command differs from detected | Update project profile |

---

## Phase 4: Verify

**Use the commands detected in Phase 0. Do not hardcode.**

```bash
$BUILD_CMD       # Compile / bundle
$TYPECHECK_CMD   # Type checking
$TEST_CMD        # Run tests
$LINT_CMD        # Lint (if available)
```

**Zero tolerance — all must pass before merge.**

If verification fails: fix in the worktree. Do NOT proceed to merge.

---

## Phase 5: Safe Merge

### Pre-merge checks

```bash
# 1. Pause all detected agents
for AGENT in $DETECTED_AGENTS; do
  curl -sf -X POST "$AGENT/loop/pause" 2>/dev/null
done

# 2. Check agent has no active background tasks (if applicable)
# curl -sf "$AGENT_URL/status" → check active delegations
```

### Merge

```bash
cd /path/to/main/worktree
git merge --no-ff "$BRANCH" -m "[forge] <type>: <plan summary>"
# <type> inferred from plan content: feat (new feature), fix (bug fix), refactor, docs, chore
```

### Post-merge verification

```bash
# Run same verification as Phase 4 — catches merge-induced issues
$BUILD_CMD && $TYPECHECK_CMD && $TEST_CMD
```

### Clean up

```bash
git worktree remove "$WORKTREE_DIR"
git branch -d "$BRANCH"

# Resume all detected agents
for AGENT in $DETECTED_AGENTS; do
  curl -sf -X POST "$AGENT/loop/resume" 2>/dev/null
done
```

### Rollback

**If merge has conflicts:** resolve in main, re-verify, do NOT resume agents until verified.

**If verification fails after merge:**
```bash
git merge --abort          # If not yet committed
# OR
git reset --merge HEAD~1   # If already committed

# Resume agents — main is back to pre-merge state
for AGENT in $DETECTED_AGENTS; do
  curl -sf -X POST "$AGENT/loop/resume" 2>/dev/null
done

# Debug in the worktree (don't delete it yet)
```

**If no agents detected:** skip all pause/resume. Merge protocol still applies.

### Stale Worktree Cleanup

Failed forge runs may leave behind worktrees. At the start of every `/forge` invocation (Phase 0), check for stale forge worktrees:

```bash
# List forge-created worktrees (pattern: *-dev)
git worktree list | grep -- '-dev'
```

If stale worktrees exist, prompt the user:
```
Found stale worktree: ../project-dev (feature/old-plan)
  - Clean up and remove? (y/n)
  - Or keep for debugging?
```

Do not silently delete — the user may be debugging a previous failure.

---

## Phase 6: Push

```bash
git push origin main
```

---

## Conventions

- **`[forge]`** prefix on merge commits — identifies planned merges (agents/CI can filter)
- **`feature/<plan-filename>`** branch naming — traceable to source plan
- **`../<project>-dev`** worktree location — sibling directory, predictable
- **`$AGENT_URL`** env var — override default agent endpoint

## Red Flags

- **Never skip isolation for multi-task plans** — worktree is cheap, debugging race conditions is not
- **Never merge without passing verification** — evidence before claims
- **Never skip the classification table** — user must see and confirm
- **Never resume agents before merge is verified** — agents trigger on partial state
- **Never force-push feature branches** — worktree refs can break
- **Never hardcode verification commands** — detect from project config

## Quick Reference

```
/forge plan.md
  |
  +--> [SENSE] Detect language, build/test commands, agents, conventions
  |
  +--> [ANALYZE] Read plan → dependency DAG → classify → present table
  |
  +--> 1-2 trivial new-file-only + no agents? → Direct on main
  |
  +--> Everything else:
         |
         +--> Create worktree + feature branch
         +--> Execute by dependency level:
         |      Independent + certain → Parallel
         |      Uncertain / modifies existing → Subagent
         |      Trivial → Direct
         |      Adapt as you go
         |
         +--> Verify: $BUILD_CMD + $TYPECHECK_CMD + $TEST_CMD
         +--> Merge: pause agents → [forge] commit → verify on main → clean up → resume
         +--> Push
```

## Examples

**Simple (no worktree needed):**
```
> /forge docs/plans/add-helper.md

[SENSE] TypeScript project. Build: pnpm build. Test: pnpm test. No agents detected.

2 tasks found. All trivial new files.
| # | Task | Mode | Reason | Depends On |
|---|------|------|--------|------------|
| 1 | Add util function | Direct | New file, 15 lines | — |
| 2 | Add tests | Direct | Test file only | #1 |

No agents detected. Trivial new files only. Working directly on main.
[executes]
Typecheck: EXIT 0. Tests: 42/42 pass.
Pushed.
```

**Complex (full forge workflow):**
```
> /forge docs/plans/context-optimization.md

[SENSE] TypeScript project. Build: pnpm build. Test: pnpm test.
        Typecheck: pnpm typecheck. Agent detected at localhost:3001 (Kuro).

6 tasks found.

| # | Task | Mode | Reason | Depends On |
|---|------|------|--------|------------|
| 1 | FTS5 smart loading | Subagent | Modifies existing function | — |
| 2 | Trail dedup | Parallel | New export, complete spec | — |
| 3 | Auto-demotion | Subagent | New module + 3-file integration | #1 |
| 4 | Haiku pruning | Parallel | New file, complete spec | — |
| 5 | Cold storage | Parallel | Clear spec, independent | — |
| 6 | Health telemetry | Direct | 5 lines in 2 files | #1, #3 |

Execution order:
  Level 0: #1 (Subagent), #2 (Parallel), #4 (Parallel), #5 (Parallel)
  Level 1: #3 (Subagent, needs #1)
  Level 2: #6 (Direct, needs #1 + #3)

Creating worktree: ../project-dev (feature/context-optimization)

Proceed? (y/n)
```
