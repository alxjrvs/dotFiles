#!/usr/bin/env bash
# Claude Code PreToolUse guard — makes the 1Password CLI USABLE by agents while
# keeping resolved secrets out of model context.
#
# Until 2026-08-18 the control here was `permissions.deny` → `Bash(op:*)`, scoped
# to the binary. That was the right call *for a deny-list*: the 2026-07-25
# postmortem showed verb enumeration fails open — the list blocked `op-agent
# secret`, `op read` and `op item get` but not `op-agent header`, the one command
# with a confirmed leak. Binary scope covers every verb including unwritten ones.
#
# The cost was total: `op --version` was denied. So was `op run -- npm publish`,
# which is 1Password's own recommended shape and prints no secret at all —
# CLAUDE.md's advice was "run it from your own terminal". A control that blocks
# the vendor's recommended pattern isn't a floor, it's an outage.
#
# This inverts the list. It is an ALLOW-list of shapes that provably do not put a
# secret VALUE on stdout, and it denies everything else `op`-shaped. That flips
# the failure mode: under a deny-list a forgotten verb sails through, under an
# allow-list a forgotten verb is blocked. `op read`, `op document get`, a verb
# 1Password ships next year, and a typo all fail the same closed way.
#
# WHAT IT NEVER DOES: emit `permissionDecision: "allow"`. A hook `allow` bypasses
# the permission system entirely, which would put this script *above*
# `permissions.deny`. It only ever denies or stays silent, so it can subtract
# permission and never add it — `permissions.deny` remains the floor underneath,
# and the two compose instead of racing.
#
# Wired agent-side via dot-claude/settings.json `hooks.PreToolUse` (matcher
# "Bash"), alongside worktree-checkout-guard.sh and rebase-guard.sh.
#
# It FAILS OPEN (allow) on a missing jq, a bad envelope, or a missing guard-lib —
# same as its two siblings, and defensible for the same reason they are: the
# residual `permissions.deny` entries (`op read`, `op item get`, `op document
# get`, and the whole `op-agent` binary) still cover the paths with confirmed
# incidents. Fail-open here degrades to roughly the pre-2026-08-18 floor minus
# binary scope on `op`; it does not degrade to nothing.
set -u

allow() { exit 0; }

deny() { # $1 = reason
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || allow
[ -n "$cmd" ] || allow

# Cheap bail-out: if no `op` token appears anywhere, this guard has no opinion.
# Word-boundary, so `open`, `loop`, `--option` and `chmod` do not wake it up.
printf '%s' "$cmd" | grep -qE '(^|[^A-Za-z0-9_.-])op(-agent)?([^A-Za-z0-9_-]|$)' || allow

# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

SAFE_SHAPES='Non-printing shapes an agent may use:
  op run [--env-file=F] -- CMD    inject secrets as env into CMD (values masked in its output)
  op inject -i TPL -o OUT         render a template TO A FILE
  op whoami / op --version        identity and version, no values
Everything else is denied because it can put a secret VALUE on stdout, and stdout
is model context. To USE a secret, never read it — pass it with "op run --".'

# 1Password global flags that consume the following argument. Without this,
# `op --account foo read op://x` would resolve its subcommand to `foo`.
_skip_op_global() { # $@ = argv after `op` -> prints argv at the subcommand
  while [ $# -gt 0 ]; do
    case "$1" in
      --account | --config | --session | --format | --encoding)
        shift
        [ $# -gt 0 ] && shift
        ;;
      --version | -v | --help | -h) break ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  printf '%s ' "$@"
}

# An interpreter takes an opaque payload this guard cannot tokenize, so
# `sh -c 'op read op://…'` walks straight past a program-name check. CLAUDE.md
# names this exact case as the residue `permissions.deny` structurally cannot
# cover ("deny cannot cover an arbitrary interpreter"). It is covered here.
_is_interpreter() { # $1 = basename
  case "$1" in
    sh | bash | zsh | dash | ksh | fish | eval | xargs | watch | script) return 0 ;;
    *) return 1 ;;
  esac
}

# A command whose whole job is to print the environment defeats `op run`'s
# masking argument, and an interpreter after `--` can do anything at all.
_bad_op_run_child() { # $1 = basename of the command after `--`
  case "$1" in
    env | printenv | set | export | declare | typeset | printf | echo) return 0 ;;
    sh | bash | zsh | dash | ksh | fish | eval | xargs) return 0 ;;
    # `op run -- git push` would hide the push from rebase-guard.sh, which
    # tokenizes for a `git`/`gh` PROGRAM and sees `op` here. git and gh get their
    # credentials from the credential helper, never from `op run`, so denying
    # this costs nothing and keeps the push guards unbypassable.
    git | gh) return 0 ;;
    # THE SAME ARGUMENT, APPLIED TO `op` ITSELF — and this one was missed until
    # 2026-08-19. `op run -- op read op://…` walked straight past everything:
    # this guard saw the child as an unremarkable program and allowed it, and
    # `permissions.deny` never matched because its rules are anchored on `op
    # read` / `op-agent` as the FIRST token, while here the first token is `op
    # run`. `permissions.allow` carries `Bash(op run:*)`, so the shape was not
    # merely permitted, it was pre-approved. Measured: `op run -- op read`,
    # `op run -- op-agent secret` and `op run -- op item edit` were all allowed.
    #
    # Masking does not rescue it. `op run` conceals values it INJECTED into the
    # child's environment; a child that reads a secret itself injected nothing,
    # so there is no value to match and the credential lands on stdout — which
    # is model context, and is the exact 2026-07-25 leak.
    #
    # So `op run` may not be used as a trampoline back into `op`. Nothing
    # legitimate needs it: `op run` exists to hand a secret to a program that
    # consumes it, and `op` consuming its own output is not that. Path spellings
    # are covered because the caller basenames $child before this runs.
    op | op-agent) return 0 ;;
    *) return 1 ;;
  esac
}

segs=$(_split "$cmd")
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
  set -- $(_norm "$seg")
  set +f
  [ $# -gt 0 ] || continue
  # basename, so `/opt/homebrew/bin/op` and `~/.local/bin/op-agent` are caught.
  # This is the path-spelling hole `permissions.deny` cannot close by pattern.
  prog=${1##*/}

  if _is_interpreter "$prog"; then
    # Only interpreter segments get a substring scan — a prose `-m "add op
    # support"` on a `git` segment is never reached, so the message false
    # positive that this suite exists to prevent cannot recur here.
    # Anchored on a real op SUBCOMMAND, not the bare word. `xargs grep op foo`
    # and `bash -c 'echo loop'` must not trip this; `sh -c 'op read op://x'` and
    # `sh -c '/opt/homebrew/bin/op read …'` must. A leading `/` is outside the
    # word class, so every path spelling is caught by the same pattern.
    if printf '%s' "$(_unquote "$seg")" |
      grep -qE '(^|[^A-Za-z0-9_.-])op(-agent)?[[:space:]]+(read|inject|run|item|document|vault|account|user|group|service-account|whoami|signin|secret|header|git-credential)([^A-Za-z0-9_-]|$)'; then
      deny "\`$prog\` is being handed a payload containing an \`op\` command, which this guard cannot tokenize — an interpreter is the one path that walks past both the guard and \`permissions.deny\`. Run the op command directly instead of through \`$prog -c\`.

$SAFE_SHAPES"
    fi
    continue
  fi

  if [ "$prog" = "op-agent" ]; then
    shift
    case "${1:-}" in
      status) continue ;;
      *)
        deny "\`op-agent ${1:-}\` is denied. \`secret\`, \`header\` and \`git-credential get\` each print a live credential to stdout, and stdout is model context — \`op-agent header\` is the command that put a PAT into a transcript on 2026-07-25. op-agent is plumbing: MCP resolvers and git exec it themselves, so an agent never needs to type it. Only \`op-agent status\` (a verdict, no secret) is permitted.

$SAFE_SHAPES"
        ;;
    esac
  fi

  [ "$prog" = "op" ] || continue

  shift
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _skip_op_global emits space-separated tokens
  set -- $(_skip_op_global "$@")
  set +f
  sub=${1:-}

  case "$sub" in
    # ---- op run: THE recommended shape ------------------------------------
    # Secrets are injected into the child's environment and never touch stdout;
    # 1Password additionally masks any known secret value appearing in the
    # child's output. This is the whole point of the change.
    run)
      shift
      seen_ddash=0
      while [ $# -gt 0 ]; do
        case "$1" in
          # Masking is what makes this shape safe to allow. Turning it off is
          # the one flag that converts `op run` back into a printing command.
          --no-masking)
            deny "\`op run --no-masking\` is denied. Masking is the property that makes \`op run\` safe in an agent session: with it on, a secret that reaches the child's stdout is replaced with \`<concealed by 1Password>\`; with it off, the raw value lands in model context. Drop the flag.

$SAFE_SHAPES"
            ;;
          --)
            seen_ddash=1
            shift
            break
            ;;
          *) shift ;;
        esac
      done
      if [ "$seen_ddash" = 0 ]; then
        deny "\`op run\` needs an explicit \`--\` before the command it runs (\`op run --env-file=.env -- npm publish\`). Without it this guard cannot tell which words are the child command, and it will not guess about a secret-bearing invocation.

$SAFE_SHAPES"
      fi
      child=${1:-}
      child=$(_unquote "$child")
      child=${child##*/}
      if [ -z "$child" ]; then
        deny "\`op run --\` has no command after the \`--\`.

$SAFE_SHAPES"
      fi
      if _bad_op_run_child "$child"; then
        deny "\`op run -- $child\` is denied. Either it exists to print the environment (which defeats masking and dumps every injected secret into model context), or it is an interpreter/VCS command whose payload this guard cannot see through — \`op run -- git push\` in particular would hide the push from rebase-guard.sh. Run \`op run --\` against the actual program that needs the secret.

$SAFE_SHAPES"
      fi
      continue
      ;;

    # ---- op inject: safe ONLY with an out-file -----------------------------
    # Bare `op inject -i tpl` renders the template to STDOUT, secrets and all.
    # With `-o` it writes a file and prints nothing.
    inject)
      shift
      out=0
      while [ $# -gt 0 ]; do
        case "$1" in
          -o | --out-file)
            out=1
            break
            ;;
          --out-file=*)
            out=1
            break
            ;;
          *) shift ;;
        esac
      done
      [ "$out" = 1 ] && continue
      deny "\`op inject\` without \`-o\`/\`--out-file\` renders the template TO STDOUT — every secret reference in it becomes a live value in model context. Add an out-file: \`op inject -i .env.tpl -o .env\`.

$SAFE_SHAPES"
      ;;

    # ---- metadata verbs: no secret VALUE in the output ---------------------
    # `''` is bare `op` (prints usage) or `op` with only global flags consumed.
    '' | --version | -v | --help | -h | help | whoami | signin | signout | update)
      continue
      ;;
    # DELIBERATELY ABSENT: `op vault list`, `op item list`, `op account/user/group
    # list`. They print no secret VALUE, so an allow-list built only on "does this
    # print a secret" would include them — but CLAUDE.md records a separate,
    # measured exposure they would re-open: `op vault list` "enumerates every vault
    # in the account (verified 2026-08-05, no prompt)", because the desktop
    # integration answers for vaults far outside `claude-agent`. Item titles carry
    # the same problem one level down.
    #
    # They were denied before this change and they stay denied. This change is
    # scoped to "an agent may USE a secret without reading it" — inventory
    # browsing is a different capability and is not what was asked for. Widening
    # to it would be a silent second change riding along with the first.
    # `op service-account create` prints a NEW TOKEN to stdout. `ratelimit` is
    # the read-only counter that CLAUDE.md points at for usage on a plan tier
    # with no audit log.
    service-account)
      shift
      case "${1:-}" in
        ratelimit) continue ;;
      esac
      ;;
  esac

  deny "\`op ${sub}\` is not on this guard's allow-list, so it is denied by default. This is an ALLOW-list on purpose: the 2026-07-25 leak happened because a deny-list of verbs missed the one verb that leaked, so anything not proven non-printing — \`read\`, \`item get\`, \`document get\`, a verb 1Password adds later, or a typo — fails closed here rather than open.

$SAFE_SHAPES"
done << EOF
$segs
EOF

allow
