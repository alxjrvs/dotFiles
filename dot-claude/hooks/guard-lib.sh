#!/usr/bin/env bash
# Shared parsing for the PreToolUse guards. Sourced, never executed. Every
# function here is pure: it reads its arguments and prints, touching no global
# state, and it lives here so the guards cannot drift apart again.
#
# Portability: bash 3.2 (`/bin/bash`). A hook cannot assume the PATH it will be
# handed — Claude Code, launchd and a mid-provision machine can each run this
# with only the system bash reachable, and a library that fails to parse means
# the guard never runs and nothing says so.
# No arrays, no `${arr[@]}` on a possibly-empty array, no `declare -g`.

# Split a command into simple commands on shell separators, RESPECTING quotes.
# Quoted text is data, never structure, and must not decide a verdict: a
# quote-blind split breaks in both directions, denying a `&&` inside a commit
# message and letting a `#`-commented `--dry-run` look like a real flag.
# A literal newline, for use as a `case` pattern below.
_NL='
'

# Remove heredoc BODIES before any parsing. A heredoc body is data the command
# writes, not command structure: `git commit -F - <<'MSG' … MSG` routinely
# contains the very commands these guards look for. It also cannot be assumed to
# be shell-quoted — ordinary prose apostrophes ("lefthook's") unbalance the quote
# tracking below and scramble segmentation downstream.
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
# `sh -c 'op read op://…'` walks straight past a program-name check. That is the
# residue `permissions.deny` structurally cannot cover; it is covered here.
# The GitHub owners this machine may WRITE to. Single consumer:
# repo-scope-guard.sh gates writes on it. It lives here rather than in prose
# because a list that governs a security boundary cannot be maintained beside a
# copy of itself — the two drift, and the executing copy is the one that is
# wrong.
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
    # one of these ships a `system()`. The unknown LANGUAGE is as open a door as
    # the unknown VERB this guard otherwise fails closed on.
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
# a space. Deleting the punctuation instead (what `_unquote` does) GLUES tokens
# together: `os.system('op read …')` collapses to `os.systemop read …`, putting
# a word character in front of `op` so the anchored pattern can no longer match.
_scan_text() { # $1 = text -> punctuation flattened to spaces
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.:/-]/ /g'
}

# Expand an interpreter's payload into extra segments, so `bash -c "git push
# origin main"` is judged by the SAME refspec logic as a bare push. Refusing
# every interpreter outright -- as op-guard must, because it cannot know what an
# `op` payload will print -- would block the legitimate `bash -c "git push
# origin feature"` for no gain. Here the payload IS a git command.
#
# One level deep on purpose: each level of recursion is a way for this to loop
# forever on a crafted input, and a guard that hangs is worse than one that
# misses.
_expand_interpreters() { # $1 = raw command, $2 = segments -> segments + payloads
  local seg out payload q raw
  # $1 must be saved before the loop below: `set -- $(_norm ...)` inside it
  # REPLACES the positional parameters, so by the time the pipe check runs `$1`
  # would be the last segment's program name rather than the raw command --
  # silently disabling the whole pipe branch.
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
      # A newline inside quotes is DATA, but this function emits one segment per
      # LINE, so a segment legitimately containing one is re-split by every
      # caller's `while read` and a commit message then arrives at a guard
      # looking like a real command. Collapsing it to a space keeps the segment
      # on one line without changing tokenization — the program name and its
      # flags are unaffected. An UNQUOTED newline still separates commands, via
      # the `case` arm below.
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
      # A newline separates simple commands exactly as `;` does; without it a
      # multi-line command collapses into ONE segment and only its first program
      # name is ever judged. `(`, `)` and a backtick separate for the same
      # reason: what follows one is a COMMAND, not an argument, so
      # `echo $(op read op://…)` must not read as a single `echo` segment.
      # Splitting routes the substitution body back through the ordinary
      # allow-list on the next iteration, which is where the verdict already
      # lives, rather than teaching this tokenizer to parse nesting.
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
# That is what separates `echo "op read op://x" | bash`, where the pipe is a
# shell operator, from `git commit -m "note: x |eval can run op read op://a"`,
# where the same characters are text inside an argument. A raw substring scan
# cannot tell them apart, and denied the second.
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

# As `_blank_quoted`, but quote state CARRIES ACROSS LINES.
#
# `_blank_quoted` resets `sq`/`dq` per record, which is right for callers asking
# a per-line question. The program-position tests ask a whole-command question:
# they anchor on `^` and grep is line-oriented, so without carrying state the
# start of EVERY line of a multi-line quoted argument reads as program position
# — a markdown code fence inside a `gh pr create --body '…'` denied as a
# substituted program name.
#
# Line structure is preserved, so a genuine multi-line command still presents a
# real line start per command; only the CONTENT inside an open quote is blanked.
_blank_quoted_ml() { # $1 = command -> quoted runs blanked, state kept across lines
  printf '%s' "$1" | awk '
    BEGIN { sq = 0; dq = 0 }
    {
      out = ""; n = length($0)
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
# environment assignments and exec wrappers, then stop at a `#` comment. Each is
# a bypass otherwise — `(git`, `then`, `do`, `env git`, `command git`,
# `FOO=bar git` and `/usr/bin/git` all sail past a bare-token comparison.
# Callers take the basename of $1 to finish the job.
#
# Tokens carry no spaces (they come from word splitting), so rejoining the
# normalized argv with spaces is lossless.
#
# Every `case` below matches the DEQUOTED token, and the program name is emitted
# dequoted: `"op" read op://…` must resolve to `op`, not to `"op"`. The prefix
# walk needs it too, or `"sudo" op read` skips the sudo arm.
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
      # runs it, so the program name after it is the real one.
      #
      # `permissions.deny` cannot cover these either, and says so: Claude Code's
      # built-in stripped-wrapper list is fixed and documents that `mise exec`,
      # `npx`, `devbox run` and `docker exec` are NOT in it. So this library is
      # the only place the shape can be closed.
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
            # begins right after it whatever preceded — tool specs included.
            # Pattern-matching each token instead (`-* | *@*`) breaks on a bare
            # tool name: `mise exec rg -- op read` resolves its program to `rg`.
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
            # argument the way a flag's argument is skipped makes the command
            # invisible rather than unreadable, so this one fails CLOSED.
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
      # grammars and one shared skip-list gets them wrong: `-w` takes an
      # argument for caffeinate and none for setsid, arch's `-d`/`-e` take one,
      # and chroot's mandatory newroot operand has to be skipped separately.
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
      # `sudo`/`doas` need their own arm rather than a place in the wrapper
      # list above because they take flags WITH arguments (`-u user`), which
      # would otherwise be read as the program name.
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
