#!/usr/bin/env bash
set -euo pipefail

# Install nomadic — portable shell environment manager
# Usage: curl -fsSL https://raw.githubusercontent.com/nijotz/nomadic/main/install.sh | bash

REPO="nijotz/nomadic"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/main/nomadic"

echo "[nomadic] Installing to ${INSTALL_DIR}/nomadic"

mkdir -p "$INSTALL_DIR"
curl -fsSL "$SCRIPT_URL" -o "${INSTALL_DIR}/nomadic"
chmod +x "${INSTALL_DIR}/nomadic"

# Add ~/.local/bin to PATH in shell rc if not already there
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  PATH_LINE='export PATH="$HOME/.local/bin:$PATH"  # added by nomadic'

  add_to_rc() {
    local rc_file="$1"
    if [[ -f "$rc_file" ]] && grep -q 'added by nomadic' "$rc_file"; then
      return
    fi
    echo "$PATH_LINE" >>"$rc_file"
    echo "[nomadic] Added ~/.local/bin to PATH in $rc_file"
  }

  if [[ -f "$HOME/.bashrc" ]] || [[ "$(basename "$SHELL")" == "bash" ]]; then
    add_to_rc "$HOME/.bashrc"
  fi

  if [[ -f "$HOME/.zshrc" ]] || [[ "$(basename "$SHELL")" == "zsh" ]]; then
    add_to_rc "$HOME/.zshrc"
  fi
fi

echo "[nomadic] Installed! To get started:"
echo ""
echo "  exec bash   # reload your shell"
echo "  nomadic init"
echo ""
