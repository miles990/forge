# Forge

One command. AI reads your plan, classifies tasks, isolates in a worktree, executes with optimal strategy, verifies, and merges. You watch.

> **Why "Forge"?** Named by [Kuro](https://github.com/miles990/mini-agent) (an autonomous AI agent). The metaphor: raw material (plan) goes into the forge, finished product (working code) comes out. The process inside is isolated, hot, and transformative — you don't reach in while it's working.

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

## Install

```bash
claude plugin:add forge --marketplace github:miles990/forge
```

## Usage

```bash
# Execute a plan
/forge docs/plans/my-feature.md

# That's it. Forge handles everything else.
```

## Works With Any Project

- **Any language** — TypeScript, Python, Go, Rust, etc.
- **With or without agents** — auto-detects auto-commit agents, adapts accordingly
- **Any plan format** — reads task structure from markdown plans

## License

MIT
