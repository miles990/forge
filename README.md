# Forge

One command. AI reads your plan, classifies tasks, isolates in a worktree, executes with optimal strategy, verifies, and merges. You watch.

> **Why "Forge"?** Named by [Kuro](https://kuro.page) (an autonomous AI agent). The metaphor: raw material (plan) goes into the forge, finished product (working code) comes out. The process inside is isolated, hot, and transformative — you don't reach in while it's working.

```bash
/forge docs/plans/my-feature.md

# Full auto — no confirmation, just go
/forge docs/plans/my-feature.md --yolo
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

- Any AI coding assistant that can read files and execute shell commands
- Git repository (forge uses worktrees for isolation)

## Install

### Claude Code (recommended)

```bash
# From the marketplace
claude plugin:add forge --marketplace github:miles990/forge
```

Or manually:

```bash
git clone https://github.com/miles990/forge.git
cp -r forge/forge ~/.claude/plugins/
```

After installation, `/forge` is available in any Claude Code session.

### Cursor

Copy the skill into Cursor's rules directory:

```bash
git clone https://github.com/miles990/forge.git
cp forge/forge/1.0.0/skills/forge/SKILL.md .cursor/rules/forge.md
```

Then tell Cursor: "Follow the forge workflow in .cursor/rules/forge.md to execute my-plan.md"

### Windsurf / Continue.dev

```bash
git clone https://github.com/miles990/forge.git
# Add to your rules/context directory
cp forge/forge/1.0.0/skills/forge/SKILL.md .windsurfrules/forge.md
# Or for Continue.dev:
cp forge/forge/1.0.0/skills/forge/SKILL.md .continue/rules/forge.md
```

### OpenClaw

Forge can be loaded as an OpenClaw skill:

```bash
git clone https://github.com/miles990/forge.git

# Copy into OpenClaw's custom skills directory
cp forge/forge/1.0.0/skills/forge/SKILL.md ~/.openclaw/custom_skills/forge.md
```

Or reference directly in your OpenClaw workspace:

```bash
cp forge/forge/1.0.0/skills/forge/SKILL.md workspace/skills/forge.md
```

Then in your OpenClaw conversation: "Use the forge skill to execute my-plan.md"

> **Note:** OpenClaw agents have file read/write and shell execution capabilities. Forge will auto-detect OpenClaw's tool execution environment and adapt accordingly. Subagent spawning depends on your OpenClaw configuration.

### Aider

```bash
git clone https://github.com/miles990/forge.git
# Use as a prompt file
aider --read forge/forge/1.0.0/skills/forge/SKILL.md
```

Then: "Follow the forge workflow to execute my-plan.md"

### Custom AI Agents

If you're building your own agent (like [mini-agent](https://github.com/miles990/mini-agent)), include SKILL.md in your agent's skill loading pipeline:

```bash
git clone https://github.com/miles990/forge.git
cp forge/forge/1.0.0/skills/forge/SKILL.md your-agent/skills/forge.md
```

Your agent can load it as a skill definition and follow the workflow when a plan execution is requested.

### Any LLM with shell access

The core of Forge is a single markdown file: `forge/1.0.0/skills/forge/SKILL.md`. It contains the complete workflow specification. Any LLM that can:

1. **Read files** — to read the plan and existing code
2. **Execute shell commands** — to run git, build, test commands

...can follow Forge. Just include SKILL.md in your LLM's context/system prompt and point it at your plan file.

```bash
git clone https://github.com/miles990/forge.git

# Option A: Copy into your project
cp forge/forge/1.0.0/skills/forge/SKILL.md docs/forge-workflow.md

# Option B: Reference directly in your prompt
cat forge/forge/1.0.0/skills/forge/SKILL.md | your-llm-cli --system-prompt -
```

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
SENSE  → detect LLM capabilities + project env + agents + stale worktrees
ANALYZE → read plan → dependency DAG → classify → present table → user confirms
ISOLATE → git worktree + feature branch
EXECUTE → Subagent (uncertain) → Parallel (certain) → Direct (trivial), adapt in real-time
VERIFY  → $BUILD_CMD + $TYPECHECK_CMD + $TEST_CMD (zero tolerance)
MERGE   → pause agents → [forge] <type>: <summary> → verify on main → cleanup → resume
PUSH    → git push origin main
```

**For the complete workflow specification, see [`SKILL.md`](forge/1.0.0/skills/forge/SKILL.md).** It contains all phases, classification rules, dependency DAG construction, LLM-adaptive execution strategies, agent detection, merge protocol, and rollback procedures.

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
