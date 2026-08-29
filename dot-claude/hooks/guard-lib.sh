#!/usr/bin/env bash
# Shared parsing for the two PreToolUse guards. Sourced, never executed.
#
# It exists because the guards each carried their own copy of this logic and had
# already drifted three ways (quote stripping on the target, `'` handling on cd,
# break-on-match), so a fix landed in one and not the other. Every function here
# is pure: it reads its arguments and prints, touching no global state.
#
# Portability: bash 3.2 (`/bin/bash`). NOT because bash is undeclared — the
# Brewfile does declare it — but because a hook cannot assume the PATH it will
# be handed. Claude Code, launchd and a mid-provision machine can each run this
# with only the system bash reachable, and a guard that fails to parse fails
# CLOSED in the worst way: it never runs and nothing says so.
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

# Blank out everything inside a quoted run, preserving length and every
# character OUTSIDE the quotes. The result is a structure-only view of a
# command: shell operators survive, prose does not.
#
# This is what separates `echo "op read op://x" | bash` — a real payload piped
# into an interpreter, where the pipe is a shell operator — from
# `git commit -m "note: x |eval can run op read op://a/b/c"`, where the same
# characters are text inside an argument. A raw substring scan cannot tell them
# apart, and denied the second one.
_blank_quoted() { # $1 = command -> same string with quoted runs blanked
  printf '%s' "$1" | awk '
    {
      out = ""; sq = 0; dq = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (!dq && c == "\047") { sq = !sq; out = out " "; continue }
        if (!sq && c == "\"")   { dq = !dq; out = out " "; continue }
        out = out ((sq || dq) ? " " : c)
      }
      print out
    }'
}

# Strip QUOTES ONLY, keeping parens. `_unquote` deletes parens too, which would
# destroy the `'('*` arm in `_norm` (a segment can legitimately open with one).
# The program token is the one place a stray quote is fatal rather than
# cosmetic, so it gets its own narrower helper.
_dequote() { # $1 = token -> printed without quotes
  local v=$1
  v=${v//\"/}
  v=${v//\'/}
  printf '%s' "$v"
}

# Emitted by `_norm` in place of a program name it cannot resolve statically —
# `$OP read`, `$(echo op) read`, a backticked name. A guard that sees this must
# DENY: a program name the guard cannot read is the same "unknown, therefore
# closed" case op-guard already applies to an unrecognized op subcommand.
# Deliberately un-spellable as a real program, so it can never collide with one.
_UNRESOLVED='%%unresolved%%'

# Does this argv carry a bare `--` separator? Used by the runner arms: when a
# runner is given one, the command begins after it and nothing before it needs to
# be understood — which is what makes a bare tool name (`mise exec rg -- …`) safe
# to skip past instead of guessing at.
_has_ddash() {
  while [ $# -gt 0 ]; do
    [ "$(_dequote "$1")" = "--" ] && return 0
    shift
  done
  return 1
}

# Normalize one segment to its real argv: drop shell-construct keywords, leading
# environment assignments and exec wrappers, then stop at a `#` comment. Each was
# a live bypass — the guards compared against the bare token `git`, so `(git`,
# `then`, `do`, `env git`, `command git`, `FOO=bar git` and `/usr/bin/git` all
# sailed past. Callers take the basename of $1 to finish the job.
#
# Tokens carry no spaces (they come from word splitting), so rejoining the
# normalized argv with spaces is lossless.
# Every `case` below matches the DEQUOTED token, and the program name is
# emitted dequoted. Before that, `_norm` compared and emitted the program token
# raw, so one pair of quotation marks walked past every guard sourcing this
# library: `"op" read op://…` resolved its program name to `"op"`, which is not
# `op`, so op-guard waved a live credential onto stdout. `"git" push origin
# main` and `"gh" issue create` were the same hole in the other guards. The
# prefix walk needs it too, or `"sudo" op read` skips the sudo arm.
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
      # Development-environment runners. Each takes a command as arguments and
      # runs it, so the program name after it is the real one — and each was a
      # measured bypass of BOTH layers on 2026-08-28: `mise exec -- op read
      # op://…`, `npx -y -- op read …`, `caffeinate op read …`, `arch -arm64 op
      # read …` and `direnv exec . op read …` all reached a live credential.
      #
      # `permissions.deny` cannot cover these either, and says so: Claude Code's
      # built-in stripped-wrapper list is fixed and documents that `mise exec`,
      # `npx`, `devbox run` and `docker exec` are NOT in it. So this library is
      # the only place the shape can be closed.
      #
      # Each arm is narrow on purpose: only the SUBCOMMAND that runs an
      # arbitrary command is stripped. `mise install` and `pnpm add` are
      # ordinary commands and must stay ordinary, or the guard starts denying
      # the tool it is supposed to be invisible to.
      #
      # This list is open, not complete. A runner not named here is a bypass —
      # add it with a case in `tests/cases.tsv` first.
      # Subcommand runners: `<prog> <sub> [args] [--] CMD`. Only the subcommand
      # that runs an ARBITRARY command enters here — `mise install` and `pnpm add`
      # stay ordinary commands, or the guard starts denying the tooling it is
      # supposed to be invisible to.
      mise | devbox | pnpm | yarn | direnv | npm | docker)
        case "$tok:$(_dequote "${2:-}")" in
          mise:exec | mise:x | devbox:run | pnpm:exec | pnpm:dlx | yarn:dlx | \
            direnv:exec | npm:exec | npm:x | docker:exec) ;;
          *) break ;;
        esac
        shift 2
        case "$tok" in
          # `direnv exec DIR CMD` and `docker exec CONTAINER CMD` each take one
          # mandatory operand between the flags and the command.
          direnv | docker)
            while [ $# -gt 0 ]; do
              case "$(_dequote "$1")" in
                -*) shift ;;
                *) break ;;
              esac
            done
            [ $# -gt 0 ] && shift
            ;;
          *)
            # `--` is the unambiguous separator, so when it is present the command
            # begins right after it whatever preceded — tool specs included. The
            # earlier version pattern-matched each token instead (`-* | *@*`), which
            # broke on a bare tool name: `mise exec rg -- op read` resolved its
            # program to `rg` and waved the `op read` through. Scanning for the
            # separator cannot have that failure.
            if _has_ddash "$@"; then
              while [ $# -gt 0 ]; do
                if [ "$(_dequote "$1")" = "--" ]; then
                  shift
                  break
                fi
                shift
              done
            else
              while [ $# -gt 0 ]; do
                case "$(_dequote "$1")" in
                  -*) shift ;;
                  *) break ;;
                esac
              done
            fi
            ;;
        esac
        ;;
      npx | bunx)
        shift
        while [ $# -gt 0 ]; do
          case "$(_dequote "$1")" in
            --)
              shift
              break
              ;;
            # `-c`/`--call` takes a COMMAND STRING, not a program name. Skipping its
            # argument the way a flag's argument is skipped made the command
            # invisible rather than unreadable — `npx -c 'op read op://…'` resolved
            # to whatever followed and was allowed. An opaque payload is exactly the
            # case the refusal sentinel exists for, so this one fails CLOSED.
            -c | --call)
              set -- "$_UNRESOLVED"
              break 2
              ;;
            -p | --package)
              shift
              [ $# -gt 0 ] && shift
              ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      # One arm per tool below, because these four have incompatible flag
      # grammars and sharing one skip-list got three of them wrong: `-w` takes an
      # argument for caffeinate and none for setsid, so `setsid -w op read` ate
      # `op` as the argument; arch's `-d`/`-e` were absent entirely; and chroot's
      # mandatory newroot operand was never skipped, so the arm could not reach a
      # command on any platform.
      caffeinate)
        shift
        while [ $# -gt 0 ]; do
          case "$(_dequote "$1")" in
            # -t <seconds> and -w <pid> take an argument; -d -i -m -s -u do not.
            -t | -w)
              shift
              [ $# -gt 0 ] && shift
              ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      arch)
        shift
        while [ $# -gt 0 ]; do
          case "$(_dequote "$1")" in
            # macOS arch(1): -arch <name>, -d <envname>, -e <env=value> each take
            # an argument. The bare selectors (-32/-64/-x86_64/-arm64) do not.
            -arch | -d | -e)
              shift
              [ $# -gt 0 ] && shift
              ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      setsid)
        # -c, -f/--fork, -w/--wait all take NO argument.
        shift
        while [ $# -gt 0 ]; do
          case "$(_dequote "$1")" in
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      chroot)
        # BSD/macOS chroot: -G <group>, -g <group>, -u <user>, -U <user> take an
        # argument. GNU spells these --userspec=… / --groups=… , attached, so they
        # need no skip. Then the mandatory newroot operand precedes the command.
        shift
        while [ $# -gt 0 ]; do
          case "$(_dequote "$1")" in
            -G | -g | -u | -U)
              shift
              [ $# -gt 0 ] && shift
              ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] && shift
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
  # The program token, dequoted — or the refusal sentinel when it is a shell
  # expansion this guard cannot statically read. Arguments are emitted as-is:
  # a quoted `-m "note about op read"` must stay one opaque blob, or stripping
  # its quotes would hand the scanners the very prose false positive the suite
  # exists to prevent.
  if [ $# -gt 0 ]; then
    tok=$(_dequote "$1")
    case "$tok" in
      *'$'* | *'`'*) printf '%s ' "$_UNRESOLVED" ;;
      *) printf '%s ' "$tok" ;;
    esac
    shift
  fi
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
