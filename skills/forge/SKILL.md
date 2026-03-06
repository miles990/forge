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

What yolo mode removes: the classification table confirmation step. Forge decides everything — classification, execution order, merge — and only stops if verification fails.

## Three Pillars

| Pillar | How |
|--------|-----|
| **Isolation** | Always work in a git worktree on a feature branch. Main stays clean. No race conditions with auto-commit agents, CI, or teammates. |
| **Quality** | Every task gets the right level of review. Subagent tasks get two-stage review (spec + code quality). Typecheck + tests gate every merge. Rollback on failure. |
| **Efficiency** | Classify tasks by uncertainty + dependency graph. Independent certain tasks run in parallel. Uncertain tasks get subagent attention. Trivial tasks run direct. No wasted cycles. |

## The Flow

**Two entry points:**

```
/forge plan.md                → Execute mode (plan file exists)
/forge "add authentication"   → Plan mode (natural language → generates plan → executes)
```

Detection: argument ends with `.md` and file exists → Execute mode. Otherwise → Plan mode.

> **Edge case:** If argument ends with `.md` but file doesn't exist, warn: "file.md not found. Treating as natural language description. Did you mean to create this file first?" Then proceed as Plan mode.

```
Input (plan file OR natural language description)
  |
  v
[P. PLAN]     (Plan mode only) Sense codebase → generate plan → save → confirm with user
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
[5. MERGE]    Safe merge to main — merge, verify, clean up
  |
  v
[6. PUSH]     Push to trigger CI/CD
```

---

## Phase P: Plan Generation (Plan mode only)

Triggered when the argument is natural language instead of a `.md` file path.

### Step 1: Understand the request

Parse the user's description. Identify:
- **What** they want (feature, fix, refactor, migration, etc.)
- **Scope** — is this a single-file change or cross-cutting?
- **Constraints** — any specific requirements mentioned?

### Step 2: Sense the codebase (for plan quality)

Before writing the plan, understand the project. This sensing is about understanding the codebase to write a good plan. Phase 0 re-senses later for execution mechanics (build/test commands, agents, worktrees).

```
1. Read project config        → package.json, CLAUDE.md, README, etc.
2. Understand architecture    → directory structure, key modules, entry points
3. Find relevant code         → grep/glob for related files, read them
4. Check existing tests       → test patterns, frameworks, coverage
5. Check existing patterns    → naming conventions, error handling, similar features
```

### Step 3: Generate the plan

Write a structured plan with tasks. Each task should specify:
- **Files** — exact paths to create or modify
- **What to do** — specific changes, not vague descriptions
- **Dependencies** — which tasks depend on which
- **Tests** — what tests to write or update

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence]
**Architecture:** [2-3 sentences about approach]

### Task 1: [Component Name]
**Files:** Create `src/path/file.ts`, Modify `src/path/existing.ts`
[Detailed description of what to implement]

### Task 2: [Tests]
**Files:** Create `tests/path/file.test.ts`
**Depends on:** Task 1
[Test cases to cover]
```

### Step 4: Save and confirm

```bash
# Save to docs/plans/ with timestamp
PLAN_FILE="docs/plans/$(date +%Y-%m-%d)-<feature-name>.md"
mkdir -p docs/plans

# If file already exists, warn before overwriting
if [ -f "$PLAN_FILE" ]; then
  echo "Plan file $PLAN_FILE already exists. Overwrite? (y/n)"
fi
```

**Normal mode:** Present the generated plan to user. Wait for approval or edits before proceeding.

**Yolo mode:** Save the plan, log it, and proceed directly to Phase 0.

> **Yolo + Plan mode safety note:** AI generates the plan AND executes it without human review. Verification gates (typecheck + tests) catch syntax/logic errors that break tests, but cannot catch "correct code that does the wrong thing." If the plan misinterprets the user's intent, the code will pass verification but not match what was wanted. For high-stakes changes, prefer Normal mode or provide a pre-written plan.

After confirmation, the plan file feeds into the standard forge flow (Phase 0 → 1 → 2 → 3 → 4 → 5 → 6).

---

## Phase 0: Environment Sensing

Before touching any code, sense the project environment. **Do not assume — detect.**

### LLM Capability Detection

Forge is designed for any LLM that can read files and execute shell commands. Detect your own capabilities to choose the best execution strategy.

| Capability | Check | Impact on execution |
|------------|-------|---------------------|
| **Subagent spawn** | Can you dispatch independent AI agents? (e.g., Claude Code `Agent` tool, Cursor Subagents, Windsurf Cascade, Copilot CLI `/fleet`, Cline subagent tool, Roo Code Boomerang Tasks) | Yes → Parallel + Subagent modes available. No → all tasks run sequentially as Direct. |
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

### Automation Awareness

Check for anything that reacts to file changes or git events on main:

| Automation type | Detection | Implication |
|-----------------|-----------|-------------|
| File watcher / auto-commit | `ps aux \| grep -i "fswatch\|watchman\|nodemon\|chokidar"` | Worktree mandatory |
| Git hooks (post-commit, pre-push) | Check `.git/hooks/` and `.husky/` | Be aware of side effects |
| CI on push | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile` | Push triggers CI — verify before push |
| Other AI agents | `ps aux \| grep -i "cursor\|copilot\|aider\|continue"` | Worktree mandatory to avoid conflicts |

**Rule:** If any automation is detected that reacts to file changes on main → worktree is mandatory regardless of task count. Worktree isolation is sufficient — no need to pause/resume external processes.

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
WORKTREE_DIR="../$(basename $PWD)-forge-$FEATURE_NAME"
# Unique per plan — avoids collision when multiple forge runs or users

# If worktree for this plan already exists, abort — don't silently overwrite
if [ -d "$WORKTREE_DIR" ]; then
  echo "Worktree $WORKTREE_DIR already exists. Previous forge run for this plan?"
  echo "Clean up first: git worktree remove $WORKTREE_DIR"
  exit 1
fi

git worktree add "$WORKTREE_DIR" -b "$BRANCH"
# All work happens in the worktree from here
```

**Skip worktree only when ALL of these are true:**
- 1-2 tasks only
- All Direct classification
- All create new files (no modifications)
- No automation detected (file watchers, AI agents, etc.)

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

### Commit all changes

After all tasks are complete, commit everything in the worktree to the feature branch:

```bash
cd "$WORKTREE_DIR"
git add -A
git commit -m "feat: <plan summary>"
```

This is required before Phase 5 (merge). Without this commit, the merge will see "already up to date" and skip your changes.

---

## Phase 4: Verify

**Use the commands detected in Phase 0. Do not hardcode.**

```bash
$BUILD_CMD       # Compile / bundle
$TYPECHECK_CMD   # Type checking
$TEST_CMD        # Run tests
$LINT_CMD        # Lint (if available)
```

**Zero tolerance — all detected commands must pass before merge.**

If verification fails: fix in the worktree. Do NOT proceed to merge.

**If no test/build/typecheck commands are detected:** Skip those checks, but warn the user that verification is incomplete. Forge still proceeds — lack of tests is a project issue, not a forge issue. Log which checks were skipped for traceability.

---

## Phase 5: Safe Merge

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
```

### Rollback

**If merge has conflicts:** resolve in main, re-verify.

**If verification fails after merge:**
```bash
git merge --abort          # If not yet committed
# OR
git reset --merge HEAD~1   # If already committed

# Debug in the worktree (don't delete it yet)
```

### Stale Worktree Cleanup

Failed forge runs may leave behind worktrees. At the start of every `/forge` invocation (Phase 0), check for stale forge worktrees:

```bash
# List forge-created worktrees (pattern: *-dev)
git worktree list | grep -- '-forge-'
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
- **`../<project>-forge-<plan-name>`** worktree location — unique per plan, sibling directory, avoids collision
## Red Flags

- **Never skip isolation for multi-task plans** — worktree is cheap, debugging race conditions is not
- **Never merge without passing verification** — evidence before claims
- **Never skip the classification table** — always generate and log (yolo mode logs without confirmation)
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
  +--> 1-2 trivial new-file-only + no automation? → Direct on main
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
         +--> Merge: [forge] commit → verify on main → clean up
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
        Typecheck: pnpm typecheck. CI detected (.github/workflows/).

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

Creating worktree: ../project-forge-context-optimization (feature/context-optimization)

Proceed? (y/n)
```
