#!/usr/bin/env zsh
# Test suite for sprout. Offline: no Jira, no AI, no network. Run: zsh tests/run.zsh

ROOT="${0:A:h:h}"
export SPROUT_CONFIG=/dev/null SPROUT_AI=0 SPROUT_DRY_RUN=1
unset JIRA_API_TOKEN SPROUT_JIRA_HOST SPROUT_BASE SPROUT_BRANCH_FORMAT SPROUT_TYPES SPROUT_PULL SPROUT_LANG
source "$ROOT/sprout.plugin.zsh"

typeset -i passed=0 failed=0

# Asserts that two strings are equal and records the result.
check() {
  if [[ "$2" == "$3" ]]; then
    passed+=1; print "  ok    $1"
  else
    failed+=1; print "  FAIL  $1\n          expected: $2\n          actual:   $3"
  fi
}

print "slug and key extraction (dry run)"
check "plain key"            "PROJ-142/feat-add-login-page"          "$(sprout PROJ-142 'Add login page' 2>&1)"
check "accents and symbols"  "PROJ-1/fix-crear-cuenta-nandu"        "$(sprout PROJ-1 'Crear Cuenta (ñandú)' fix 2>&1)"
check "browse URL"           "PROJ-7/feat-hello-world"               "$(sprout https://acme.atlassian.net/browse/proj-7 'Hello, World!' 2>&1)"
check "host with digits"     "APP-9/chore-tidy-up"                   "$(sprout https://my-org-2.atlassian.net/browse/APP-9 'Tidy up' chore 2>&1)"
check "board URL"            "PROJ-33/feat-board-link"               "$(sprout 'https://acme.atlassian.net/jira/software/projects/PROJ/boards/1?selectedIssue=PROJ-33' 'Board link' 2>&1)"
check "lowercase key"        "ABC-5/feat-lower"                      "$(sprout abc-5 'lower' 2>&1)"

long="$(sprout PROJ-2 'A very long ticket title that goes well beyond the fifty character limit for slugs' 2>&1)"
check "slug capped at 50"    "1" "$(( ${#${long#PROJ-2/feat-}} <= 50 ))"
check "no trailing hyphen"   "0" "$([[ "$long" == *- ]] && print 1 || print 0)"

print "branch format and types"
check "custom format"        "feat/PROJ-3_cool-thing" "$(SPROUT_BRANCH_FORMAT='{type}/{ID}_{slug}' sprout PROJ-3 'Cool thing' 2>&1)"
check "custom type allowed"  "PROJ-4/docs-write-guide" "$(SPROUT_TYPES='feat fix docs' sprout PROJ-4 'Write guide' docs 2>&1)"

print "failures"
sprout PROJ-5 'x' wrong >/dev/null 2>&1;     check "invalid type fails"    "1" "$?"
sprout 'no key here' 'x' >/dev/null 2>&1;    check "missing key fails"     "1" "$?"
sprout PROJ-6 '!!!' >/dev/null 2>&1;         check "empty slug fails"      "1" "$?"
sprout PROJ-6 >/dev/null 2>&1;               check "no Jira config fails"  "1" "$?"

print "heuristic naming without AI"
check "stop-words dropped"   "build-login-page-okta" "$(_sprout_shorten 'Build the login page for Okta users' '')"

print "AI language rule"
check "default is English"    "1" "$([[ "$(_sprout_language_rule)" == *English* ]] && print 1 || print 0)"
check "es is Spanish"         "1" "$([[ "$(SPROUT_LANG=es _sprout_language_rule)" == *Spanish* ]] && print 1 || print 0)"
check "ticket keeps language" "1" "$([[ "$(SPROUT_LANG=ticket _sprout_language_rule)" == *"same language"* ]] && print 1 || print 0)"
check "custom language name"  "1" "$([[ "$(SPROUT_LANG=Klingon _sprout_language_rule)" == *Klingon* ]] && print 1 || print 0)"

print "real Git flow (temporary repositories)"
tmp="$(mktemp -d)"
(
  cd "$tmp" || exit 1
  git init -q --bare -b main origin.git
  git init -q -b main work && cd work
  git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git remote add origin "$tmp/origin.git"
  git push -q -u origin main
  git remote set-head origin main >/dev/null

  unset SPROUT_DRY_RUN
  sprout PROJ-10 'Fix crash on start' >/dev/null 2>&1
  print -r -- "created=$(git branch --show-current)"

  git switch -q main
  sprout PROJ-10 'Fix crash on start' >/dev/null 2>&1
  print -r -- "again=$(git branch --show-current)"

  git switch -q main
  print -r -- "base=$(_sprout_default_base)"

  git switch -q -c develop
  git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m dev
  git push -q -u origin develop
  git switch -q main
  sprout PROJ-11 'Add search' --base develop >/dev/null 2>&1
  print -r -- "onbase=$(git branch --show-current)"
  print -r -- "tip=$(git rev-parse HEAD)"
  print -r -- "develop=$(git rev-parse develop~0)"

  git switch -q main
  sprout --base=develop PROJ-12 'Add filters' >/dev/null 2>&1
  print -r -- "equals=$(git branch --show-current)"

  git switch -q main
  git remote set-url origin "$tmp/missing.git"
  sprout PROJ-13 'Offline work' --no-pull >/dev/null 2>&1
  print -r -- "nopull=$(git branch --show-current)"

  git switch -q main
  sprout PROJ-14 'Needs value' --base >/dev/null 2>&1
  print -r -- "novalue=$?"
) > "$tmp/out.txt" 2>&1
check "creates the branch"           "created=PROJ-10/feat-fix-crash-on-start" "$(grep '^created=' "$tmp/out.txt")"
check "switches if it already exists" "again=PROJ-10/feat-fix-crash-on-start"  "$(grep '^again=' "$tmp/out.txt")"
check "detects the default base"     "base=main"                               "$(grep '^base=' "$tmp/out.txt")"
check "--base starts from that branch"  "onbase=PROJ-11/feat-add-search"   "$(grep '^onbase=' "$tmp/out.txt")"
check "--base uses the branch tip"      "$(grep '^develop=' "$tmp/out.txt" | sed 's/develop=/tip=/')" "$(grep '^tip=' "$tmp/out.txt")"
check "--base=<branch> form works"      "equals=PROJ-12/feat-add-filters"  "$(grep '^equals=' "$tmp/out.txt")"
check "--no-pull skips the pull"        "nopull=PROJ-13/feat-offline-work" "$(grep '^nopull=' "$tmp/out.txt")"
check "--base without a value fails"    "novalue=1"                        "$(grep '^novalue=' "$tmp/out.txt")"
check "dry run accepts --base"          "PROJ-15/feat-add-x"               "$(sprout PROJ-15 'Add x' --base develop --no-pull)"
rm -rf "$tmp"

print "\n$passed passed, $failed failed"
(( failed == 0 ))
