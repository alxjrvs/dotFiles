#!/usr/bin/env bash
# Shared parsing for repo-scope-guard.sh. Sourced, never executed. Every function is pure: it
# reads its arguments and prints.
#
# Portability: bash 3.2 (`/bin/bash`), because a hook cannot assume its PATH and a library that
# fails to parse means the guard never runs and nothing says so. No arrays, no `declare -g`.

# The GitHub owners this machine may WRITE to. Single consumer: repo-scope-guard.sh. One copy,
# because a list that governs a boundary drifts the moment there are two.
_owned_orgs() {
  cat << 'ORGS'
alxjrvs
TheGnarCo
BinfiniteLLC
SalvageUnion-io
RANDSUM
Criterium-Engineers
ORGS
}

_NL='
'

# Remove heredoc BODIES before parsing: a body is data the command writes, not structure, and
# `git commit -F - <<'MSG' … MSG` routinely contains the words a guard looks for. `<<<` has no
# body and is not matched.
_strip_heredocs() { # $1 = command -> command with heredoc bodies removed
  local line delim='' d out='' trimmed
  while IFS= read -r line; do
    if [ -n "$delim" ]; then
      trimmed=${line#"${line%%[![:space:]]*}"}
      [ "$trimmed" = "$delim" ] && delim=''
      continue
    fi
    out=$out$line'
'
    case "$line" in
      *'<<'*)
        d=$(printf '%s' "$line" |
          sed -n "s/.*<<-\{0,1\}[[:space:]]*['\"]\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)['\"]\{0,1\}.*/\1/p")
        [ -n "$d" ] && delim=$d
        ;;
    esac
  done << EOF
$1
EOF
  printf '%s' "$out"
}

# Split a command into simple commands on unquoted separators. Quoted text is data and must not
# decide a verdict: a `&&` inside a commit message is prose. A newline inside quotes collapses
# to a space so a segment stays on one line; an unquoted newline separates commands, as do
# `;`, `&`, `|`, parens and backticks (what follows one is a COMMAND, not an argument).
_split() { # $1 = command -> one simple command per line
  local s c q='' cur='' n i
  s=$(_strip_heredocs "$1")
  n=${#s}
  i=0
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$_NL" ]; then cur=$cur' '; else cur=$cur$c; fi
      [ "$c" = "$q" ] && q=''
      i=$((i + 1))
      continue
    fi
    case $c in
      "'" | '"')
        q=$c
        cur=$cur$c
        ;;
      \\)
        cur=$cur$c
        i=$((i + 1))
        [ "$i" -lt "$n" ] && cur=$cur${s:i:1}
        ;;
      ';' | '&' | '|' | '(' | ')' | '`' | "$_NL")
        printf '%s\n' "$cur"
        cur=''
        ;;
      *) cur=$cur$c ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "$cur"
}

# Strip quotes and grouping parens so an argument compares by NAME.
_unquote() { # $1 = token -> printed without quotes/parens
  local v=$1
  v=${v//\"/}
  v=${v//\'/}
  v=${v//\(/}
  v=${v//\)/}
  printf '%s' "$v"
}

# Strip quotes only.
_dequote() { # $1 = token -> printed without quotes
  local v=$1
  v=${v//\"/}
  v=${v//\'/}
  printf '%s' "$v"
}

# Normalize one segment to its real argv: drop shell keywords, leading assignments and the
# common exec wrappers, then stop at a `#` comment. Each is a bypass otherwise: `(gh`, `then`,
# `env gh`, `command gh`, `FOO=bar gh` and `/usr/bin/gh` all sail past a bare comparison.
# Callers take the basename of $1. Arguments are emitted as-is, quotes kept, so a quoted
# `--body "…"` stays one opaque blob.
_norm() { # $1 = segment -> prints normalized argv, space-separated
  local first tok
  set -f
  # shellcheck disable=SC2086 # intentional word-split of one shell segment
  set -- $1
  set +f
  while [ $# -gt 0 ]; do
    tok=$(_dequote "$1")
    case "$tok" in
      '(' | ')' | '{' | '}' | '!' | if | then | else | elif | fi | while | until | for | do | done | in)
        shift
        ;;
      '('*)
        first=${tok#\(}
        shift
        set -- "$first" "$@"
        ;;
      timeout)
        shift
        [ $# -gt 0 ] && shift
        ;;
      command | builtin | env | exec | nohup | nice | stdbuf | noglob | time)
        shift
        ;;
      # `op run [--env-file=F] -- CMD` runs CMD, so CMD is the program to judge. Without this
      # arm `op run -- gh issue create` resolves to the program `op` and the gh write is never
      # scoped. `op-sa` is denied outright in settings.json, but it costs nothing to read here.
      op | op-sa)
        [ "$(_dequote "${2:-}")" = run ] || break
        shift 2
        while [ $# -gt 0 ]; do
          if [ "$(_dequote "$1")" = "--" ]; then
            shift
            break
          fi
          case "$(_dequote "$1")" in
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      # sudo/doas take flags WITH arguments (`-u user`) that would otherwise read as the program.
      sudo | doas)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u | -g | -p | -C | -U | -T | -r | -t)
              shift
              [ $# -gt 0 ] && shift
              ;;
            --)
              shift
              break
              ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      [A-Za-z_]*=*) shift ;;
      *) break ;;
    esac
  done
  if [ $# -gt 0 ]; then
    printf '%s ' "$(_dequote "$1")"
    shift
  fi
  while [ $# -gt 0 ]; do
    case "$1" in '#'*) break ;; esac
    printf '%s ' "$1"
    shift
  done
}
