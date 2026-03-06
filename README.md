# Forge

**The problem:** You tell your AI "add JWT authentication." It starts editing files on main. Three files in, tests break. You debug, realize it modified the wrong middleware. Meanwhile your auto-commit agent already pushed the broken code. You revert, start over, and babysit every step.

**Forge fixes this.** Forge is a **skill file** — a single markdown file that teaches your AI coding assistant how to execute multi-task plans safely. Describe what you want. AI generates the plan, classifies tasks by complexity, isolates everything in a git worktree, runs uncertain tasks through two-stage review while certain tasks run in parallel, and only merges to main after typecheck + tests pass. You come back to a clean commit on main.

```bash
# Describe what you want — forge handles everything else
/forge "add user authentication with JWT" --yolo

# Or write your own plan and let forge execute it
/forge docs/plans/my-feature.md
```

Works with **Claude Code**, **Cursor**, **Windsurf**, **Copilot CLI**, **Cline**, **Roo Code**, **Aider**, and any LLM that can read files + run shell commands.

> **Why "Forge"?** Named by [Kuro](https://kuro.page) (an autonomous AI agent). Raw material (plan) goes in, finished product (working code) comes out. The process inside is isolated, hot, and transformative — you don't reach in while it's working.

## What Happens

```
/forge "add rate limiting"
  -> AI senses codebase (architecture, patterns, conventions)
  -> Generates implementation plan with tasks
  -> Saves to docs/plans/YYYY-MM-DD-rate-limiting.md
  -> You confirm (or --yolo skips this)
  -> Falls through to execute mode ↓

/forge plan.md
  -> AI reads plan, classifies each task
  -> Per task: allocates worktree slot → executes → verifies → merges to main
  -> Independent tasks run in parallel (up to 3 slots)
  -> Failed tasks retry once (successful work preserved)
  -> Final verification on main
  -> Pushes
```

You confirm the classification table. Everything else is automated.

## Modes

Forge has two dimensions: **input** (plan file vs natural language) and **confirmation** (normal vs yolo).

### Execute mode — run an existing plan

You write the plan (or edit an AI-generated one), then forge executes it.

```bash
/forge docs/plans/my-feature.md
```

Forge reads the plan, classifies tasks, shows you the classification table, and waits for confirmation before executing.

### Plan mode — describe what you want

No plan file? Describe what you want in natural language. Forge senses the codebase, generates a structured plan, saves it to `docs/plans/`, and asks you to confirm before executing.

```bash
/forge "add rate limiting middleware with per-user quotas"
```

The generated plan is a real file you can edit, version control, and re-run. If the AI misunderstands your intent, fix the plan and re-run — no code was written yet.

### Yolo mode — full auto, no confirmation

Append `--yolo` to skip all confirmation steps. Forge decides everything — plan generation, task classification, execution order — and only stops if verification fails.

```bash
# Plan + execute, fully autonomous
/forge "add WebSocket support for real-time updates" --yolo

# Execute existing plan, no confirmation
/forge docs/plans/my-feature.md --yolo
```

Yolo mode keeps all safety nets (worktree isolation, verification gates, rollback on failure). What it removes: the pause where you review and confirm.

**When to use yolo:** Well-scoped features with good test coverage. You trust the AI's judgment and want to walk away.

**When NOT to use yolo with plan mode:** High-stakes changes where a misinterpreted intent would produce "correct code that does the wrong thing." Use normal mode so you can review the generated plan before execution.

## Three Pillars

| | What | Why |
|-|------|-----|
| **Isolation** | Each task gets its own worktree slot | No race conditions. Main only receives verified code. Safe from auto-commit agents, CI, teammates. |
| **Quality** | Two-stage review + per-task verification gates | Every subagent task gets spec compliance + code quality review. Typecheck + tests gate every merge. |
| **Efficiency** | Up to 3 tasks in parallel + auto-retry | Independent tasks run simultaneously across slots. Failed tasks retry without losing successful work. Crash-safe progress tracking. |

## Requirements

- **Git** — forge uses worktrees for isolation
- Any AI coding assistant that can read files and execute shell commands

### Platform Support

| Platform | Subagent | Parallel | Worktree | Notes |
|----------|----------|----------|----------|-------|
| **Claude Code** | `Agent` tool | Up to 4 | Native | Optimized path — two-stage review via separate agents |
| **Cursor** | Subagents, Background Agents | Up to 8 | Native (auto) | Background Agents run in cloud VMs |
| **Windsurf** | Cascade | Up to 5 | Native | Multi-pane parallel Cascade sessions |
| **Copilot CLI** | `/fleet`, specialized agents | Yes (via `/fleet`) | Native | Orchestrator auto-delegates independent subtasks |
| **Cline** | Subagent tool (via CLI) | Yes (resource-limited) | Manual | Multiple CLI processes in separate directories |
| **Roo Code** | Boomerang Tasks | Sequential only | Native | Orchestrator delegates to specialized modes, one at a time |
| **OpenClaw** | `sessions_spawn` | Up to 5 children | Via plugins | Personal agent platform, not a coding IDE |
| **Continue.dev** | Cloud Agents (CI only) | Manual (multiple CLI) | Manual | No native subagent spawn in IDE |
| **Aider** | No | No | Manual | Single-agent design; multi-agent is community/external only |
| **Any LLM + shell** | Depends | Depends | `git worktree` | Forge auto-detects capabilities at runtime |

**Key principle:** When subagent spawn is unavailable, all tasks execute sequentially. Quality gates never degrade — isolation + verification + merge protocol are LLM-independent.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/install.sh | bash
```

Auto-detects your platform (Claude Code, Cursor, Windsurf, Cline, Roo Code, Continue.dev, Aider) and installs to the right place.

<details>
<summary>Manual install</summary>

Forge is a single markdown file ([`SKILL.md`](skills/forge/SKILL.md)). Download it to wherever your AI reads instructions:

```bash
# Claude Code (plugin system)
claude plugin marketplace add miles990/forge
claude plugin install forge

# Cursor
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o .cursor/rules/forge.md

# Windsurf
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o .windsurfrules/forge.md

# OpenClaw
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o ~/.openclaw/custom_skills/forge.md

# Aider
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o forge.md && aider --read forge.md

# Any LLM with shell access
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o forge.md
```
</details>

## Uninstall

```bash
# Claude Code
claude plugin uninstall forge

# Other platforms — delete the file you installed
rm .cursor/rules/forge.md          # Cursor
rm .windsurfrules/forge.md         # Windsurf
rm ~/.openclaw/custom_skills/forge.md  # OpenClaw
rm forge.md                        # Aider / generic
```

## Usage

### 0. Invoke forge

| Platform | How to invoke |
|----------|---------------|
| **Claude Code** | `/forge plan.md` or `/forge "description"` |
| **Other LLMs** | "Follow the forge workflow to execute plan.md" or "Follow the forge workflow to: [description]" |

### 1. Write a plan (or let AI write it)

Create a markdown file, or just describe what you want and let forge generate it for you.

#### Plan Format

Forge parses any markdown with `### Task` headings. Here's the full format:

```markdown
# Feature Name

**Goal:** One sentence describing the outcome.
**Architecture:** 2-3 sentences about the approach. (optional)

### Task 1: Short task name
**Files:** Create `src/new-file.ts`, Modify `src/existing.ts`
Description of what to implement. Be specific — exact function signatures,
logic, edge cases. The more detail, the better the AI executes.

### Task 2: Another task
**Files:** Modify `src/routes/auth.ts`
**Depends on:** Task 1
Description. "Depends on" tells forge to run this after Task 1 completes.

### Task 3: Tests
**Files:** Create `tests/feature.test.ts`
**Depends on:** Task 1, Task 2
- Test case A (input → expected output)
- Test case B (edge case)
- Test case C (error handling)
```

**Required:** `### Task N: Name` headings — forge uses these to identify tasks.

**Optional but recommended:**
- `**Files:**` — `Create` or `Modify` + exact paths. Helps forge classify tasks (new file = likely Parallel, modify existing = likely Subagent).
- `**Depends on:**` — References to other tasks. Forge builds a dependency DAG from these — independent tasks can run simultaneously.
- `**Goal:**` / `**Architecture:**` — Top-level context for the AI.

**Minimal plan** (also works):

```markdown
# Add reverse utility

### Task 1: Add reverse function
Modify `src/utils.js` — add `reverse(str)` that returns the string reversed.

### Task 2: Add tests
Modify `tests/run.js` — test reverse with normal, empty, palindrome, single char inputs.
```

### 2. Review the classification

Forge analyzes each task and presents a classification table:

```
| # | Task                    | Mode      | Reason                      |
|---|-------------------------|-----------|-----------------------------|
| 1 | Add validation helper   | Parallel  | New file, complete spec     |
| 2 | Update registration     | Subagent  | Modifies existing function  |
| 3 | Add tests               | Parallel  | Independent test file       |

Execution order:
  Level 0: #1 (Parallel, no deps)
  Level 1: #2 (Subagent, needs #1) + #3 (Parallel, needs #1)

Proceed? (y/n)
```

Confirm or override, then forge handles everything else:
- Allocates worktree slots per task (up to 3 in parallel)
- Executes each task in isolation with optimal strategy
- Per-task verification + merge to main
- Failed tasks auto-retry once
- Final verification on main
- Pushes

### Task Classification

| Mode | When | How |
|------|------|-----|
| **Direct** | < 10 lines, single file, config changes | Inline, no subagent overhead |
| **Subagent** | Modifies existing code, cross-file coordination, uncertain location | Sequential, two-stage review (spec + quality) |
| **Parallel** | New file with complete spec, independent test file | Simultaneous via Agent tool |

Classification adapts during execution — if a subagent task completes easily, similar remaining tasks upgrade to parallel.

## If Something Goes Wrong

Forge works in a git worktree on a feature branch. **Main is never touched until everything passes.** If something breaks mid-execution, your main branch is exactly where it was.

| Scenario | What happens |
|----------|-------------|
| **Tests fail** | Forge retries the task in its slot. Won't merge until all pass. |
| **Merge conflict** | Rebase handles most cases automatically. If rebase conflicts, falls back to direct merge. |
| **Verification fails after merge** | Auto-rollback: `git revert <commit>`. Successful tasks preserved. |
| **Forge crashes / you ctrl-C** | Progress file tracks completed tasks. Re-run `/forge plan.md` to resume from where it stopped. |
| **One task fails permanently** | Successful tasks are already merged to main. Only the failed task and its dependents are skipped. |
| **Wrong plan / bad output** | Per-task commits make it easy to revert individual tasks. `git log --oneline` shows each `[forge] task N:` commit. |

Each task merges to main independently. A failure in task 3 doesn't lose the work from tasks 1 and 2.

## Configuration

### Conventions

- **`[forge] task N: description`** per-task merge commits — traceable to individual tasks
- **`feature/task-N-name`** branch naming — one branch per task
- **`../<project>-forge-{1,2,3}`** persistent worktree slots — reused across tasks, cached dependencies

## For AI Agents

Technical reference for AI agents invoking `/forge`: **[docs/for-ai-agents.md](docs/for-ai-agents.md)**

Complete workflow specification: **[`SKILL.md`](skills/forge/SKILL.md)**

## Works With Any Project

- **Any language** — TypeScript, Python, Go, Rust, etc.
- **With or without automation** — auto-detects file watchers, CI, AI agents → uses worktree isolation
- **Any plan format** — reads task structure from markdown plans

## FAQ

**What is Forge?**
Forge is a skill file (a structured markdown prompt) that teaches any AI coding assistant how to execute multi-task implementation plans safely. It classifies tasks by complexity, isolates each task in its own worktree slot, executes with the optimal strategy (parallel, sequential, or inline), and only merges to main after verification passes. Failed tasks retry automatically without losing successful work.

**What is a skill file?**
A skill file is a markdown document that defines a reusable workflow for AI assistants — like a runbook that your AI follows. In Claude Code it installs as a plugin skill (`/forge`). In other tools (Cursor, Windsurf, Aider), it loads as a rules file or system prompt. One file, any platform.

**Does Forge only work with Claude Code?**
No. Forge is a single markdown file that any LLM can follow — Claude Code, Cursor, Windsurf, Copilot CLI, Cline, Roo Code, Aider, or any AI with shell access. Claude Code gets the best experience (native `/forge` command + parallel subagents), but the core workflow (isolation, verification, merge) works everywhere.

**Is Forge an AI agent?**
No. Forge is a workflow specification (a skill/prompt) that runs inside your existing AI assistant. It doesn't have its own model, runtime, or API. Think of it as a discipline layer — your AI already knows how to write code, forge teaches it how to execute a multi-task plan safely.

**How is Forge different from Devin / SWE-agent?**
Devin and SWE-agent are full AI agents with their own environments. Forge is lightweight — a single markdown file that augments your existing AI assistant. No setup, no infrastructure, no monthly fee.

## License

MIT
