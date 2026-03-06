#!/usr/bin/env bash
# forge-lite.sh — Lightweight worktree isolation for AI agent delegations
# Mechanical steps only. Creative work is done by the LLM between commands.
#
# Usage:
#   forge-lite.sh create <task-name>              → Create worktree + branch
#   forge-lite.sh verify <worktree-path>          → Run typecheck + tests
#   forge-lite.sh merge <worktree-path> [message]  → Merge to main + cleanup
#   forge-lite.sh yolo <worktree-path> [message]   → Verify + merge in one shot
#   forge-lite.sh cleanup <worktree-path>          → Remove worktree without merging
#   forge-lite.sh recover                          → Recover from a previous crash
#
# Exit codes: 0 = success, 1 = failure (details on stderr)

set -euo pipefail

MAIN_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: not inside a git repository" >&2
  exit 1
}

LOCK_FILE="$MAIN_DIR/.git/forge-lite.lock"
STATE_FILE="$MAIN_DIR/.git/forge-lite-state"
STALE_HOURS=24

# ============================================================
# Safety infrastructure
# ============================================================

acquire_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null) || lock_pid=""
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      echo "Error: another forge-lite is running (pid $lock_pid)" >&2
      echo "If stale: rm $LOCK_FILE" >&2
      exit 1
    fi
    echo "[lock] Removing stale lock (pid $lock_pid no longer running)" >&2
    rm -f "$LOCK_FILE"
  fi
  echo $$ > "$LOCK_FILE"
}

release_lock() {
  rm -f "$LOCK_FILE"
}

set_state() {
  echo "$1:$2:$(date +%s)" > "$STATE_FILE"
}

clear_state() {
  rm -f "$STATE_FILE"
}

on_exit() {
  local code=$?
  release_lock
  if [ "$code" -eq 0 ]; then
    clear_state
  elif [ -f "$STATE_FILE" ]; then
    echo "[crash] State saved: $(cat "$STATE_FILE")" >&2
    echo "[crash] Run 'forge-lite.sh recover' to clean up" >&2
  fi
}

trap on_exit EXIT
trap 'exit 130' INT TERM

# ============================================================
# Stale worktree auto-prune
# ============================================================

auto_prune() {
  git -C "$MAIN_DIR" worktree prune 2>/dev/null || true

  local project_name
  project_name=$(basename "$MAIN_DIR")
  local parent_dir
  parent_dir=$(dirname "$MAIN_DIR")
  local now
  now=$(date +%s)

  for dir in "$parent_dir/${project_name}-forge-"*; do
    [ -d "$dir" ] || continue
    local mtime
    if stat -f %m "$dir" >/dev/null 2>&1; then
      mtime=$(stat -f %m "$dir")    # macOS
    else
      mtime=$(stat -c %Y "$dir" 2>/dev/null) || continue  # Linux
    fi
    local age_hours=$(( (now - mtime) / 3600 ))
    if [ "$age_hours" -ge "$STALE_HOURS" ]; then
      echo "[prune] Removing stale worktree (${age_hours}h old): $dir" >&2
      local branch
      branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
      git -C "$MAIN_DIR" worktree remove "$dir" 2>/dev/null || rm -rf "$dir"
      [ -n "$branch" ] && [ "$branch" != "main" ] && \
        git -C "$MAIN_DIR" branch -D "$branch" 2>/dev/null || true
    fi
  done
}

# ============================================================
# Pre-flight validation
# ============================================================

preflight_check() {
  local cmd="${1:?}"

  # Warn about previous crash state
  if [ -f "$STATE_FILE" ]; then
    echo "[warn] Previous run may have crashed: $(cat "$STATE_FILE")" >&2
    echo "[warn] Run 'forge-lite.sh recover' to clean up, or continuing..." >&2
  fi

  # For merge/yolo: ensure main is clean
  if [ "$cmd" = "merge" ] || [ "$cmd" = "yolo" ]; then
    if ! git -C "$MAIN_DIR" diff --quiet 2>/dev/null || \
       ! git -C "$MAIN_DIR" diff --cached --quiet 2>/dev/null; then
      echo "Error: main has uncommitted changes — commit or stash first" >&2
      exit 1
    fi
    if [ -f "$MAIN_DIR/.git/MERGE_HEAD" ]; then
      echo "Error: merge already in progress on main — resolve first" >&2
      exit 1
    fi
  fi
}

# ============================================================
# Install dependencies if needed
# ============================================================

install_deps() {
  local dir="${1:?}"

  if [ -f "$dir/package.json" ]; then
    # Skip if node_modules is a real directory (not a symlink)
    if [ -d "$dir/node_modules" ] && [ ! -L "$dir/node_modules" ]; then
      return 0
    fi
    # Remove broken or stale symlinks (worktree artifact)
    [ -L "$dir/node_modules" ] && rm "$dir/node_modules"

    local install_cmd="npm ci"
    [ -f "$dir/pnpm-lock.yaml" ] && install_cmd="pnpm install --frozen-lockfile"
    [ -f "$dir/bun.lockb" ] && install_cmd="bun install --frozen-lockfile"
    [ -f "$dir/yarn.lock" ] && install_cmd="yarn install --frozen-lockfile"

    echo "[deps] Running: $install_cmd" >&2
    (cd "$dir" && eval "$install_cmd") || {
      echo "[deps] FAILED: $install_cmd" >&2
      return 1
    }
  elif [ -f "$dir/go.mod" ]; then
    echo "[deps] Running: go mod download" >&2
    (cd "$dir" && go mod download) || true
  fi
}

# ============================================================
# Detect project verification commands
# ============================================================

detect_commands() {
  local dir="${1:-$MAIN_DIR}"
  BUILD_CMD="" TYPECHECK_CMD="" TEST_CMD="" LINT_CMD=""

  if [ -f "$dir/package.json" ]; then
    local pm="npm run"
    [ -f "$dir/pnpm-lock.yaml" ] && pm="pnpm"
    [ -f "$dir/bun.lockb" ] && pm="bun run"
    [ -f "$dir/yarn.lock" ] && pm="yarn"

    grep -q '"build"' "$dir/package.json" 2>/dev/null && BUILD_CMD="$pm build"
    grep -q '"typecheck"' "$dir/package.json" 2>/dev/null && TYPECHECK_CMD="$pm typecheck"
    grep -q '"test"' "$dir/package.json" 2>/dev/null && TEST_CMD="$pm test"
    grep -q '"lint"' "$dir/package.json" 2>/dev/null && LINT_CMD="$pm lint"
  elif [ -f "$dir/Cargo.toml" ]; then
    BUILD_CMD="cargo build"
    TYPECHECK_CMD="cargo check"
    TEST_CMD="cargo test"
  elif [ -f "$dir/go.mod" ]; then
    BUILD_CMD="go build ./..."
    TYPECHECK_CMD="go vet ./..."
    TEST_CMD="go test ./..."
  elif [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ]; then
    [ -f "$dir/pyproject.toml" ] && grep -q "mypy" "$dir/pyproject.toml" 2>/dev/null && TYPECHECK_CMD="mypy ."
    command -v pytest >/dev/null 2>&1 && TEST_CMD="pytest"
  elif [ -f "$dir/Makefile" ]; then
    grep -q "^build:" "$dir/Makefile" 2>/dev/null && BUILD_CMD="make build"
    grep -q "^test:" "$dir/Makefile" 2>/dev/null && TEST_CMD="make test"
  fi
}

# ============================================================
# Commands
# ============================================================

cmd_create() {
  local task_name="${1:?Usage: forge-lite.sh create <task-name>}"
  task_name=$(echo "$task_name" | tr ' ' '-' | tr -cd '[:alnum:]-_' | tr '[:upper:]' '[:lower:]')

  # Auto-prune stale worktrees before creating new one
  auto_prune

  local branch="feature/$task_name"
  local worktree_dir="$MAIN_DIR/../$(basename "$MAIN_DIR")-forge-$task_name"

  if [ -d "$worktree_dir" ]; then
    echo "Error: worktree already exists: $worktree_dir" >&2
    echo "Clean up first: forge-lite.sh cleanup $worktree_dir" >&2
    exit 1
  fi

  # Clean up leftover branch from previous crash
  if git -C "$MAIN_DIR" rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "[create] Removing leftover branch: $branch" >&2
    git -C "$MAIN_DIR" branch -D "$branch" 2>/dev/null || true
  fi

  set_state "create" "$worktree_dir"
  git -C "$MAIN_DIR" worktree add "$worktree_dir" -b "$branch" 2>&1
  clear_state
  echo "$worktree_dir"
}

cmd_verify() {
  local worktree="${1:?Usage: forge-lite.sh verify <worktree-path>}"
  [ -d "$worktree" ] || { echo "Error: directory not found: $worktree" >&2; exit 1; }

  set_state "verify" "$worktree"
  detect_commands "$worktree"

  # Install dependencies before verification (worktrees have no node_modules)
  install_deps "$worktree" || { echo "[verify] Cannot install dependencies" >&2; clear_state; return 1; }

  local failed=0
  local skipped=""

  if [ -n "$BUILD_CMD" ]; then
    echo "[verify] Running: $BUILD_CMD" >&2
    (cd "$worktree" && eval "$BUILD_CMD") || { echo "[verify] FAILED: $BUILD_CMD" >&2; failed=1; }
  else
    skipped="${skipped}build "
  fi

  if [ -n "$TYPECHECK_CMD" ] && [ "$failed" -eq 0 ]; then
    echo "[verify] Running: $TYPECHECK_CMD" >&2
    (cd "$worktree" && eval "$TYPECHECK_CMD") || { echo "[verify] FAILED: $TYPECHECK_CMD" >&2; failed=1; }
  else
    [ -z "$TYPECHECK_CMD" ] && skipped="${skipped}typecheck "
  fi

  if [ -n "$TEST_CMD" ] && [ "$failed" -eq 0 ]; then
    echo "[verify] Running: $TEST_CMD" >&2
    (cd "$worktree" && eval "$TEST_CMD") || { echo "[verify] FAILED: $TEST_CMD" >&2; failed=1; }
  else
    [ -z "$TEST_CMD" ] && skipped="${skipped}test "
  fi

  [ -n "$skipped" ] && echo "[verify] Skipped (not detected): $skipped" >&2

  clear_state
  if [ "$failed" -eq 0 ]; then
    echo "[verify] All checks passed" >&2
    return 0
  else
    echo "[verify] Verification failed — do NOT merge" >&2
    return 1
  fi
}

cmd_merge() {
  local worktree="${1:?Usage: forge-lite.sh merge <worktree-path> [message]}"
  local message="${2:-[forge] task completed}"
  [ -d "$worktree" ] || { echo "Error: directory not found: $worktree" >&2; exit 1; }

  set_state "merge" "$worktree"

  # Get branch name from worktree
  local branch
  branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    echo "Error: cannot determine branch in $worktree" >&2; exit 1;
  }

  # Check if there are uncommitted changes
  if ! git -C "$worktree" diff --quiet || ! git -C "$worktree" diff --cached --quiet; then
    echo "[merge] Committing uncommitted changes in worktree..." >&2
    git -C "$worktree" add -A
    git -C "$worktree" commit -m "$message"
  fi

  # Check if branch has commits ahead of main
  local ahead
  ahead=$(git -C "$MAIN_DIR" rev-list --count "main..$branch" 2>/dev/null) || ahead=0
  if [ "$ahead" -eq 0 ]; then
    echo "Error: branch $branch has no commits ahead of main" >&2
    exit 1
  fi

  # Merge
  echo "[merge] Merging $branch into main..." >&2
  set_state "merging" "$worktree"
  git -C "$MAIN_DIR" merge --no-ff "$branch" -m "[forge] $message" || {
    echo "[merge] Merge conflict — resolve manually in $MAIN_DIR" >&2
    exit 1
  }

  # Post-merge verify
  set_state "post-verify" "$worktree"
  detect_commands "$MAIN_DIR"
  install_deps "$MAIN_DIR" || true
  local post_fail=0
  if [ -n "$TYPECHECK_CMD" ]; then
    (cd "$MAIN_DIR" && eval "$TYPECHECK_CMD") || post_fail=1
  fi
  if [ -n "$TEST_CMD" ] && [ "$post_fail" -eq 0 ]; then
    (cd "$MAIN_DIR" && eval "$TEST_CMD") || post_fail=1
  fi

  if [ "$post_fail" -ne 0 ]; then
    echo "[merge] Post-merge verification FAILED — rolling back" >&2
    git -C "$MAIN_DIR" reset --merge HEAD~1
    echo "[merge] Main restored. Debug in worktree: $worktree" >&2
    exit 1
  fi

  # Cleanup
  echo "[merge] Cleaning up worktree and branch..." >&2
  git -C "$MAIN_DIR" worktree remove "$worktree" 2>/dev/null || rm -rf "$worktree"
  git -C "$MAIN_DIR" branch -d "$branch" 2>/dev/null || true

  clear_state
  echo "[merge] Done. Merged $branch into main." >&2
}

cmd_yolo() {
  local worktree="${1:?Usage: forge-lite.sh yolo <worktree-path> [message]}"
  local message="${2:-[forge] task completed}"

  cmd_verify "$worktree" || exit 1
  cmd_merge "$worktree" "$message"
}

cmd_cleanup() {
  local worktree="${1:?Usage: forge-lite.sh cleanup <worktree-path>}"
  [ -d "$worktree" ] || { echo "Already cleaned up: $worktree" >&2; return 0; }

  local branch
  branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""

  git -C "$MAIN_DIR" worktree remove "$worktree" 2>/dev/null || rm -rf "$worktree"
  [ -n "$branch" ] && git -C "$MAIN_DIR" branch -D "$branch" 2>/dev/null || true

  echo "[cleanup] Removed $worktree" >&2
}

cmd_recover() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "[recover] No crash state found — nothing to recover" >&2
    # Still prune stale worktrees as a courtesy
    auto_prune
    return 0
  fi

  local state_info
  state_info=$(cat "$STATE_FILE")
  local phase worktree timestamp
  phase=$(echo "$state_info" | cut -d: -f1)
  worktree=$(echo "$state_info" | cut -d: -f2)
  timestamp=$(echo "$state_info" | cut -d: -f3)

  local age=""
  if [ -n "$timestamp" ]; then
    local now
    now=$(date +%s)
    age="$(( (now - timestamp) / 60 ))min ago"
  fi

  echo "[recover] Found crash state: phase=$phase worktree=$worktree ${age:+($age)}" >&2

  case "$phase" in
    create)
      echo "[recover] Crashed during create — cleaning up partial worktree" >&2
      cmd_cleanup "$worktree" 2>/dev/null || true
      ;;
    verify)
      echo "[recover] Crashed during verify — worktree is safe" >&2
      echo "[recover] Re-verify:  forge-lite.sh verify $worktree" >&2
      echo "[recover] Or abandon: forge-lite.sh cleanup $worktree" >&2
      clear_state
      return 0
      ;;
    merge|merging)
      echo "[recover] Crashed during merge — checking main state" >&2
      if [ -f "$MAIN_DIR/.git/MERGE_HEAD" ]; then
        echo "[recover] Aborting in-progress merge on main" >&2
        git -C "$MAIN_DIR" merge --abort 2>/dev/null || true
      fi
      echo "[recover] Cleaning up worktree" >&2
      cmd_cleanup "$worktree" 2>/dev/null || true
      ;;
    post-verify)
      echo "[recover] Crashed during post-merge verify — rolling back merge" >&2
      git -C "$MAIN_DIR" reset --merge HEAD~1 2>/dev/null || true
      echo "[recover] Main restored. Cleaning up worktree" >&2
      cmd_cleanup "$worktree" 2>/dev/null || true
      ;;
    *)
      echo "[recover] Unknown phase: $phase — cleaning up" >&2
      cmd_cleanup "$worktree" 2>/dev/null || true
      ;;
  esac

  clear_state
  git -C "$MAIN_DIR" worktree prune 2>/dev/null || true
  echo "[recover] Done" >&2
}

# ============================================================
# Dispatch
# ============================================================

# Acquire lock for all commands except recover (which cleans up locks)
case "${1:-}" in
  recover) ;;
  "") ;;
  *) acquire_lock ;;
esac

preflight_check "${1:-help}"

case "${1:-}" in
  create)  shift; cmd_create "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  merge)   shift; cmd_merge "$@" ;;
  yolo)    shift; cmd_yolo "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  recover) cmd_recover ;;
  *)
    echo "Usage: forge-lite.sh <create|verify|merge|yolo|cleanup|recover> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  create <task-name>              Create worktree + feature branch" >&2
    echo "  verify <worktree-path>          Run typecheck + tests" >&2
    echo "  merge  <worktree-path> [msg]    Merge to main + cleanup" >&2
    echo "  yolo   <worktree-path> [msg]    Verify + merge in one shot" >&2
    echo "  cleanup <worktree-path>         Remove worktree without merging" >&2
    echo "  recover                         Recover from a previous crash" >&2
    exit 1
    ;;
esac
