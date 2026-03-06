# Forge

One command. AI reads your plan, classifies tasks, isolates in a worktree, executes with optimal strategy, verifies, and merges. You watch.

> **Why "Forge"?** Named by [Kuro](https://kuro.page) (an autonomous AI agent). The metaphor: raw material (plan) goes into the forge, finished product (working code) comes out. The process inside is isolated, hot, and transformative — you don't reach in while it's working.

```bash
/forge docs/plans/my-feature.md
```

## What Happens

```
/forge plan.md
  -> AI reads plan, classifies each task
  -> Creates worktree + feature branch (isolated from main)
  -> Executes tasks:
       Uncertain tasks -> Subagent (sequential, two-stage review)
       Certain tasks   -> Parallel (simultaneous)
       Trivial tasks   -> Direct (inline)
  -> Typecheck + tests (must pass)
  -> Merges to main, verifies again
  -> Pushes
```

You confirm the classification table. Everything else is automated.

## Three Pillars

| | What | Why |
|-|------|-----|
| **Isolation** | Git worktree + feature branch | No race conditions. Main stays clean. Safe from auto-commit agents, CI watchers, teammates. |
| **Quality** | Two-stage review + verification gates | Every subagent task gets spec compliance + code quality review. Typecheck + tests gate every merge. |
| **Efficiency** | Smart task classification | Certain tasks run in parallel. Uncertain tasks get focused attention. Trivial tasks run inline. No wasted cycles. |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- Git repository (forge uses worktrees for isolation)

## Install

```bash
# From the Claude Code marketplace
claude plugin:add forge --marketplace github:miles990/forge
```

Or install manually:

```bash
# Clone the repo
git clone https://github.com/miles990/forge.git

# Copy the plugin into your Claude Code plugins directory
cp -r forge/forge ~/.claude/plugins/
```

After installation, the `/forge` command is available in any Claude Code session.

## Usage

### 1. Write a plan

Create a markdown file describing what you want to build. Each task should be a clear, actionable unit:

```markdown
# My Feature Implementation Plan

### Task 1: Add user validation helper
Create `src/validators/user.ts` with email and name validation functions.

### Task 2: Update registration endpoint
Modify `src/routes/auth.ts` to use the new validation helper.

### Task 3: Add tests
Create `tests/validators/user.test.ts` with full coverage.
```

### 2. Run forge

```bash
/forge docs/plans/my-feature.md
```

### 3. Review the classification

Forge analyzes each task and presents a classification table:

```
| # | Task                    | Mode      | Reason                      |
|---|-------------------------|-----------|-----------------------------|
| 1 | Add validation helper   | Parallel  | New file, complete spec     |
| 2 | Update registration     | Subagent  | Modifies existing function  |
| 3 | Add tests               | Parallel  | Independent test file       |

Execution order: Phase A (Subagent: #2) -> Phase B (Parallel: #1, #3)

Proceed? (y/n)
```

Confirm or override, then forge handles everything else:
- Creates worktree + feature branch
- Executes tasks with optimal strategy
- Runs typecheck + tests (must pass)
- Merges to main, verifies again
- Pushes

### Task Classification

| Mode | When | How |
|------|------|-----|
| **Direct** | < 10 lines, single file, config changes | Inline, no subagent overhead |
| **Subagent** | Modifies existing code, cross-file coordination, uncertain location | Sequential, two-stage review (spec + quality) |
| **Parallel** | New file with complete spec, independent test file | Simultaneous via Agent tool |

Classification adapts during execution — if a subagent task completes easily, similar remaining tasks upgrade to parallel.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_URL` | `http://localhost:3001` | Auto-commit agent endpoint (optional). If set, forge pauses the agent before merge and resumes after. |

### Conventions

- **`[forge]`** prefix on merge commits — identifies planned merges
- **`feature/<plan-filename>`** branch naming — traceable to source plan
- **`../<project>-dev`** worktree location — sibling directory, predictable

## For AI Agents

> This section is for AI agents that invoke `/forge`. Humans can skip this.

### LLM Compatibility

Forge works with any LLM that can read files and execute shell commands. Default optimized for **Claude Code (Anthropic)**.

| LLM | Subagent | Parallel | Worktree | Notes |
|-----|----------|----------|----------|-------|
| **Claude Code** (default) | `Agent` tool | Up to 4 simultaneous | Full support | Optimized path — two-stage review via separate agents |
| Cursor | Background agents | Limited | Full support | Use Cursor's agent dispatch |
| Aider | No | No | Full support | All tasks run sequential, verification still applies |
| Copilot CLI | No | No | Full support | Sequential execution |
| Any LLM + shell | Depends | Depends | `git worktree` | Auto-detects capabilities at runtime |

**Key principle:** When subagent spawn is unavailable, all tasks execute sequentially. The isolation + verification + merge protocol never degrades — quality gates are LLM-independent.

### Invocation

```
/forge <path-to-plan.md>
```

**Input:** Any markdown file with task-like structure (headings, numbered lists, checkboxes — forge auto-detects the format).

**Output:** Working, verified code merged to main and pushed.

### Phase 0: Environment Sensing

Before touching any code, **sense your own capabilities and the project environment**:

```
0. Detect LLM capabilities   → Can spawn subagents? Max parallelism? Worktree support?
1. Detect language/framework  → package.json? Cargo.toml? go.mod? pyproject.toml? Makefile?
2. Detect build command       → "build" script in package.json? `make build`? `cargo build`?
3. Detect test command        → "test" script? `pytest`? `go test`? `cargo test`?
4. Detect typecheck command   → `tsc --noEmit`? `mypy`? `go vet`?
5. Detect auto-commit agent   → curl -sf "$AGENT_URL/status" (default http://localhost:3001)
6. Detect existing worktrees  → git worktree list (avoid conflicts)
7. Read CLAUDE.md / .cursor/* → project-specific conventions, naming, test patterns
```

Store these as your **project profile** — use it for every decision below. Don't guess what works; detect it.

### Phase 1: Intelligent Plan Analysis

Read the plan. For each task, build a **dependency graph** and **uncertainty score**:

```
For each task:
  1. What files does it touch? (create vs modify)
  2. Does it depend on output from another task? (import, call site, shared type)
  3. How much is specified? (complete code → low uncertainty, "find and fix" → high)
  4. Does the target file exist? If yes, how complex? (read it, count lines/functions)
```

Then classify — not by rigid rules, but by reasoning:

| Signal | Points toward |
|--------|---------------|
| Creates new file + plan has complete code | Parallel |
| Creates new file + plan is vague | Subagent |
| Modifies existing file (any complexity) | Subagent |
| Depends on previous task's output | Subagent (sequential) |
| < 10 lines, single file, no ambiguity | Direct |
| Independent test file with clear spec | Parallel |

**Build the dependency DAG.** Tasks with no dependencies on each other can be parallelized. Tasks with dependencies must be sequential regardless of classification.

Present to user:

```
| # | Task | Mode | Reason | Depends On |
|---|------|------|--------|------------|
| 1 | Validation helper | Parallel | New file, complete spec | — |
| 2 | Update registration | Subagent | Modifies existing fn | #1 |
| 3 | Add tests | Parallel | Independent test file | #1 |

Execution order:
  Phase A: #1 (Parallel, no deps)
  Phase B: #2 (Subagent, needs #1), #3 (Parallel, needs #1) — can run simultaneously
```

Wait for user confirmation before proceeding.

### Phase 2: Isolation

```bash
FEATURE_NAME=$(basename "$PLAN_FILE" .md)
BRANCH="feature/$FEATURE_NAME"
WORKTREE_DIR="../$(basename $PWD)-dev"
git worktree add "$WORKTREE_DIR" -b "$BRANCH"
```

**Skip worktree only when:** 1-2 Direct tasks that create new files only AND no auto-commit agent detected.

### Phase 3: Adaptive Execution

Execute tasks respecting the dependency DAG. Strategy adapts to LLM capabilities:

**Claude Code (default — optimized path):**
- **Subagent tasks** — `Agent` tool, sequential, two-stage review (spec compliance → code quality) via separate reviewer agents
- **Parallel tasks** — multiple `Agent` tool calls simultaneously (up to 4), each with `isolation: "worktree"`
- **Direct tasks** — inline, no agent overhead

**Other LLMs (no subagent spawn):**
- All tasks execute sequentially. Classification still determines review depth:
  - Was-Subagent → run verification after each task, self-review carefully
  - Was-Parallel → batch where possible, verify after batch
  - Direct → verify at end

**Adapt in real-time:**

| Observation | Action |
|-------------|--------|
| Subagent completes easily, no questions | Upgrade similar remaining tasks → Parallel |
| Subagent asks many questions / hits complications | Keep similar remaining tasks as Subagent |
| Parallel agent fails or produces bad code | Downgrade similar remaining tasks → Subagent |
| Direct change causes test failure | Escalate to Subagent |
| Task reveals new dependency not in plan | Re-order remaining tasks accordingly |
| Verification command differs from detected | Update project profile, use correct command going forward |

### Phase 4: Verification

Run the commands detected in Phase 0. **Not hardcoded — use what the project actually uses.**

```bash
# Use detected commands, e.g.:
$BUILD_CMD    # pnpm build, cargo build, go build ./..., etc.
$TYPECHECK_CMD # pnpm typecheck, mypy ., go vet ./..., etc.
$TEST_CMD     # pnpm test, pytest, go test ./..., cargo test, etc.
```

**Zero tolerance.** If anything fails, fix in the worktree. Do NOT proceed to merge.

### Phase 5: Safe Merge

```bash
# 1. Pause agent (if detected)
curl -sf -X POST "$AGENT_URL/loop/pause" 2>/dev/null

# 2. Check for active delegations (if agent has background tasks, wait or warn)
ACTIVE=$(curl -sf "$AGENT_URL/status" 2>/dev/null | grep -o '"active":[0-9]*' | head -1)

# 3. Merge
cd /path/to/main && git merge --no-ff "$BRANCH" -m "[forge] feat: <plan summary>"

# 4. Verify on main (catches merge-induced issues)
$BUILD_CMD && $TYPECHECK_CMD && $TEST_CMD

# 5. Clean up
git worktree remove "$WORKTREE_DIR" && git branch -d "$BRANCH"

# 6. Resume agent
curl -sf -X POST "$AGENT_URL/loop/resume" 2>/dev/null
```

**Rollback:**
```bash
git merge --abort            # If not yet committed
git reset --merge HEAD~1     # If already committed — then resume agent
```

### Phase 6: Push

```bash
git push origin main
```

### Hard Rules

- Never skip worktree for multi-task plans
- Never merge without passing verification
- Never skip the classification table
- Never force-push feature branches
- Never resume agent before merge is verified

## Works With Any Project

- **Any language** — TypeScript, Python, Go, Rust, etc.
- **With or without agents** — auto-detects auto-commit agents, adapts accordingly
- **Any plan format** — reads task structure from markdown plans

## License

MIT
