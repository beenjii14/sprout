#!/usr/bin/env bash
# sprout installer - interactive setup for macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/beenjii14/sprout/main/install.sh | bash
#
# or, from a clone:  ./install.sh
#
# Every question has a default; press Enter to accept it. Environment variables
# (SPROUT_JIRA_HOST, JIRA_EMAIL, SPROUT_BASE, JIRA_API_TOKEN) pre-fill the answers, and
# when no terminal is available the installer runs without asking anything.
set -euo pipefail

REPO="beenjii14/sprout"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sprout"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sprout"
CONF_FILE="$CONF_DIR/config"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
MARK_BEGIN="# >>> sprout (Jira branch helper) >>>"
MARK_END="# <<< sprout <<<"

# Where answers are read from: the controlling terminal, so `curl | bash` works.
INPUT="${SPROUT_INSTALL_INPUT:-/dev/tty}"
INTERACTIVE=1
{ : < "$INPUT"; } 2>/dev/null || INTERACTIVE=0
# Open the input once so successive reads advance (works for a file or a terminal).
[ "$INTERACTIVE" -eq 1 ] && exec 3< "$INPUT"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ask "Question" "default" -> prints the answer (the default when empty/non-interactive).
ask() {
  local prompt="$1" default="${2:-}" reply=""
  if [ "$INTERACTIVE" -eq 1 ]; then
    if [ -n "$default" ]; then
      read -r -p "  $prompt [$default]: " reply <&3 || true
    else
      read -r -p "  $prompt: " reply <&3 || true
    fi
  fi
  printf '%s' "${reply:-$default}"
}

# yesno "Question" "y|n" -> exit status 0 for yes.
yesno() {
  local answer; answer="$(ask "$1 (y/n)" "$2")"
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Rejects values that could break the generated shell config.
safe() {
  case "$1" in
    *\"*|*\$*|*\`*|*\\*) die "'$1' contains characters that are not allowed (\" \$ \` \\)." ;;
  esac
}

bold "sprout - Git branches from Jira tickets"
echo

# 1. Dependencies ------------------------------------------------------------
missing=""
for bin in zsh git curl jq perl; do
  command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
if [ -n "$missing" ]; then
  die "missing dependencies:$missing  (macOS: brew install$missing | Debian/Ubuntu: sudo apt install$missing)"
fi
# AI CLIs sprout can use to shorten names (optional): "command:Vendor".
AI_CANDIDATES="claude:Anthropic gemini:Google codex:OpenAI copilot:GitHub cursor-agent:Cursor"
ai_found=""
for entry in $AI_CANDIDATES; do
  command -v "${entry%%:*}" >/dev/null 2>&1 && ai_found="$ai_found $entry"
done
[ -n "$ai_found" ] \
  || info "No AI CLI found (claude, gemini, codex, copilot, cursor-agent): names will use the built-in rule (still works; install one later for smarter names)."

# 2. Install the plugin file ---------------------------------------------------
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
PLUGIN_PATH="$DATA_DIR/sprout.plugin.zsh"
if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/../share/sprout/sprout.plugin.zsh" ]; then
  # Installed by a package manager (e.g. Homebrew): load the plugin where it already lives.
  PLUGIN_PATH="$(cd "$SRC_DIR/../share/sprout" && pwd)/sprout.plugin.zsh"
  info "Using the packaged plugin at $PLUGIN_PATH"
else
  mkdir -p "$DATA_DIR"
  if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/sprout.plugin.zsh" ]; then
    cp "$SRC_DIR/sprout.plugin.zsh" "$PLUGIN_PATH"
  else
    curl -fsSL "$RAW_URL/sprout.plugin.zsh" -o "$PLUGIN_PATH" \
      || die "could not download sprout.plugin.zsh from $RAW_URL"
  fi
  info "Installed $PLUGIN_PATH"
fi
echo

# 3. Questions -----------------------------------------------------------------
bold "Jira (leave the host empty to skip the Jira lookup and always pass titles by hand)"
jira_host="$(ask "Jira site host, e.g. your-team.atlassian.net" "${SPROUT_JIRA_HOST:-}")"
jira_host="${jira_host#https://}"; jira_host="${jira_host%%/*}"
jira_email=""
token=""
if [ -n "$jira_host" ]; then
  jira_email="$(ask "Atlassian account email" "${JIRA_EMAIL:-$(git config --global user.email 2>/dev/null || true)}")"
  echo "  Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens"
  if [ "$INTERACTIVE" -eq 1 ]; then
    read -r -s -p "  Atlassian API token (hidden, Enter to keep the stored one): " token <&3 || true
    echo
  fi
fi

echo
bold "Git"
base="$(ask "Base branch to branch from (empty = auto-detect the remote default)" "${SPROUT_BASE:-}")"

echo
bold "Naming"
ai=1; ai_provider=""
set -- $ai_found
if [ "$#" -eq 0 ]; then
  ai=0
else
  choice="${1%%:*}"; vendor="${1#*:}"
  if [ "$#" -gt 1 ]; then
    list=""; for entry in "$@"; do list="$list ${entry%%:*}"; done
    choice="$(ask "AI CLIs found:$list. Which one should shorten names? (none = local rule)" "$choice")"
    vendor=""
    for entry in "$@"; do [ "${entry%%:*}" = "$choice" ] && vendor="${entry#*:}"; done
    [ -n "$vendor" ] || ai=0
  fi
  if [ "$ai" -eq 1 ]; then
    yesno "Use $choice to shorten branch names? The ticket title and description are sent to $vendor" "y" \
      && ai_provider="$choice" || ai=0
  fi
fi

safe "$jira_host"; safe "$jira_email"; safe "$base"; safe "$ai_provider"

# 4. Store the token ---------------------------------------------------------------
store_token() {
  if command -v security >/dev/null 2>&1; then
    security add-generic-password -U -a "${USER:-sprout}" -s sprout-jira-token -w "$1" >/dev/null
  elif command -v secret-tool >/dev/null 2>&1; then
    printf '%s' "$1" | secret-tool store --label="sprout Jira API token" service sprout-jira-token
  else
    mkdir -p "$CONF_DIR"
    ( umask 077; printf '%s\n' "$1" > "$CONF_DIR/token" )
    info "No keychain tool found: token saved in $CONF_DIR/token (mode 600)."
  fi
}
if [ -n "$token" ]; then
  store_token "$token"
elif [ -n "${JIRA_API_TOKEN:-}" ] && [ "$INTERACTIVE" -eq 0 ] && [ -n "$jira_host" ]; then
  info "Using JIRA_API_TOKEN from the environment (not stored)."
fi
unset token

# 5. Write the configuration (no secrets) -------------------------------------------
mkdir -p "$CONF_DIR"
{
  echo "# Generated by sprout install.sh. Edit freely; variables already exported in your shell win."
  [ -n "$jira_host" ]  && printf 'export SPROUT_JIRA_HOST="${SPROUT_JIRA_HOST:-%s}"\n' "$jira_host"
  [ -n "$jira_email" ] && printf 'export JIRA_EMAIL="${JIRA_EMAIL:-%s}"\n' "$jira_email"
  [ -n "$base" ]       && printf 'export SPROUT_BASE="${SPROUT_BASE:-%s}"\n' "$base"
  printf 'export SPROUT_AI="${SPROUT_AI:-%s}"\n' "$ai"
  [ -n "$ai_provider" ] && printf 'export SPROUT_AI_PROVIDER="${SPROUT_AI_PROVIDER:-%s}"\n' "$ai_provider"
  echo '# export SPROUT_AI_CMD="your-ai-cli {prompt}"  # any AI CLI: {prompt} is replaced by the prompt, or it is sent on stdin'
  echo '# export SPROUT_TYPES="feat fix chore"   # allowed branch types (the type comes from the Jira issue type, default feat)'
  echo '# export SPROUT_LANG="en"                # language of AI-generated names: en, es, pt, fr, de, it, ... or "ticket"'
  echo '# export SPROUT_BRANCH_FORMAT="{ID}/{type}-{slug}"'
  echo '# export SPROUT_COMMAND="sprout"          # rename the command if "sprout" clashes with another tool'
} > "$CONF_FILE"
chmod 600 "$CONF_FILE"
info "Configuration saved in $CONF_FILE"

# 6. Load the plugin from ~/.zshrc -------------------------------------------------------
touch "$ZSHRC"
if grep -qF "$MARK_BEGIN" "$ZSHRC"; then
  info "$ZSHRC already loads sprout."
else
  {
    echo
    echo "$MARK_BEGIN"
    echo "source \"$PLUGIN_PATH\""
    echo "$MARK_END"
  } >> "$ZSHRC"
  info "Added the loader to $ZSHRC"
fi

# 7. Check the Jira connection (read-only) ---------------------------------------------------
echo
if [ -n "$jira_host" ]; then
  stored=""
  if [ -n "${JIRA_API_TOKEN:-}" ]; then stored="$JIRA_API_TOKEN"
  elif command -v security >/dev/null 2>&1; then stored="$(security find-generic-password -s sprout-jira-token -w 2>/dev/null || true)"
  elif command -v secret-tool >/dev/null 2>&1; then stored="$(secret-tool lookup service sprout-jira-token 2>/dev/null || true)"
  elif [ -r "$CONF_DIR/token" ]; then stored="$(tr -d '[:space:]' < "$CONF_DIR/token")"
  fi
  if [ -n "$stored" ] && [ -n "$jira_email" ]; then
    code="$(printf 'user = "%s:%s"\n' "$jira_email" "$stored" \
      | curl -s -o /dev/null -w '%{http_code}' --max-time 10 -K - "https://$jira_host/rest/api/3/myself" || true)"
    if [ "$code" = "200" ]; then info "Jira connection OK."
    else warn "Jira answered HTTP $code - check the host, email and token."; fi
  else
    warn "No token found yet: sprout cannot fetch titles from Jira until you add one (see the README)."
  fi
  unset stored
fi

echo
bold "Done."
info "Ready. In any repository run:  sprout <TICKET-KEY>   (add --dry-run to preview the name)"
if [ "$INTERACTIVE" -eq 1 ] && [ -t 0 ] && [ -z "${SPROUT_INSTALL_NO_SHELL:-}" ]; then
  info "Opening a new zsh with sprout loaded (type 'exit' to go back)..."
  exec zsh -i
fi
info "Open a new terminal (or run: source $ZSHRC) to start using it."
