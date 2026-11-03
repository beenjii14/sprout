# sprout - create Git branches straight from Jira tickets.
# https://github.com/beenjii14/sprout
#
# Source this file from your ~/.zshrc (the installer does it for you):
#
#   source ~/.local/share/sprout/sprout.plugin.zsh
#
# Usage:  sprout [-n|--dry-run] [<KEY|URL>] ["<title>"] [<type>]
# Docs:   sprout --help  |  README.md

typeset -g SPROUT_VERSION="0.2.0"

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

# Condenses a ticket into 2-5 slug words: asks the Claude CLI when available,
# otherwise drops stop-words and keeps the first four meaningful words (the
# local fallback cannot translate: it keeps the ticket's own words).
_sprout_shorten() {
  emulate -L zsh
  local title="$1" desc="$2" out=""

  if [[ "${SPROUT_AI:-1}" != 0 ]] && (( $+commands[claude] )); then
    out="$(printf 'Ticket title: %s\nDescription / acceptance criteria: %s\n' "$title" "$desc" \
      | perl -e 'alarm 25; exec @ARGV' claude -p --model "${SPROUT_AI_MODEL:-haiku}" \
          "Create a short git branch name for this Jira ticket. Rules: 2 to 5 lowercase words joined by hyphens, ASCII only (no accents), no prefix (no change type, no ticket key). Short but descriptive. Base it on the TITLE; use the description only to disambiguate and to pick the most representative words. Keep proper nouns and technologies; drop generic verbs (set up, create, implement). Do not invent concepts that are not in the ticket. $(_sprout_language_rule) Reply with ONLY the name." \
          2>/dev/null | tail -n1)"
    # Accept only a well-formed answer, otherwise fall back to the heuristic.
    [[ "$out" =~ '^[a-z0-9]+(-[a-z0-9]+){0,5}$' && ${#out} -ge 3 && ${#out} -le 40 ]] || out=""
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
  -n, --dry-run   Print the branch name only; do not touch Git.
  -h, --help      Show this help.
  -v, --version   Show the version.

Examples:
  sprout PROJ-123                      # title and type come from Jira
  sprout PROJ-123 "Add login page"     # no Jira lookup needed
  sprout https://acme.atlassian.net/browse/PROJ-123 "Hotfix" fix
EOF
}

# Entry point behind the user-facing command: resolves key, title and type,
# builds the branch name and creates (or switches to) the branch.
_sprout_run() {
  emulate -L zsh
  local -a args
  local dry="${SPROUT_DRY_RUN:-}"

  while (( $# )); do
    case "$1" in
      -h|--help)    _sprout_usage; return 0 ;;
      -v|--version) print "sprout $SPROUT_VERSION"; return 0 ;;
      -n|--dry-run) dry=1 ;;
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

  local base remote="${SPROUT_REMOTE:-origin}"
  base="$(_sprout_default_base)"

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
  if [[ "${SPROUT_PULL:-1}" != 0 ]]; then
    git pull "$remote" "$base" || return 1
  fi
  git switch -c "$branch" || return 1

  (( stashed )) && git stash pop
  print -u2 -r -- "Branch created: ${branch}"
}

# Tab completion for the ticket, title and type arguments.
_sprout_complete() {
  _arguments \
    '1:Jira key or URL:' \
    '2:title:' \
    "3:type:(${SPROUT_TYPES:-feat fix chore})"
}

# Define the user-facing command (default `sprout`; override with SPROUT_COMMAND).
functions[${SPROUT_COMMAND:-sprout}]='_sprout_run "$@"'
(( $+functions[compdef] )) && compdef _sprout_complete "${SPROUT_COMMAND:-sprout}"
