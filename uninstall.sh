#!/usr/bin/env bash
# sprout uninstaller: removes the plugin, the ~/.zshrc loader and (optionally) your
# configuration and stored Jira token.
set -euo pipefail

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sprout"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sprout"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
MARK_BEGIN="# >>> sprout (Jira branch helper) >>>"
MARK_END="# <<< sprout <<<"

INPUT="${SPROUT_INSTALL_INPUT:-/dev/tty}"
INTERACTIVE=1
{ : < "$INPUT"; } 2>/dev/null || INTERACTIVE=0
# Open the input once so successive reads advance (works for a file or a terminal).
[ "$INTERACTIVE" -eq 1 ] && exec 3< "$INPUT"

# yesno "Question" -> exit status 0 for yes (default: no; always no without a terminal).
yesno() {
  local reply=""
  if [ "$INTERACTIVE" -eq 1 ]; then
    read -r -p "  $1 (y/N): " reply <&3 || true
  fi
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Remove the loader block from ~/.zshrc.
if [ -f "$ZSHRC" ] && grep -qF "$MARK_BEGIN" "$ZSHRC"; then
  tmp="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$ZSHRC" > "$tmp"
  cat "$tmp" > "$ZSHRC"
  rm -f "$tmp"
  echo "Removed the loader from $ZSHRC"
fi

if [ -d "$DATA_DIR" ]; then
  rm -rf "$DATA_DIR"
  echo "Removed $DATA_DIR"
fi

if [ -d "$CONF_DIR" ] && yesno "Delete your configuration in $CONF_DIR?"; then
  rm -rf "$CONF_DIR"
  echo "Removed $CONF_DIR"
fi

if yesno "Delete the stored Jira API token (service sprout-jira-token)?"; then
  if command -v security >/dev/null 2>&1; then
    security delete-generic-password -s sprout-jira-token >/dev/null 2>&1 && echo "Token removed from the Keychain." || true
  fi
  if command -v secret-tool >/dev/null 2>&1; then
    secret-tool clear service sprout-jira-token 2>/dev/null && echo "Token removed from libsecret." || true
  fi
fi

echo "Done. Open a new terminal for the change to take effect."
