#!/usr/bin/env bash
# Shared parsing for the two PreToolUse guards. Sourced, never executed.
#
# It exists because the guards each carried their own copy of this logic and had
# already drifted three ways (quote stripping on the target, `'` handling on cd,
# break-on-match), so a fix landed in one and not the other. Every function here
# is pure: it reads its arguments and prints, touching no global state.
#
# Portability: bash 3.2 (`/bin/bash`). `bash` is not in the Brewfile, so the
# homebrew bash 5 that happens to be first on PATH is not guaranteed anywhere.
# No arrays, no `${arr[@]}` on a possibly-empty array, no `declare -g`.

# Split a command into simple commands on shell separators, RESPECTING quotes.
# A quote-blind split (the previous `sed -E 's/(\|\||&&|[;&|])/\n/g'`) breaks in
# both directions: it splits at a `&&` inside a commit message and denies real
# work, and it lets a `#`-commented `--dry-run` look like a real flag. Quoted
# text is data, never structure, and must not decide a verdict.
# A literal newline, for use as a `case` pattern below. bash 3.2 accepts `$'\n'`
# inline, but naming it keeps the pattern list readable.
_NL='
'

# Remove heredoc BODIES before any parsing. A heredoc body is data the command
# writes, not command structure: `git commit -F - <<'MSG' … MSG` routinely
# contains the very commands these guards look for. It also cannot be assumed to
# be shell-quoted — ordinary prose apostrophes ("lefthook's") unbalance the quote
# tracking below and scramble segmentation downstream.
#
# This is not hypothetical: writing the commit message for the very change that
# added these guards' new cases was DENIED by the guard, because the message
# explained `git push origin main && cd ..`.
#
# `<<<` (herestring) has no body and is deliberately not matched.
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

_split() { # $1 = command -> one simple command per line
  local s c q='' cur='' n i
  s=$(_strip_heredocs "$1")
  n=${#s}
  i=0
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    if [ -n "$q" ]; then
      cur=$cur$c
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
        # A backslash escapes the next character, which therefore cannot be a
        # separator or a quote — copy both through untouched.
        cur=$cur$c
        i=$((i + 1))
        [ "$i" -lt "$n" ] && cur=$cur${s:i:1}
        ;;
      # A newline separates simple commands exactly as `;` does. Without it a
      # multi-line command collapsed into ONE segment, so `git status` on line 1
      # made the segment's subcommand `status` and a `git push origin main` on
      # line 2 was never seen.
      ';' | '&' | '|' | "$_NL")
        printf '%s\n' "$cur"
        cur=''
        ;;
      *) cur=$cur$c ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "$cur"
}

# Strip quoting and grouping punctuation so a ref compares by NAME:
# `'main'`, `"main"` and `(git push origin main)` all name `main`.
_unquote() { # $1 = token -> printed without quotes/parens
  local v=$1
  v=${v//\"/}
  v=${v//\'/}
  v=${v//\(/}
  v=${v//\)/}
  printf '%s' "$v"
}

# Normalize one segment to its real argv: drop shell-construct keywords, leading
# environment assignments and exec wrappers, then stop at a `#` comment. Each was
# a live bypass — the guards compared against the bare token `git`, so `(git`,
# `then`, `do`, `env git`, `command git`, `FOO=bar git` and `/usr/bin/git` all
# sailed past. Callers take the basename of $1 to finish the job.
#
# Tokens carry no spaces (they come from word splitting), so rejoining the
# normalized argv with spaces is lossless.
_norm() { # $1 = segment -> prints normalized argv, space-separated
  local first
  set -f
  # shellcheck disable=SC2086 # intentional word-split of one shell segment
  set -- $1
  set +f
  while [ $# -gt 0 ]; do
    case "$1" in
      '(' | ')' | '{' | '}' | '!' | if | then | else | elif | fi | while | until | for | do | done | in)
        shift
        ;;
      '('*)
        first=${1#\(}
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
      [A-Za-z_]*=*) shift ;;
      *) break ;;
    esac
  done
  while [ $# -gt 0 ]; do
    case "$1" in '#'*) break ;; esac
    printf '%s ' "$1"
    shift
  done
}

# Skip git's global options (and the argument of those that take one) to reach
# the subcommand. Callers use it as: set -- $(_skip_global "$@").
_skip_global() { # $@ = argv after the program name -> prints argv at subcommand
  while [ $# -gt 0 ]; do
    case "$1" in
      -c | -C | --git-dir | --work-tree | --namespace | --exec-path)
        shift
        [ $# -gt 0 ] && shift
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  printf '%s ' "$@"
}
