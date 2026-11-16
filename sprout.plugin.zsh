# sprout - create Git branches straight from Jira tickets.
# https://github.com/beenjii14/sprout
#
# Source this file from your ~/.zshrc (the installer does it for you):
#
#   source ~/.local/share/sprout/sprout.plugin.zsh
#
# Usage:  sprout [-n|--dry-run] [<KEY|URL>] ["<title>"] [<type>]
# Docs:   sprout --help  |  README.md

typeset -g SPROUT_VERSION="0.5.0"

# Configuration file written by install.sh. Variables already exported in the
# shell win over the ones in the file.
: ${SPROUT_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/sprout/config}
[[ -r "$SPROUT_CONFIG" ]] && source "$SPROUT_CONFIG"

# Prints an error message prefixed with the command name to stderr.
_sprout_err() {
  print -u2 -r -- "sprout: $*"
}

# Prints the Jira API token from the first available source:
# $JIRA_API_TOKEN, macOS Keychain, libsecret (Linux) or a 600-mode token file.
_sprout_token() {
  emulate -L zsh
  local token_file="${SPROUT_CONFIG:h}/token"

  if [[ -n "$JIRA_API_TOKEN" ]]; then
    print -rn -- "$JIRA_API_TOKEN"; return 0
  fi
  if (( $+commands[security] )); then
    security find-generic-password -s sprout-jira-token -w 2>/dev/null && return 0
  fi
  if (( $+commands[secret-tool] )); then
    secret-tool lookup service sprout-jira-token 2>/dev/null && return 0
  fi
  if [[ -r "$token_file" ]]; then
    tr -d '[:space:]' < "$token_file"; return 0
  fi
  return 1
}

# Prints the first 500 characters of the system clipboard, if a tool exists.
_sprout_clipboard() {
  emulate -L zsh
  local clip=""
  if   (( $+commands[pbpaste]  )); then clip="$(pbpaste 2>/dev/null)"
  elif (( $+commands[wl-paste] )); then clip="$(wl-paste --no-newline 2>/dev/null)"
  elif (( $+commands[xclip]    )); then clip="$(xclip -selection clipboard -o 2>/dev/null)"
  elif (( $+commands[xsel]     )); then clip="$(xsel --clipboard --output 2>/dev/null)"
  fi
  print -rn -- "${clip[1,500]}"
}

# Extracts and upper-cases a Jira issue key (e.g. PROJ-123) from a bare key or
# a URL. Prefers /browse/KEY and ?selectedIssue=KEY so host names never match.
_sprout_extract_key() {
  emulate -L zsh
  local input="$1" re
  for re in \
    '/browse/([A-Za-z][A-Za-z0-9_]+-[0-9]+)' \
    'selectedIssue=([A-Za-z][A-Za-z0-9_]+-[0-9]+)' \
    '([A-Za-z][A-Za-z0-9_]+-[0-9]+)'; do
    if [[ "$input" =~ $re ]]; then
      print -r -- "${(U)match[1]}"
      return 0
    fi
  done
  return 1
}

# Turns a string into a slug: lowercase, accents stripped, anything outside
# [a-z0-9] becomes "-", trimmed, at most $2 characters (default 50).
_sprout_slugify() {
  emulate -L zsh
  printf '%s' "$1" | perl -CS -MUnicode::Normalize -se '
    while (<STDIN>) {
      $_ = NFD($_);
      s/\p{Mn}//g;
      $_ = lc;
      s/[^a-z0-9]+/-/g;
      s/^-+|-+$//g;
      $_ = substr($_, 0, $max);
      s/-+$//;
      print;
    }' -- -max="${2:-50}"
}

# Prints "<issue type>\t<summary>\t<description excerpt>" for a Jira Cloud issue.
# Return codes: 2 no host, 3 no token, 4 no email, 5 request failed.
_sprout_jira_fetch() {
  emulate -L zsh
  local key="$1" host="${SPROUT_JIRA_HOST#https://}" email token
  host="${host%%/*}"
  email="${JIRA_EMAIL:-$(git config user.email 2>/dev/null)}"

  [[ -n "$host" ]] || return 2
  token="$(_sprout_token)" || return 3
  [[ -n "$email" ]] || return 4

  # Credentials go through stdin so they never show up in `ps`.
  printf 'user = "%s:%s"\n' "$email" "$token" \
    | curl -sS --fail --max-time 10 -K - -H 'Accept: application/json' \
        "https://${host}/rest/api/3/issue/${key}?fields=summary,issuetype,description" 2>/dev/null \
    | jq -er '[.fields.issuetype.name, .fields.summary,
               ([.fields.description | .. | .text? // empty] | join(" ")
                | gsub("\\s+"; " ") | .[0:1500])] | @tsv' 2>/dev/null \
    || return 5
}

# Maps a Jira issue type name to one of feat|fix|chore.
_sprout_type_from_issue() {
  emulate -L zsh
  case "${(L)1}" in
    *bug*|*defect*|*incident*|*error*)                        print fix ;;
    *chore*|*tech*|*sub-task*|*subtask*|*spike*|*task\ tech*) print chore ;;
    *)                                                        print feat ;;
  esac
}

# Prints the language instruction for the AI prompt from $SPROUT_LANG
# (default "en"): a code (en, es, pt, fr, de, it), a language name, or "ticket"
# to keep whatever language the ticket is written in.
_sprout_language_rule() {
  emulate -L zsh
  local lang="${SPROUT_LANG:-en}"
  case "${(L)lang}" in
    ticket|auto) print -rn -- "Write the name in the same language as the ticket." ;;
    en)          print -rn -- "Write the name in English, translating the key words if the ticket is in another language." ;;
    es)          print -rn -- "Write the name in Spanish, translating the key words if the ticket is in another language." ;;
    pt)          print -rn -- "Write the name in Portuguese, translating the key words if the ticket is in another language." ;;
    fr)          print -rn -- "Write the name in French, translating the key words if the ticket is in another language." ;;
    de)          print -rn -- "Write the name in German, translating the key words if the ticket is in another language." ;;
    it)          print -rn -- "Write the name in Italian, translating the key words if the ticket is in another language." ;;
    *)           print -rn -- "Write the name in ${lang}, translating the key words if the ticket is in another language." ;;
  esac
}

# Prints the Cursor CLI binary: `agent` (current installs, only when its help mentions
# Cursor) or `cursor-agent` (older installs, which can be a stale copy next to a newer
# `agent`, so it comes second). Returns 1 when neither is found.
_sprout_cursor_bin() {
  emulate -L zsh
  if (( $+commands[agent] )) && agent --help </dev/null 2>&1 | head -n 20 | grep -qi cursor; then
    print agent; return 0
  fi
  (( $+commands[cursor-agent] )) && { print cursor-agent; return 0; }
  return 1
}

# Prints the AI providers to try, one per line and in order: "custom" when
# $SPROUT_AI_CMD is set, else the names in $SPROUT_AI_PROVIDER (comma or space
# separated), else the first supported CLI found on the PATH.
_sprout_ai_providers() {
  emulate -L zsh
  local c p
  if [[ -n "$SPROUT_AI_CMD" ]]; then print custom; return 0; fi
  if [[ -n "$SPROUT_AI_PROVIDER" ]]; then
    for p in ${(s:,:)${SPROUT_AI_PROVIDER// /,}}; do [[ -n "$p" ]] && print -r -- "${(L)p}"; done
    return 0
  fi
  for c in claude gemini codex copilot; do
    (( $+commands[$c] )) && { print $c; return 0; }
  done
  _sprout_cursor_bin >/dev/null && print cursor
  return 0
}

# Fills `reply` with the command for provider $1 (default: the first provider): the
# SPROUT_AI_CMD words for "custom", or a preset. A `{prompt}` word is replaced by the
# prompt; without one the prompt goes to stdin. Returns 1 when it is not usable.
_sprout_ai_command() {
  emulate -L zsh
  local p="${1:-$(_sprout_ai_providers | head -n 1)}" model="${SPROUT_AI_MODEL:-}" c
  reply=()
  case "$p" in
    custom)              reply=("${(@Q)${(z)SPROUT_AI_CMD}}")
                         (( $#reply )) && (( $+commands[$reply[1]] )); return ;;
    claude)              reply=(claude -p --model "${model:-haiku}" '{prompt}') ;;
    gemini)              reply=(gemini ${model:+-m} ${model:+$model} -p '{prompt}') ;;
    codex)               reply=(codex exec ${model:+-m} ${model:+$model} -) ;;
    copilot)             reply=(copilot -s ${model:+--model} ${model:+$model} -p '{prompt}') ;;
    cursor|cursor-agent) c="$(_sprout_cursor_bin)" || return 1
                         reply=($c -p --trust ${model:+--model} ${model:+$model} '{prompt}') ;;
    *)                   return 1 ;;
  esac
  (( $+commands[$reply[1]] ))
}

# Prints the seconds to wait for each AI: $SPROUT_AI_TIMEOUT, else 8 when there is
# another provider to fall back to ($1 = number of providers), else 25.
_sprout_ai_timeout() {
  emulate -L zsh
  if [[ "$SPROUT_AI_TIMEOUT" == <-> ]]; then print -r -- "$SPROUT_AI_TIMEOUT"
  elif (( ${1:-1} > 1 )); then print 8
  else print 25
  fi
}

# Directory with the "this AI was slow or failed recently" markers.
_sprout_ai_state() { print -r -- "${XDG_CACHE_HOME:-$HOME/.cache}/sprout"; }

# True when provider $1 failed within the last $SPROUT_AI_SKIP_MINUTES (default 60).
_sprout_ai_skipped() {
  emulate -L zsh
  local m="${SPROUT_AI_SKIP_MINUTES:-60}" f
  [[ "$m" == <-> ]] || m=60
  (( m > 0 )) || return 1
  f=("$(_sprout_ai_state)/skip-$1"(N.mm-$m))
  (( $#f ))
}

# Marks provider $1 as failing ($2 = bad) or healthy (anything else).
_sprout_ai_mark() {
  emulate -L zsh
  local d="$(_sprout_ai_state)"
  if [[ "$2" == bad ]]; then mkdir -p "$d" 2>/dev/null && : >| "$d/skip-$1" 2>/dev/null
  else rm -f "$d/skip-$1" 2>/dev/null
  fi
  return 0
}

# True when $1 is a well-formed branch name: 2-5 hyphenated lowercase words.
_sprout_valid_name() {
  emulate -L zsh
  [[ "$1" =~ '^[a-z0-9]+(-[a-z0-9]+){0,5}$' && ${#1} -ge 3 && ${#1} -le 40 ]]
}

# Runs provider $1 on prompt $2 with a limit of $3 seconds; prints its raw answer
# and returns its exit status (142 on a timeout). stderr goes to $SPROUT_AI_STDERR.
_sprout_ai_run() {
  emulate -L zsh
  local prompt="$2" limit="$3" i has=0
  local -a cmd
  _sprout_ai_command "$1" || return 127
  cmd=("${reply[@]}")
  for i in {1..$#cmd}; do
    if [[ "${cmd[i]}" == *'{prompt}'* ]]; then cmd[i]="${cmd[i]//\{prompt\}/$prompt}"; has=1; fi
  done
  if (( has )); then
    perl -e 'alarm shift; exec @ARGV' "$limit" "${cmd[@]}" </dev/null 2>>"${SPROUT_AI_STDERR:-/dev/null}"
  else
    printf '%s' "$prompt" | perl -e 'alarm shift; exec @ARGV' "$limit" "${cmd[@]}" 2>>"${SPROUT_AI_STDERR:-/dev/null}"
  fi
}

# Asks the providers in order and prints the first well-formed name. A provider that
# is slow, fails or answers badly is skipped for a while and the next one is tried.
# Returns 2 when no provider is usable, 1 when all that were tried failed.
_sprout_ai_ask() {
  emulate -L zsh
  local prompt="$1" p out name limit i tried=0
  local -a provs usable
  provs=(${(f)"$(_sprout_ai_providers)"})
  for p in $provs; do _sprout_ai_command "$p" && usable+=("$p"); done
  (( $#usable )) || return 2
  limit="$(_sprout_ai_timeout $#usable)"
  for i in {1..$#usable}; do
    p="$usable[i]"
    # Skip a recently failing AI, but never skip when it is the only one left to try.
    if _sprout_ai_skipped "$p" && (( tried || i < $#usable )); then continue; fi
    tried=1
    out="$(_sprout_ai_run "$p" "$prompt" "$limit")"
    name="${out##*$'\n'}"
    if _sprout_valid_name "$name"; then
      _sprout_ai_mark "$p" ok
      print -r -- "$name"
      return 0
    fi
    _sprout_ai_mark "$p" bad
    if (( i < $#usable )); then
      print -u2 -r -- "sprout: $p gave no usable name within ${limit} s; trying ${usable[i+1]}."
    fi
  done
  (( tried )) && return 1
  return 1
}

# Condenses a ticket into 2-5 slug words: asks the configured AI tools in order when
# there are any, otherwise drops stop-words and keeps the first four meaningful words
# (the local fallback cannot translate: it keeps the ticket's own words).
_sprout_shorten() {
  emulate -L zsh
  local title="$1" desc="$2" out="" rc

  if [[ "${SPROUT_AI:-1}" != 0 ]]; then
    out="$(_sprout_ai_ask "Create a short git branch name for this Jira ticket. Rules: 2 to 5 lowercase words joined by hyphens, ASCII only (no accents), no prefix (no change type, no ticket key). Short but descriptive. Base it on the TITLE; use the description only to disambiguate and to pick the most representative words. Keep proper nouns and technologies; drop generic verbs (set up, create, implement). Do not invent concepts that are not in the ticket. $(_sprout_language_rule) Reply with ONLY the name.

Ticket title: ${title}
Description / acceptance criteria: ${desc}")"
    rc=$?
    if (( rc == 1 )); then
      out=""
      print -u2 -r -- "sprout: no AI gave a usable name; using the local rule. Run '${SPROUT_COMMAND:-sprout} --doctor' to see why."
    elif (( rc != 0 )); then
      out=""
    fi
  fi

  if [[ -z "$out" ]]; then
    local stop=' a an and as at by de del el en for from in into la las lo los of on or para por the to un una with y o u al con segun sobre que se su sus como cuando '
    local -a words=() parts
    local w
    parts=("${(@s:-:)$(_sprout_slugify "$title" 200)}")
    for w in $parts; do
      [[ "$stop" == *" $w "* ]] || words+=("$w")
    done
    out="${(j:-:)words[1,4]}"
  fi
  print -rn -- "$out"
}

# Prints the base branch: $SPROUT_BASE, else the remote's default branch, else main.
_sprout_default_base() {
  emulate -L zsh
  local remote="${SPROUT_REMOTE:-origin}" ref
  if [[ -n "$SPROUT_BASE" ]]; then print -r -- "$SPROUT_BASE"; return 0; fi
  if ref="$(git symbolic-ref --quiet --short "refs/remotes/${remote}/HEAD" 2>/dev/null)"; then
    print -r -- "${ref#${remote}/}"; return 0
  fi
  print main
}

# Explains which AI tools sprout would use, in order, and tests each with a real call.
_sprout_doctor() {
  emulate -L zsh
  local p out name start limit errfile ask_rc rc=0 shown=0
  local -a provs usable
  print -r -- "sprout $SPROUT_VERSION"
  print -r -- "config:   ${SPROUT_CONFIG:-$HOME/.config/sprout/config}"
  print -r -- "SPROUT_AI=${SPROUT_AI:-1}  SPROUT_AI_PROVIDER=${SPROUT_AI_PROVIDER:-<auto>}  SPROUT_AI_CMD=${SPROUT_AI_CMD:-<unset>}"
  if [[ "${SPROUT_AI:-1}" == 0 ]]; then
    print -r -- "AI is turned off (SPROUT_AI=0). Names use the local rule."
    print -r -- "Turn it on: set SPROUT_AI=1 in your config, or run sprout-setup again."
    return 0
  fi
  provs=(${(f)"$(_sprout_ai_providers)"})
  for p in $provs; do _sprout_ai_command "$p" && usable+=("$p"); done
  if (( ! $#usable )); then
    print -r -- "No usable AI command found. Install one of: claude, gemini, codex, copilot, agent (Cursor CLI),"
    print -r -- "or set SPROUT_AI_CMD. The editors (Cursor, VS Code Copilot) are not the same as their command-line tools."
    return 1
  fi
  limit="$(_sprout_ai_timeout $#usable)"
  if (( $#usable > 1 )); then
    print -r -- "order:    ${(j: -> :)usable}   (each gets up to ${limit} s, then the next one is tried)"
  else
    print -r -- "using:    ${usable[1]}   (up to ${limit} s)"
  fi
  for p in $usable; do
    _sprout_ai_command "$p"
    print -r -- ""
    print -r -- "[$p] ${(j: :)reply[1,-2]} ..."
    errfile="$(mktemp)"
    start=$SECONDS
    out="$(SPROUT_AI_STDERR="$errfile" _sprout_ai_run "$p" "Create a short git branch name for a Jira ticket titled 'Add dark mode toggle to settings'. Rules: 2 to 5 lowercase words joined by hyphens, ASCII only. Reply with ONLY the name." "$limit")"
    ask_rc=$?
    name="${out##*$'\n'}"
    if _sprout_valid_name "$name"; then
      print -r -- "  OK: got '$name' in $(( SECONDS - start )) s."
      _sprout_ai_mark "$p" ok
    else
      (( ${#usable} > 1 )) || rc=1
      print -r -- "  FAILED after $(( SECONDS - start )) s (exit code $ask_rc): no usable name."
      [[ -n "$out" ]] && print -r -- "  output:   ${out[1,300]}"
      [[ -s "$errfile" ]] && print -r -- "  error:    $(head -c 400 "$errfile")"
      if (( ask_rc == 142 )); then
        print -r -- "  It did not answer in ${limit} s. If the tool is just slow, give it more time: export SPROUT_AI_TIMEOUT=90"
      else
        print -r -- "  Try the same command by hand to see more; it may need login, an update, workspace trust or a network."
      fi
    fi
    rm -f "$errfile"
  done
  return $rc
}

# Prints the help text.
_sprout_usage() {
  cat <<EOF
sprout $SPROUT_VERSION - create Git branches straight from Jira tickets

Usage:
  sprout [options] [<KEY|URL>] ["<title>"] [<type>]

Arguments:
  KEY|URL   Issue key (PROJ-123) or a Jira URL. Defaults to the clipboard.
  title     Ticket title. Defaults to the one fetched from Jira.
  type      One of: ${SPROUT_TYPES:-feat fix chore}. Defaults to the issue type mapping, else feat.

Options:
  -b, --base <branch>   Start from this branch instead of the configured base.
  -r, --remote <name>   Pull from this remote instead of the configured one.
      --no-pull         Skip the pull for this run (offline work).
  -n, --dry-run         Print the branch name only; do not touch Git.
      --doctor          Check which AI sprout uses and test it.
  -h, --help            Show this help.
  -v, --version         Show the version.

Examples:
  sprout PROJ-123                      # title and type come from Jira
  sprout PROJ-123 "Add login page"     # no Jira lookup needed
  sprout https://acme.atlassian.net/browse/PROJ-123 "Hotfix" fix
  sprout PROJ-123 --base develop       # branch off develop just this once
EOF
}

# Entry point behind the user-facing command: resolves key, title and type,
# builds the branch name and creates (or switches to) the branch.
_sprout_run() {
  emulate -L zsh
  local -a args
  local dry="${SPROUT_DRY_RUN:-}" base_opt="" remote_opt="" pull="${SPROUT_PULL:-1}"

  while (( $# )); do
    case "$1" in
      -h|--help)    _sprout_usage; return 0 ;;
      -v|--version) print "sprout $SPROUT_VERSION"; return 0 ;;
      -n|--dry-run) dry=1 ;;
      --doctor)     _sprout_doctor; return $? ;;
      --no-pull)    pull=0 ;;
      -b|--base|-r|--remote)
        if [[ -z "$2" || "$2" == -* ]]; then
          _sprout_err "$1 needs a value."
          print -u2 -r -- "Run '${SPROUT_COMMAND:-sprout} --help' for usage."
          return 1
        fi
        if [[ "$1" == -b || "$1" == --base ]]; then base_opt="$2"; else remote_opt="$2"; fi
        shift ;;
      --base=*)     base_opt="${1#--base=}" ;;
      --remote=*)   remote_opt="${1#--remote=}" ;;
      --)           shift; args+=("$@"); break ;;
      *)            args+=("$1") ;;
    esac
    shift
  done

  local input="${args[1]}" title="${args[2]}" type="${args[3]}" slug="" key
  local types="${SPROUT_TYPES:-feat fix chore}"

  [[ -z "$input" ]] && input="$(_sprout_clipboard)"
  if ! key="$(_sprout_extract_key "$input")"; then
    _sprout_err "no Jira issue key found in the arguments or the clipboard."
    print -u2 -r -- "Run '${SPROUT_COMMAND:-sprout} --help' for usage."
    return 1
  fi

  # Title (and type) from Jira when not given explicitly.
  if [[ -z "$title" ]]; then
    local row rc
    row="$(_sprout_jira_fetch "$key")"; rc=$?
    if (( rc == 0 )) && [[ -n "$row" ]]; then
      local -a fields=("${(@ps:\t:)row}")
      title="${fields[2]}"
      [[ -z "$type" ]] && type="$(_sprout_type_from_issue "${fields[1]}")"
      print -u2 -r -- "Jira: $title"
      slug="$(_sprout_shorten "$title" "${fields[3]}")"
    else
      case $rc in
        2) _sprout_err "set SPROUT_JIRA_HOST (e.g. your-team.atlassian.net) to fetch titles from Jira, or pass the title yourself." ;;
        3) _sprout_err "no Jira API token found (set JIRA_API_TOKEN or store it in your keychain; see the README)." ;;
        4) _sprout_err "no email found; set JIRA_EMAIL." ;;
        *) _sprout_err "could not fetch $key from Jira (check host, email, token and project access)." ;;
      esac
      print -u2 -r -- "Run '${SPROUT_COMMAND:-sprout} --help' for usage."
      return 1
    fi
  fi

  type="${type:-feat}"
  if [[ " $types " != *" $type "* ]]; then
    _sprout_err "invalid type '$type' (expected one of: $types)."
    return 1
  fi

  [[ -z "$slug" ]] && slug="$(_sprout_slugify "$title")"
  if [[ -z "$slug" ]]; then
    _sprout_err "the title produced an empty slug; use letters or digits."
    return 1
  fi

  local format='{ID}/{type}-{slug}'
  [[ -n "$SPROUT_BRANCH_FORMAT" ]] && format="$SPROUT_BRANCH_FORMAT"
  local branch="$format"
  branch="${branch//\{ID\}/$key}"
  branch="${branch//\{type\}/$type}"
  branch="${branch//\{slug\}/$slug}"

  if [[ -n "$dry" ]]; then
    print -r -- "$branch"
    return 0
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { _sprout_err "not inside a Git repository."; return 1; }

  local base remote="${remote_opt:-${SPROUT_REMOTE:-origin}}"
  base="${base_opt:-$(_sprout_default_base)}"

  # Already there? Just switch.
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    print -u2 -r -- "Branch already exists, switching to ${branch}"
    git switch "$branch"
    return $?
  fi

  # Another branch for the same ticket (AI names can vary between runs).
  local existing
  existing="$(git branch --list "*${key}*" --format='%(refname:short)' | head -n1)"
  if [[ -n "$existing" ]]; then
    print -u2 -r -- "A branch for ${key} already exists: ${existing}"
    print -u2 -r -- "New branch would be: ${branch}"
    if read -q "?[y] switch to the existing one / [N] create the new one: "; then
      print; git switch "$existing"; return $?
    fi
    print
  fi

  # Uncommitted changes: offer to carry them over with a stash.
  local stashed=0
  if [[ -n "$(git status --porcelain)" ]]; then
    read -q "?Uncommitted changes found. Stash them and restore on the new branch? [y/N] " \
      || { print; _sprout_err "cancelled."; return 1; }
    print
    git stash push -u -m "sprout: ${branch}" || return 1
    stashed=1
  fi

  git switch "$base" || return 1
  if [[ "$pull" != 0 ]]; then
    git pull "$remote" "$base" || return 1
  fi
  git switch -c "$branch" || return 1

  (( stashed )) && git stash pop
  print -u2 -r -- "Branch created: ${branch}"
}

# Tab completion for the ticket, title and type arguments.
_sprout_complete() {
  _arguments \
    '(-b --base)'{-b,--base}'[start from this branch]:branch:__git_branch_names' \
    '(-r --remote)'{-r,--remote}'[pull from this remote]:remote:__git_remotes' \
    '--no-pull[skip the pull]' \
    '--doctor[check which AI sprout uses]' \
    '(-n --dry-run)'{-n,--dry-run}'[print the branch name only]' \
    '1:Jira key or URL:' \
    '2:title:' \
    "3:type:(${SPROUT_TYPES:-feat fix chore})"
}

# Define the user-facing command (default `sprout`; override with SPROUT_COMMAND).
functions[${SPROUT_COMMAND:-sprout}]='_sprout_run "$@"'
(( $+functions[compdef] )) && compdef _sprout_complete "${SPROUT_COMMAND:-sprout}"
