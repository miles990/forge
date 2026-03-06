#!/usr/bin/env bash
set -euo pipefail

# Forge installer — auto-detects platform and installs SKILL.md to the right place
# Usage: curl -fsSL https://raw.githubusercontent.com/miles990/forge/main/install.sh | bash

REPO="miles990/forge"
SKILL_URL="https://raw.githubusercontent.com/$REPO/main/forge/1.0.0/skills/forge/SKILL.md"
SKILL_CONTENT=""

fetch_skill() {
  SKILL_CONTENT=$(curl -fsSL "$SKILL_URL")
  if [ -z "$SKILL_CONTENT" ]; then
    echo "Error: Failed to download SKILL.md"
    exit 1
  fi
}

install_to() {
  local dir="$1"
  local file="$2"
  mkdir -p "$dir"
  echo "$SKILL_CONTENT" > "$dir/$file"
  echo "  Installed: $dir/$file"
}

detect_and_install() {
  local installed=0

  # Claude Code — requires official plugin commands, not file copy
  if command -v claude &>/dev/null; then
    echo "[claude-code] Detected. Registering marketplace and installing plugin..."
    claude marketplace:add "github:$REPO" 2>/dev/null || true
    if claude plugin:add forge 2>/dev/null; then
      echo "  Installed via claude plugin:add"
      echo "  Use: /forge path/to/plan.md"
    else
      echo "  Auto-install failed. Run manually:"
      echo "    claude marketplace:add github:$REPO"
      echo "    claude plugin:add forge"
    fi
    installed=1
  fi

  # OpenClaw
  if [ -d "$HOME/.openclaw" ]; then
    install_to "$HOME/.openclaw/custom_skills" "forge.md"
    echo "  Use: Tell your agent to 'use the forge skill to execute plan.md'"
    installed=1
  fi

  # Cursor
  if [ -d ".cursor" ] || [ -d "$HOME/.cursor" ]; then
    install_to ".cursor/rules" "forge.md"
    echo "  Use: 'Follow the forge workflow in .cursor/rules/forge.md to execute plan.md'"
    installed=1
  fi

  # Windsurf
  if [ -d ".windsurfrules" ]; then
    install_to ".windsurfrules" "forge.md"
    echo "  Use: 'Follow the forge workflow to execute plan.md'"
    installed=1
  fi

  # Continue.dev
  if [ -d ".continue" ]; then
    install_to ".continue/rules" "forge.md"
    echo "  Use: 'Follow the forge workflow to execute plan.md'"
    installed=1
  fi

  # Aider — just download, user includes manually
  if command -v aider &>/dev/null; then
    install_to "." "forge.md"
    echo "  Use: aider --read forge.md"
    installed=1
  fi

  # Fallback: install to current project
  if [ "$installed" -eq 0 ]; then
    install_to "." "forge.md"
    echo "  Include this file in your LLM's context to use Forge."
  fi
}

main() {
  echo "Forge installer"
  echo "==============="
  echo ""
  echo "Downloading SKILL.md..."
  fetch_skill
  echo "Detecting platforms..."
  echo ""
  detect_and_install
  echo ""
  echo "Done. Documentation: https://github.com/$REPO"
}

main
