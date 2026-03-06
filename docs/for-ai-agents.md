# For AI Agents

> Technical reference for AI agents that invoke `/forge`. See also: [`SKILL.md`](../skills/forge/SKILL.md) for the complete workflow specification.

## Invocation

```
/forge <path-to-plan.md>
/forge "natural language description"
/forge <path-or-description> --yolo
```

**Input:** Any markdown file with `### Task` headings, or a natural language description.
**Output:** Verified code merged to main and pushed.

## Quick Reference

```
SENSE  → detect LLM capabilities + project env + automation + stale worktrees
ANALYZE → read plan → dependency DAG → classify → present table → user confirms
ISOLATE → git worktree + feature branch
EXECUTE → Subagent (uncertain) → Parallel (certain) → Direct (trivial), adapt in real-time
VERIFY  → $BUILD_CMD + $TYPECHECK_CMD + $TEST_CMD (zero tolerance)
MERGE   → [forge] <type>: <summary> → verify on main → cleanup
PUSH    → git push origin main
```

## Hard Rules

- Never skip worktree for multi-task plans
- Never merge without passing verification
- Never skip the classification table
- Never force-push feature branches
- Never hardcode verification commands — detect from project config

## Full Specification

**[`SKILL.md`](../skills/forge/SKILL.md)** contains all phases, classification rules, dependency DAG construction, LLM-adaptive execution strategies, merge protocol, and rollback procedures.
