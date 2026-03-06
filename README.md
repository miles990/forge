# Forge

**The problem:** You have a 6-task implementation plan. Your AI assistant executes them one by one, on main, with no isolation. Halfway through, tests break. You `git stash`, debug, realize task 3 conflicted with task 2. Meanwhile your auto-commit agent pushed broken code. You start over.

**Forge fixes this.** One command — AI reads the plan, classifies tasks by complexity, isolates everything in a git worktree, runs uncertain tasks through two-stage review while certain tasks execute in parallel, gates the merge on typecheck + tests, and only touches main when everything passes.

```bash
# Full auto — AI generates plan + executes + verifies + merges + pushes
/forge "add user authentication with JWT" --yolo

# Or from an existing plan
/forge docs/plans/my-feature.md

# Plan mode — AI writes the plan, you confirm, then it executes
/forge "add rate limiting"
```

Works with **Claude Code**, **OpenClaw**, **Cursor**, **Windsurf**, **Aider**, and any LLM that can read files + run shell commands.

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

- Any AI coding assistant that can read files and execute shell commands
- Git repository (forge uses worktrees for isolation)

## Install

### Quick install (auto-detects platform)

```bash
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/install.sh | bash
```

Automatically detects Claude Code, OpenClaw, Cursor, Windsurf, Continue.dev and installs to the right place.

### Claude Code

```bash
# Add marketplace + install plugin
claude plugin marketplace add miles990/forge
claude plugin install forge

# Or use the quick install script
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/install.sh | bash
```

After installation, `/forge` is available in any Claude Code session.

### OpenClaw

```bash
# Auto-install
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/install.sh | bash

# Or manually
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o ~/.openclaw/custom_skills/forge.md
```

Then tell your agent: "Use the forge skill to execute my-plan.md"

> Forge auto-detects OpenClaw's tool environment and adapts. Subagent spawning depends on your OpenClaw configuration.

### Cursor / Windsurf / Continue.dev

```bash
# Auto-install (detects your editor)
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/install.sh | bash

# Or manually — pick your editor:
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o .cursor/rules/forge.md          # Cursor
  # .windsurfrules/forge.md          # Windsurf
  # .continue/rules/forge.md         # Continue.dev
```

Then: "Follow the forge workflow to execute my-plan.md"

### Aider

```bash
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o forge.md
aider --read forge.md
```

### Custom AI Agents

For agents like [mini-agent](https://github.com/miles990/mini-agent) or your own:

```bash
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o your-agent/skills/forge.md
```

### Any LLM with shell access

Forge is a single markdown file. Any LLM that can read files + run shell commands can use it:

```bash
# Download the skill
curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/skills/forge/SKILL.md \
  -o forge.md

# Include in your LLM's context
cat forge.md | your-llm-cli --system-prompt -
```

## Uninstall

### Claude Code

```bash
claude plugin uninstall forge
```

### Other platforms

Delete the `forge.md` or `SKILL.md` file you installed:

```bash
# Cursor
rm .cursor/rules/forge.md

# Windsurf
rm .windsurfrules/forge.md

# Continue.dev
rm .continue/rules/forge.md

# OpenClaw
rm ~/.openclaw/custom_skills/forge.md

# Aider
rm forge.md
```

## Usage

### 0. Invoke forge

| Platform | How to invoke |
|----------|---------------|
| **Claude Code** | `/forge plan.md` or `/forge "description"` |
| **OpenClaw** | "Use the forge skill to execute plan.md" |
| **Cursor / Windsurf** | "Follow the forge workflow to execute plan.md" |
| **Aider** | "Follow the forge workflow in forge.md to execute plan.md" |
| **Any LLM** | "Follow the forge workflow to: [your description]" |

### 1. Write a plan (or let AI write it)

Create a markdown file, or just describe what you want and let forge generate the plan:

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

Execution order:
  Level 0: #1 (Parallel, no deps)
  Level 1: #2 (Subagent, needs #1) + #3 (Parallel, needs #1)

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

### Conventions

- **`[forge]`** prefix on merge commits — identifies planned merges
- **`feature/<plan-filename>`** branch naming — traceable to source plan
- **`../<project>-forge-<plan-name>`** worktree location — unique per plan, avoids collision

## For AI Agents

> This section is for AI agents that invoke `/forge`. Humans can skip this.

### LLM Compatibility

Forge works with any LLM that can read files and execute shell commands. Default optimized for **Claude Code (Anthropic)**.

| LLM / Platform | Subagent | Parallel | Worktree | Notes |
|----------------|----------|----------|----------|-------|
| **Claude Code** (default) | `Agent` tool | Up to 4 simultaneous | Full support | Optimized path — two-stage review via separate agents |
| OpenClaw | Skill execution | Depends on config | Full support | Load as custom skill, adapts to OpenClaw's tool environment |
| Cursor | Background agents | Limited | Full support | Use Cursor's agent dispatch |
| Windsurf / Continue.dev | Depends | Depends | Full support | Load as rules file |
| Aider | No | No | Full support | All tasks run sequential, verification still applies |
| Copilot CLI | No | No | Full support | Sequential execution |
| Custom agents (mini-agent, etc.) | Depends | Depends | Full support | Include SKILL.md in agent's skill pipeline |
| Any LLM + shell | Depends | Depends | `git worktree` | Auto-detects capabilities at runtime |

**Key principle:** When subagent spawn is unavailable, all tasks execute sequentially. The isolation + verification + merge protocol never degrades — quality gates are LLM-independent.

### Invocation

```
/forge <path-to-plan.md>
```

**Input:** Any markdown file with task-like structure. **Output:** Verified code merged to main and pushed.

### Quick Reference

```
SENSE  → detect LLM capabilities + project env + automation + stale worktrees
ANALYZE → read plan → dependency DAG → classify → present table → user confirms
ISOLATE → git worktree + feature branch
EXECUTE → Subagent (uncertain) → Parallel (certain) → Direct (trivial), adapt in real-time
VERIFY  → $BUILD_CMD + $TYPECHECK_CMD + $TEST_CMD (zero tolerance)
MERGE   → [forge] <type>: <summary> → verify on main → cleanup
PUSH    → git push origin main
```

**For the complete workflow specification, see [`SKILL.md`](skills/forge/SKILL.md).** It contains all phases, classification rules, dependency DAG construction, LLM-adaptive execution strategies, merge protocol, and rollback procedures.

### Hard Rules

- Never skip worktree for multi-task plans
- Never merge without passing verification
- Never skip the classification table
- Never force-push feature branches
- Never hardcode verification commands — detect from project config

## Works With Any Project

- **Any language** — TypeScript, Python, Go, Rust, etc.
- **With or without automation** — auto-detects file watchers, CI, AI agents → uses worktree isolation
- **Any plan format** — reads task structure from markdown plans

## License

MIT
