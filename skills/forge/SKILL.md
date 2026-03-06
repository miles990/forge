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
| **Isolation** | Each task gets its own worktree slot. Main only receives verified, passing code. No race conditions with auto-commit agents, CI, or teammates. |
| **Quality** | Every task gets the right level of review. Subagent tasks get two-stage review (spec + code quality). Typecheck + tests gate every per-task merge. Rollback on failure. |
| **Efficiency** | Up to 3 tasks run in parallel across independent slots. Failed tasks retry without losing successful work. Crash-safe progress tracking enables resume. |

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
[0. SENSE]    Detect project environment — language, build/test commands, agents, forge-lite.sh
  |
  v
[1. ANALYZE]  Read plan, build dependency DAG, classify each task, present table
  |
  v
[2. PREPARE]  Detect isolation mode (task-level or single-worktree), check for resume state
  |
  v
[3. EXECUTE]  Per-task: allocate slot → execute → verify → merge to main → release slot
  |            Independent tasks run in parallel across slots (up to 3)
  |            Failed tasks retry once, then skip (dependents blocked)
  |            Adapt classification in real-time based on results
  |
  v
[4. VERIFY]   Final verification on main (catches cross-task integration issues)
  |
  v
[5. COMPLETE] Cleanup + push
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
  Subagent:     yes/no  → determines Parallel/Subagent availability
  Max parallel: N       → determines batch size for Parallel tasks
  Worktree:     yes/no  → determines isolation strategy
  Shell:        yes     → required (no shell = cannot use forge)
  forge-lite:   yes/no  → yes = task-level isolation (per-task slots, retry, resume)
                           no  = single worktree for all tasks
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
| forge-lite.sh | `command -v forge-lite.sh \|\| ls scripts/forge-lite.sh` | Task-level isolation available |
| Stale forge worktrees | `forge-lite.sh status` or `git worktree list \| grep -- '-forge-'` | Prompt user to clean up |

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

## Phase 2: Prepare Isolation

Detect isolation strategy and check for resumable state.

### Detect forge-lite.sh

Check for `forge-lite.sh` in `scripts/` or PATH. This determines the isolation strategy.

```
forge-lite.sh detected?
  yes → Task-level isolation (each task gets its own worktree slot)
  no  → Single worktree (legacy — one worktree for all tasks)
```

**With forge-lite.sh** (preferred): Each task gets an independent worktree slot from a pool of 3. Tasks are verified and merged individually. Failed tasks can retry without losing successful work. File overlap detection prevents conflicts between concurrent tasks.

**Without forge-lite.sh** (fallback): Create a single worktree for all tasks, execute sequentially, merge once at the end.

```bash
# Check availability
FORGE_LITE=$(command -v forge-lite.sh || echo "scripts/forge-lite.sh")
[ -x "$FORGE_LITE" ] && ISOLATION="task-level" || ISOLATION="single-worktree"
```

### Check for resume state

If a previous forge run was interrupted, a progress file may exist:

```bash
PROGRESS_FILE=".forge-progress-$(basename "$PLAN_FILE" .md).json"
```

If found, display completed tasks and ask whether to resume or start fresh:
```
Found progress from previous run:
  Task 1: ✅ completed (merged to main)
  Task 2: ✅ completed (merged to main)
  Task 3: ❌ failed (1 retry exhausted)
  Task 4: ⏸ pending
  Task 5: ⏸ pending

Resume from Task 3? (y/n)
```

**Yolo mode:** Auto-resume — skip completed tasks, retry failed ones.

### Single-worktree fallback

If forge-lite.sh is not available, create one worktree for the entire plan (original behavior):

```bash
FEATURE_NAME=$(basename "$PLAN_FILE" .md)
BRANCH="feature/$FEATURE_NAME"
WORKTREE_DIR="../$(basename $PWD)-forge-$FEATURE_NAME"

if [ -d "$WORKTREE_DIR" ]; then
  echo "Worktree $WORKTREE_DIR already exists. Clean up first."
  exit 1
fi

git worktree add "$WORKTREE_DIR" -b "$BRANCH"
```

Then proceed to Phase 3 in single-worktree mode (all tasks share one worktree, one final merge).

**Skip worktree entirely only when ALL of these are true:**
- 1-2 tasks only
- All Direct classification
- All create new files (no modifications)
- No automation detected (file watchers, AI agents, etc.)

---

## Phase 3: Adaptive Execution

Execute tasks **respecting the dependency DAG**. Strategy depends on isolation mode and LLM capabilities.

### Task-Level Isolation (with forge-lite.sh)

Each task gets its own worktree slot. The lifecycle per task:

```
allocate slot → execute → commit → verify → merge to main → release slot
```

Independent tasks at the same DAG level run in parallel across different slots (up to 3 concurrent).

#### Per-Task Execution Loop

For each dependency level in the DAG:

```
1. Collect all tasks at this level (dependencies satisfied)
2. For each task (parallel if independent, up to 3):
   a. SLOT=$(forge-lite.sh create "task-N-name" --files "declared,files")
      - Exit code 2 = file overlap with busy slot → wait and retry
   b. Execute task in $SLOT (Subagent/Parallel/Direct — see below)
   c. Commit changes in slot:
      cd $SLOT && git add -A && git commit -m "[forge] task N: description"
   d. forge-lite.sh yolo $SLOT "[forge] task N: description"
      - Runs verification (typecheck + tests) in the slot
      - Rebases onto main (handles concurrent merges)
      - Merges to main
      - Cleans up slot for reuse
   e. Update progress file: mark task completed
   f. If yolo fails:
      - Retry once: fix in slot → re-run yolo
      - If retry fails: mark task failed, log error, continue to next task
3. Move to next dependency level (previous level's merges are in main)
```

#### Progress Tracking

Maintain a JSON progress file (gitignored) throughout execution:

```json
{
  "plan": "docs/plans/2026-03-06-feature.md",
  "startedAt": "2026-03-06T10:00:00Z",
  "isolation": "task-level",
  "tasks": {
    "1": { "status": "completed", "mergedAt": "2026-03-06T10:02:30Z" },
    "2": { "status": "completed", "mergedAt": "2026-03-06T10:02:45Z" },
    "3": { "status": "failed", "retries": 1, "error": "test timeout" },
    "4": { "status": "pending" },
    "5": { "status": "pending" }
  }
}
```

This enables crash recovery — on resume, skip completed tasks (already merged to main) and retry from the last failure point.

#### File Overlap Handling

Each task declares which files it touches (from the plan's `**Files:**` field). `forge-lite.sh create --files` checks for overlap with busy slots:

- **No overlap** → slot allocated, proceed
- **Overlap detected (exit 2)** → wait for the conflicting slot to finish, then retry
- **No files declared** → proceed without overlap check (task will still merge safely via rebase)

#### Retry Logic

Each task gets **1 automatic retry** on failure:

| Failure type | Retry action |
|-------------|--------------|
| Verification fails (typecheck/test) | Fix in same slot → re-run `forge-lite.sh yolo` |
| Merge conflict after rebase | `forge-lite.sh cleanup` → re-create slot → re-execute task from scratch |
| Task execution error | Re-execute task in same slot |

After retry exhaustion: mark task failed, continue with independent tasks. Tasks that depend on a failed task are skipped and marked `blocked`.

### Single-Worktree Mode (without forge-lite.sh)

All tasks share one worktree. Execute sequentially. Same task classification, but no per-task merge.

### Task Execution by Classification

These apply in both isolation modes:

#### Subagent Tasks (Claude Code)

1. **Dispatch implementer subagent** via `Agent` tool — provide full task text + relevant file contents + project conventions + worktree path
2. **Subagent implements** — explores, writes code + tests, self-reviews
3. **Dispatch spec compliance reviewer** via `Agent` tool — does code match the plan?
4. **Dispatch code quality reviewer** via `Agent` tool — clean code, follows conventions, no bugs?
5. **Fix loop** — if either review finds issues, dispatch fix agent, then re-review
6. **Mark complete**

#### Parallel Tasks (Claude Code)

- Dispatch multiple `Agent` tool calls simultaneously (respect slot availability — up to 3 in task-level mode)
- Each agent gets: complete task spec + worktree slot path + project conventions
- Agents work independently in separate slots, true filesystem isolation
- Collect results — each slot independently verifies and merges

#### Direct Tasks (All LLMs)

Execute trivially yourself. In task-level mode, Direct tasks can optionally skip slot allocation and work directly on main — only when: single file, < 10 lines, create-only (no modifications).

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

## Phase 4: Final Verification

After all tasks are merged to main, run final verification on main itself:

```bash
$BUILD_CMD       # Compile / bundle
$TYPECHECK_CMD   # Type checking
$TEST_CMD        # Run tests
$LINT_CMD        # Lint (if available)
```

**Why verify again?** Each task was verified individually in its slot, but interactions between merged tasks could introduce issues. This catches cross-task integration problems.

**Zero tolerance — all detected commands must pass.**

If final verification fails:
- Identify which task's merge introduced the failure (`git log --oneline` to see per-task merge commits)
- Revert the problematic merge: `git revert <commit>`
- Re-execute that task with the failure context
- Re-verify

**If no test/build/typecheck commands are detected:** Skip those checks, but warn the user. Log which checks were skipped.

---

## Phase 5: Complete

### Cleanup

```bash
# Remove progress file
rm -f "$PROGRESS_FILE"

# In single-worktree mode: clean up the worktree
git worktree remove "$WORKTREE_DIR" 2>/dev/null
git branch -d "$BRANCH" 2>/dev/null

# Task-level mode: slots are cleaned up per-task by forge-lite.sh yolo
# Check for any leftover slots from failed tasks:
forge-lite.sh status  # shows busy/free/abandoned
forge-lite.sh recover # cleans up any stale state
```

### Stale Worktree Cleanup

At the start of every `/forge` invocation (Phase 0), check for stale forge worktrees:

```bash
forge-lite.sh status   # preferred — shows slot states
# or: git worktree list | grep -- '-forge-'
```

If stale worktrees exist, prompt the user (Normal mode) or auto-clean (Yolo mode).

### Push

```bash
git push origin main
```

---

## Conventions

- **`[forge]`** prefix on merge commits — identifies planned merges (agents/CI can filter)
- **`[forge] task N: description`** per-task merge commits in task-level mode — traceable to individual tasks
- **`feature/task-N-name`** branch naming in task-level mode — one branch per task
- **`../<project>-forge-{1,2,3}`** persistent worktree slots — reused across tasks, cached node_modules
- **`.forge-progress-<plan>.json`** progress file — tracks task status for crash-safe resume (gitignored)
## Red Flags

- **Never skip isolation for multi-task plans** — worktree slots are cheap, debugging race conditions is not
- **Never merge without passing verification** — evidence before claims, per-task and final
- **Never skip the classification table** — always generate and log (yolo mode logs without confirmation)
- **Never force-push feature branches** — worktree refs can break
- **Never hardcode verification commands** — detect from project config
- **Never delete the progress file mid-run** — it enables crash-safe resume
- **Never skip failed-task dependents silently** — mark them `blocked` and report

## Quick Reference

```
/forge plan.md
  |
  +--> [SENSE] Detect language, build/test commands, agents, forge-lite.sh
  |
  +--> [ANALYZE] Read plan → dependency DAG → classify → present table
  |
  +--> 1-2 trivial new-file-only + no automation? → Direct on main
  |
  +--> forge-lite.sh available? → Task-level isolation (preferred):
  |      |
  |      +--> Per-task: allocate slot → execute → verify → merge to main
  |      +--> Independent tasks → parallel across slots (up to 3)
  |      +--> Failed task → retry once, skip if still fails
  |      +--> Progress tracked → crash-safe resume
  |
  +--> No forge-lite.sh? → Single worktree (legacy):
  |      |
  |      +--> Create worktree + feature branch
  |      +--> Execute all tasks in shared worktree
  |      +--> Single verify + merge
  |
  +--> Final verify on main (cross-task integration)
  +--> Cleanup + push
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

**Complex (task-level isolation):**
```
> /forge docs/plans/context-optimization.md

[SENSE] TypeScript project. Build: pnpm build. Test: pnpm test.
        Typecheck: pnpm typecheck. CI detected (.github/workflows/).
        forge-lite.sh: available (3 slots). Isolation: task-level.

6 tasks found.

| # | Task | Mode | Reason | Files | Depends On |
|---|------|------|--------|-------|------------|
| 1 | FTS5 smart loading | Subagent | Modifies existing function | src/search.ts | — |
| 2 | Trail dedup | Parallel | New export, complete spec | src/dedup.ts | — |
| 3 | Auto-demotion | Subagent | New module + 3-file integration | src/demotion.ts | #1 |
| 4 | Haiku pruning | Parallel | New file, complete spec | src/pruning.ts | — |
| 5 | Cold storage | Parallel | Clear spec, independent | src/cold.ts | — |
| 6 | Health telemetry | Direct | 5 lines in 2 files | src/health.ts | #1, #3 |

Execution order:
  Level 0: #1 (slot 1) + #2 (slot 2) + #4 (slot 3)  — 3 parallel
  Level 0b: #5 (slot freed by #2 or #4)
  Level 1: #3 (slot, needs #1 merged to main first)
  Level 2: #6 (Direct on main, needs #1 + #3)

Each task: verify → merge to main → slot released.
Failed task: retry once → skip + block dependents if still fails.

Proceed? (y/n)
```
