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

# An interpreter takes an opaque payload this guard cannot tokenize, so
# `sh -c 'op read op://…'` walks straight past a program-name check. CLAUDE.md
# names this exact case as the residue `permissions.deny` structurally cannot
# cover ("deny cannot cover an arbitrary interpreter"). It is covered here.
# The GitHub owners this machine may WRITE to. Single source: repo-scope-guard.sh
# gates writes on it, and pr-review.sh defaults its review scope from it.
#
# It was two lists until now, and they had already drifted: CLAUDE.md named six
# owners, pr-review.sh named five — `Criterium-Engineers` was missing from the
# one that executes. That is the whole argument for putting it here; a list that
# governs a security boundary cannot be maintained in prose beside a copy.
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

_is_interpreter() { # $1 = basename
  case "$1" in
    sh | bash | zsh | dash | ksh | fish | eval | xargs | watch | script) return 0 ;;
    # The scripting runtimes belong here for exactly the reason the shells do:
    # `-c`/`-e` takes an opaque payload this guard cannot tokenize, and every
    # one of these ships a `system()`. Omitting them left `python3 -c
    # "os.system('op read …')"` as an open door through a guard that otherwise
    # fails closed on an unknown VERB — the door was the unknown LANGUAGE.
    python | python2 | python3 | ruby | perl | node | bun | deno | php | lua | awk) return 0 ;;
    # Not interpreters in the language sense, but they take a command as
    # arguments and run it: `find -exec op read …` and `ssh host "op read …"`
    # both reach a real `op` this guard would otherwise never see. The payload
    # scan is anchored on a real op SUBCOMMAND, so `find . -name '*.op'` and
    # `ssh host uptime` do not trip it.
    find | ssh) return 0 ;;
    *) return 1 ;;
  esac
}

# Flatten everything that is not a word character or part of an `op://` path to
# a space. `_unquote` DELETES its punctuation, which silently glued tokens
# together: `os.system('op read …')` collapsed to `os.systemop read …`, putting
# a word character in front of `op` so the pattern above could not match. Every
# `python3 -c` payload was invisible for that one reason, and the suite could
# not see it because no case exercised a payload with punctuation before `op`.
_scan_text() { # $1 = text -> punctuation flattened to spaces
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.:/-]/ /g'
}

# Expand an interpreter's payload into extra segments, so `bash -c "git push
# origin main"` is judged by the SAME refspec logic as a bare push. The
# alternative -- refusing every interpreter outright, as op-guard must, because
# it cannot know what an `op` payload will print -- would block the legitimate
# `bash -c "git push origin feature"` for no gain. Here the payload IS a git
# command, so it can simply be read as one.
#
# One level deep on purpose. `bash -c "bash -c ..."` is not a spelling anyone
# reaches for, and each level of recursion is a way for this to loop forever on
# a crafted input; a guard that hangs is worse than one that misses.
_expand_interpreters() { # $1 = raw command, $2 = segments -> segments + payloads
  local seg out payload q raw
  # $1 must be saved before the loop below: `set -- $(_norm ...)` inside it
  # REPLACES the positional parameters, so by the time the pipe check runs `$1`
  # is the last segment's program name rather than the raw command. That silently
  # disabled the whole pipe branch -- grep found nothing in an empty string.
  raw=$1
  out=$2
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    set -f
    # shellcheck disable=SC2046 # intentional word-split: _norm emits tokens
    set -- $(_norm "$seg")
    set +f
    [ $# -gt 0 ] || continue
    _is_interpreter "${1##*/}" || continue
    shift
    # Drop the interpreter's own flags (`-c`, `-e`) so the payload starts at the
    # command. Without this the payload's program name reads as `-c`.
    while [ $# -gt 0 ]; do
      case "$1" in
        -*) shift ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || continue
    payload=$(_unquote "$*")
    [ -n "$payload" ] || continue
    out=$out$_NL$(_split "$payload")
  done << EOF
$2
EOF

  # A payload piped INTO an interpreter sits in the PRODUCING segment, whose
  # program name is `echo` -- neither segment names the real command. Pull the
  # quoted runs out of the whole command and read each as a candidate.
  #
  # Gated on an actual pipe-into-interpreter, which is what keeps this away from
  # `git commit -m "explain git push origin main"`: that has no pipe, so no
  # quoted run is ever expanded and the prose stays prose.
  if printf '%s' "$raw" |
    grep -qE '\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?([A-Za-z0-9_./-]*/)?(sh|bash|zsh|dash|ksh|fish|eval|python[23]?|ruby|perl|node|bun|deno)([[:space:]]|$)'; then
    while IFS= read -r q; do
      [ -n "$q" ] || continue
      out=$out$_NL$(_split "$(_unquote "$q")")
    done << EOF
$(printf '%s' "$raw" | grep -oE "\"[^\"]*\"|'[^']*'" || true)
EOF
  fi
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
      # A newline inside quotes is DATA, and the quote tracking here always knew
      # that. The bug was downstream: this function emits one segment per LINE, so
      # a segment legitimately containing a newline was re-split by every caller's
      # `while read`. A commit message with a line starting `op read …` or
      # `git push origin main` then arrived at a guard looking like a real command,
      # which is how writing about these guards became impossible to commit.
      #
      # Collapsing it to a space keeps the segment on one line without changing
      # tokenization — the program name and its flags are unaffected, and prose is
      # only ever inspected as prose. An UNQUOTED newline still separates commands,
      # which the `echo hi\nop read` and `git status\ngit push` cases assert.
      if [ "$c" = "$_NL" ]; then
        cur=$cur' '
      else
        cur=$cur$c
      fi
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
      # `(`, `)` and a backtick separate simple commands for the same reason
      # `;` does: what follows one is a COMMAND, not an argument. Before this,
      # `echo $(op read op://…)` was a single segment whose program name was
      # `echo`, so the guard inspected the wrapper and never the payload — and
      # `permissions.deny` could not help, its rules being anchored on `op read`
      # as the first token. Splitting here routes the substitution body back
      # through the ordinary allow-list on the next iteration, which is where
      # the verdict already lives; the alternative was teaching this tokenizer
      # to parse nesting, which is strictly more code and more ways to be wrong.
      #
      # Only UNQUOTED delimiters split — the quote branch above returns first —
      # so a paren inside a commit message is still prose. An unquoted `(` in
      # shell is always a construct: subshell, `$(`, or `<(`. Splitting on the
      # bare paren covers all three spellings without matching `$` or `<`.
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
      # `sudo` was the one privilege wrapper missing from the list above, so
      # `sudo op read …` resolved its program name to `sudo` and every guard
      # sourcing this library waved it through. It needs its own arm rather than
      # a place in that list because it takes flags WITH arguments (`-u user`),
      # which would otherwise become the program name.
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
