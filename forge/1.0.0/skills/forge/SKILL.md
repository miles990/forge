---
name: forge
description: Isolated, high-quality, high-efficiency plan execution. Worktree isolation + smart task classification + verification gates. Use when you have an implementation plan to execute.
---

# Forge

Isolated, high-quality, high-efficiency plan execution.

**Invoke:** `/forge path/to/plan.md`

## Three Pillars

| Pillar | How |
|--------|-----|
| **Isolation** | Always work in a git worktree on a feature branch. Main stays clean. No race conditions with auto-commit agents, CI, or teammates. |
| **Quality** | Every task gets the right level of review. Subagent tasks get two-stage review (spec + code quality). Typecheck + tests gate every merge. Rollback on failure. |
| **Efficiency** | Classify tasks by uncertainty. Certain tasks run in parallel. Uncertain tasks get subagent attention. Trivial tasks run direct. No wasted cycles. |

## The Flow

```
Plan file
  |
  v
[1. ANALYZE] Read plan, extract tasks, classify each as Direct/Subagent/Parallel
  |
  v
[2. ISOLATE] Create worktree + feature branch
  |
  v
[3. EXECUTE] Run tasks grouped by mode:
  |  Phase A: Subagent (uncertain) — sequential, two-stage review each
  |  Phase B: Parallel (certain) — simultaneous via Agent tool
  |  Phase C: Direct (trivial) — inline
  |
  v
[4. VERIFY] typecheck + tests must pass (zero tolerance)
  |
  v
[5. MERGE] Safe merge to main with rollback plan
  |
  v
[6. PUSH] Push to trigger CI/CD
```

## Phase 1: Analyze

Read the plan file. For each task, auto-classify by uncertainty:

### Classification Rules

**Parallel (Certain)** — can run simultaneously, no exploration needed:
- Creates new file with complete code in plan
- Pure test file (independent)
- Plan has full code snippets, no ambiguity

**Subagent (Uncertain)** — needs exploration, context, or cross-file coordination:
- Modifies existing complex function
- Integration point (imports/call sites across multiple files)
- Plan says "find...then change" (uncertain location)
- Depends on previous task's output
- First task of a new pattern (once proven, similar tasks upgrade to Parallel)

**Direct (Trivial)** — not worth spawning a subagent:
- < 10 lines change in a single file
- Config/constant change
- Adding an export or import

**Present classification table to user before executing:**

```
| # | Task | Mode | Reason |
|---|------|------|--------|
| 1 | New search helper | Parallel | New file, complete spec |
| 2 | Modify buildContext | Subagent | Complex existing function |
| 3 | Add constant | Direct | Single line change |

Execution order: Phase A (Subagent: #2) -> Phase B (Parallel: #1) -> Phase C (Direct: #3)
```

User confirms or overrides before proceeding.

## Phase 2: Isolate

**Always create a worktree for 3+ task plans or any plan modifying existing code.**

```bash
FEATURE_NAME=$(basename "$PLAN_FILE" .md)
BRANCH="feature/$FEATURE_NAME"
WORKTREE_DIR="../$(basename $PWD)-dev"
git worktree add "$WORKTREE_DIR" -b "$BRANCH"
# All work happens in the worktree from here
```

Skip worktree only for: 1-2 trivial Direct tasks that create new files only.

**Agent detection (optional enhancement):**
If `$AGENT_URL` is set (or defaults to `http://localhost:3001`), check if an auto-commit agent is running. If yes, worktree is mandatory regardless of task count.

## Phase 3: Execute

### Phase A: Subagent Tasks (Sequential)

Run uncertain tasks one at a time with full review cycle:

1. **Dispatch implementer subagent** — provide full task text + context from plan
2. **Subagent implements** — explores, asks questions, writes code + tests, self-reviews
3. **Spec compliance review** — does code match what the plan asked for?
4. **Code quality review** — clean code, no bugs, proper error handling?
5. **Fix loop** — if either review finds issues, implementer fixes, reviewer re-reviews
6. **Mark complete** — move to next task

### Phase B: Parallel Tasks (Simultaneous)

Run certain tasks in parallel using Agent tool with `isolation: "worktree"`:
- Each agent gets: complete task spec + file paths + test requirements
- Agents work independently, no shared state
- Collect all results, verify each passes tests
- Merge all into dev worktree

### Phase C: Direct Tasks (Inline)

Execute trivially yourself. No subagent overhead.

### Adaptive Re-classification

Modes can change during execution based on evidence:

| Observation | Action |
|-------------|--------|
| Subagent completes easily, no questions asked | Upgrade similar remaining tasks to Parallel |
| Subagent asks many questions or hits complications | Keep remaining similar tasks as Subagent |
| Parallel agent fails or produces bad code | Downgrade remaining similar tasks to Subagent |
| Direct change causes unexpected test failure | Escalate to Subagent for investigation |

## Phase 4: Verify

**In the worktree, run full verification. Zero tolerance — must pass before merge.**

```bash
# Detect and run project's verification commands
# TypeScript/JavaScript:
pnpm typecheck 2>/dev/null || npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null
pnpm test 2>/dev/null || npm test 2>/dev/null || npx vitest run 2>/dev/null

# Python:
# python -m pytest
# mypy .

# Go:
# go build ./...
# go test ./...

# Rust:
# cargo check
# cargo test
```

Adapt to the project's actual build/test commands. If unsure, check `package.json`, `Makefile`, `Cargo.toml`, etc.

**If verification fails:** Fix in the worktree. Do NOT proceed to merge.

## Phase 5: Merge

### Safe Merge Protocol

```bash
# 1. (If agent detected) Pause agent to prevent trigger storm
AGENT_URL="${AGENT_URL:-http://localhost:3001}"
curl -sf -X POST "$AGENT_URL/loop/pause" 2>/dev/null  # Silent fail if no agent

# 2. Merge feature branch into main
cd /path/to/main/worktree
git merge --no-ff "$BRANCH" -m "[forge] feat: <plan summary>"

# 3. Verify on main (catches merge-induced issues)
# Run same verification commands as Phase 4

# 4. Clean up worktree + branch
git worktree remove "$WORKTREE_DIR"
git branch -d "$BRANCH"

# 5. (If agent detected) Resume agent
curl -sf -X POST "$AGENT_URL/loop/resume" 2>/dev/null
```

### Rollback Plan

**If merge has conflicts:**
- Resolve conflicts in main worktree
- Re-run verification after resolution
- Do NOT resume agent until verified

**If verification fails after merge:**
```bash
git merge --abort          # If not yet committed
# OR
git reset --merge HEAD~1   # If already committed

# Resume agent — main is back to pre-merge state
curl -sf -X POST "$AGENT_URL/loop/resume" 2>/dev/null

# Debug in the worktree (don't delete it)
```

**If no agent:** Skip all pause/resume steps. Merge protocol still applies.

## Phase 6: Push

```bash
git push origin main
```

## Conventions

- **`[forge]`** prefix on merge commits — identifies planned merges (agents can filter these)
- **`feature/<plan-filename>`** branch naming — traceable to source plan
- **`../<project>-dev`** worktree location — sibling directory, predictable
- **`$AGENT_URL`** env var — configurable agent endpoint (optional)

## Red Flags

- **Never skip isolation for multi-task plans** — worktree is cheap, debugging race conditions is not
- **Never merge without passing verification** — evidence before claims
- **Never skip the classification table** — user must see and confirm the execution plan
- **Never resume agent before merge is verified** — agent triggers on partial state
- **Never force-push feature branches** — worktree refs can break

## Quick Reference

```
/forge plan.md
  |
  +--> 1-2 trivial new-file-only tasks? -> Direct on main, no worktree
  |
  +--> Everything else:
         |
         +--> Create worktree
         +--> Classify tasks:
         |      New file + complete spec? ---------> Parallel
         |      Modifies existing code? -----------> Subagent
         |      < 10 lines, single file? ----------> Direct
         |      Depends on previous task? ---------> Subagent
         |
         +--> Execute: Subagent first, then Parallel, then Direct
         +--> Verify: typecheck + tests
         +--> Merge: [forge] commit, verify again, clean up
         +--> Push
```

## Examples

**Simple (no worktree needed):**
```
> /forge docs/plans/add-helper.md

2 tasks found. All trivial new files.
| # | Task | Mode | Reason |
|---|------|------|--------|
| 1 | Add util function | Direct | New file, 15 lines |
| 2 | Add tests | Direct | Test file only |

Working directly on main (trivial new files only).
[executes]
Typecheck: EXIT 0. Tests: 42/42 pass.
```

**Complex (full forge workflow):**
```
> /forge docs/plans/context-optimization.md

6 tasks found.

| # | Task | Mode | Reason |
|---|------|------|--------|
| 1 | FTS5 smart loading | Subagent | Modifies existing function |
| 2 | Trail dedup | Parallel | New export, complete spec |
| 3 | Auto-demotion | Subagent | New module + 3-file integration |
| 4 | Haiku pruning | Parallel | New file, complete spec |
| 5 | Cold storage | Parallel | Clear spec, independent |
| 6 | Health telemetry | Direct | 5 lines in 2 files |

Creating worktree: ../project-dev (feature/context-optimization)

Phase A: Subagent (1, 3) — sequential with two-stage review
Phase B: Parallel (2, 4, 5) — simultaneous
Phase C: Direct (6) — inline

Proceed? (y/n)
```
