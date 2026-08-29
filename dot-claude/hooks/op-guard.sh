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

# Cheap bail-out: if none of the secret-printing programs appears anywhere, this
# guard has no opinion. Word-boundary on `op`, so `open`, `loop`, `--option` and
# `chmod` do not wake it up.
#
# `boom`, `security` and `git` are here because each has ONE subcommand that
# prints a live credential to stdout, and none of those commands contains an `op`
# token, so the original pattern slept through all three. `security
# find-generic-password` is the sharpest: the token it guards is the SERVICE
# ACCOUNT's, which reads every item in the vault, and the keychain item is named
# `op-claude-agent` — where the character after `op` is `-`, which this pattern's
# own exclusion class rules out. The highest-value secret on the machine sat
# behind the one rule that could never fire.
#
# Each of those three is anchored on its SUBCOMMAND, not on the program name, and
# that is load-bearing rather than tidy. Waking on the bare word `git` drags every
# ordinary git command into this guard's unconditional deny paths — the ones for a
# program name that comes from a command substitution, and for a name it cannot
# statically read. Measured on 2026-08-28, waking on the program name alone turned
# `$(git rev-parse --show-toplevel)/scripts/gates.sh`, `$(brew --prefix)/bin/git
# status` and `$HOME/.local/bin/boom verify` from allow into DENY — the last being
# boom's actual install path on this machine — and answered each with an
# op-secrets lecture. Those deny paths are correct for an `op`-shaped command and
# wrong for anything else, so the bail-out is what must stay narrow.
#
# `op` keeps its bare-program anchor: every `op` verb is a candidate, which is the
# whole premise of the allow-list below.
printf '%s' "$cmd" | grep -qE '(^|[^A-Za-z0-9_.-])(op(-agent)?([^A-Za-z0-9_-]|$)|boom([^A-Za-z0-9_-]|$).*askpass|security([^A-Za-z0-9_-]|$).*find-(generic|internet)-password|security([^A-Za-z0-9_-]|$).*find-(certificate|identity)|git([^A-Za-z0-9_-]|$).*credential)' || allow

# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

SAFE_SHAPES='Non-printing shapes an agent may use:
  op run [--env-file=F] -- CMD    inject secrets as env into CMD (values masked in its output)
  op inject -i TPL -o OUT         render a template TO A FILE
  op whoami / op --version        identity and version, no values
  op item list [--vault V]        titles and metadata, no values
  op item move ITEM --destination-vault V   OUT of the agent vault only
Everything else is denied because it can put a secret VALUE on stdout, and stdout
is model context. To USE a secret, never read it — pass it with "op run --".'

# The vault this agent's service account can read. `op item move` may take items OUT
# of it but never INTO it: inbound is self-escalation, since SA vault access is
# immutable after creation and membership is the only lever over blast radius.
AGENT_VAULT=${BOOM_vault:-claude-agent}

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

# A command whose whole job is to print the environment defeats `op run`'s
# masking argument, and an interpreter after `--` can do anything at all.
_bad_op_run_child() { # $1 = basename of the command after `--`, $2.. = its argv
  local _a _prog=$1
  shift
  case "$_prog" in
    env | printenv | set | export | declare | typeset | printf | echo) return 0 ;;
    sh | bash | zsh | dash | ksh | fish | eval | xargs) return 0 ;;
    # Same argument as the shells directly above, and the same omission the
    # 2026-08-28 audit found in `_is_interpreter`: `op run -- python3 -c
    # "print(os.environ)"` prints every INJECTED value, which is precisely what
    # listing `env` and `printenv` here exists to stop. A language runtime is a
    # more capable `printenv`, not a less capable one.
    # `awk`'s program is inline by construction, so it has no safe shape here.
    awk) return 0 ;;
    # The other runtimes DO have a safe shape, and it is the main reason `op run`
    # exists: `op run -- node build.js` hands a secret to a program that consumes
    # it. Denying the whole runtime broke exactly that — `op run -- bun run dev`
    # and `op run -- node build.js` are allow-cases in this suite, and both went
    # red. What is unsafe is the INLINE script: `-e`/`-c` is a `printenv` whose
    # output you cannot predict. So the FLAG decides, not the language.
    python | python2 | python3 | ruby | perl | node | bun | deno | php | lua)
      for _a in "$@"; do
        case "$_a" in
          -c | -e | -E | -p | -P | --eval | --print | -) return 0 ;;
          # `deno eval` is a subcommand rather than a flag.
          eval) return 0 ;;
          # Bundled short flags: perl's `-ne`, `-lane`; ruby's `-ne`.
          -[A-Za-z]*) case "$_a" in *e* | *c*) return 0 ;; esac ;;
        esac
      done
      return 1
      ;;
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

# The op-subcommand pattern, named once because two scans now share it and must
# never drift apart. Anchored on a real SUBCOMMAND, so the bare word `op` in a
# commit message is not a match.
#
# `header` stays in this list although the verb was deleted on 2026-08-28. This
# pattern is DETECTION, not documentation: it decides whether an interpreter
# payload looks op-shaped, and a hook resolves `~/.claude/hooks/` at run time
# while `op-agent` resolves on PATH — a machine mid-provision, or holding a stale
# link, can pair this guard with an op-agent that still has the verb. Keeping a
# retired spelling costs a branch in a regex; dropping one costs a credential.
# The deny MESSAGE below is where a dead verb must not appear, and does not.
_OP_VERB_RE='(^|[^A-Za-z0-9_-])op(-agent)?[[:space:]]+(read|inject|run|item|document|vault|account|user|group|service-account|whoami|signin|secret|header|git-credential)([^A-Za-z0-9_-]|$)'

# A payload piped INTO an interpreter is never an argv token of the interpreter's
# own segment: in `echo "op read op://…" | bash`, the `echo` segment carries the
# secret command and the `bash` segment carries nothing. Neither is deniable
# alone, so this scans the WHOLE command — but only when it genuinely pipes into
# an interpreter.
#
# The pipe is matched against a STRUCTURE-ONLY view: heredoc bodies removed and
# quoted runs blanked. Previously both scans read the raw command, so a pipe
# character inside a quoted argument counted as a shell operator, and
# `git commit -m "note: x |eval can run op read op://a/b/c"` was DENIED while
# the identical message without the pipe was allowed. That is the commit-message
# false positive this suite exists to prevent, reopened by the gate meant to
# keep it closed — it blocked read-only work three times during the 2026-08-28
# audit, including the writing of this very finding.
#
# The op-verb scan below still reads the RAW command on purpose: the payload of
# a genuine attack lives INSIDE the quotes, so blanking them for the content
# scan would hide the thing being looked for. Structure from the blanked view,
# content from the raw one.
if printf '%s' "$(_blank_quoted "$(_strip_heredocs "$cmd")")" |
  grep -qE '\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?([A-Za-z0-9_./-]*/)?(sh|bash|zsh|dash|ksh|fish|eval|python[23]?|ruby|perl|node|bun|deno|php|lua|awk)([[:space:]]|$)'; then
  if _scan_text "$cmd" | grep -qE "$_OP_VERB_RE"; then
    deny "This command pipes a payload containing an \`op\` command into an interpreter. Neither the producing segment nor the interpreter segment names \`op\` as its program, so the shape walks past both this guard's tokenizer and \`permissions.deny\`. Run the op command directly.

$SAFE_SHAPES"
  fi
fi

# A command substitution in PROGRAM position — `` `echo op` read op://… `` or
# `$(echo op) read op://…` — names a program only the shell can resolve, and
# the shell resolves it AFTER this guard has run. It cannot be caught after
# `_split`, because `_split` treats the substitution as a separator and
# decomposes it: the pieces are `echo op` and `read op://…`, neither of which
# has `op` in program position, so both fall through as ordinary commands.
#
# Anchored at the start of the command or immediately after a separator, so a
# substitution inside an ARGUMENT is untouched — `git commit -m "fix \`op read\`
# guard"` and `tar -C "$(pwd)" -cf -` are both prose or paths, not a program
# name, and denying those would recreate the false positive this suite exists
# to prevent.
if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(\$\(|`)'; then
  deny "This command's program name comes from a command substitution, so what actually runs is decided by the shell after this guard has already allowed it — and an unreadable program name is the case this guard closes rather than waves through. Spell the program out literally.

$SAFE_SHAPES"
fi

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

  # A program name that is itself a shell expansion (`$OP read …`,
  # `$(echo op) read …`) cannot be read statically, and this guard's whole
  # contract is that an unrecognized name is closed, not open. Same doctrine as
  # the unknown-subcommand arm below.
  if [ "$prog" = "$_UNRESOLVED" ]; then
    deny "This command's program name is a shell expansion, so no guard can tell what it runs — and an unreadable name is exactly the case this guard closes rather than waves through. Spell the program out literally.

$SAFE_SHAPES"
  fi

  if _is_interpreter "$prog"; then
    # Only interpreter segments get a substring scan — a prose `-m "add op
    # support"` on a `git` segment is never reached, so the message false
    # positive that this suite exists to prevent cannot recur here.
    # Anchored on a real op SUBCOMMAND, not the bare word. `xargs grep op foo`
    # and `bash -c 'echo loop'` must not trip this; `sh -c 'op read op://x'` and
    # `sh -c '/opt/homebrew/bin/op read …'` must. A leading `/` is outside the
    # word class, so every path spelling is caught by the same pattern.
    if _scan_text "$seg" | grep -qE "$_OP_VERB_RE"; then
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
        deny "\`op-agent ${1:-}\` is denied. \`secret\` and \`git-credential get\` each print a live credential to stdout, and stdout is model context — the deleted \`header\` verb is what put a PAT into a transcript on 2026-07-25. op-agent is plumbing: MCP resolvers and git exec it themselves, so an agent never needs to type it. Only \`op-agent status\` (a verdict, no secret) is permitted.

$SAFE_SHAPES"
        ;;
    esac
  fi

  # `security find-generic-password` reads the login keychain, and the item it
  # reads here is the 1Password SERVICE ACCOUNT token — the credential that can
  # read every item in the agent vault. `permissions.deny` carries
  # `Bash(security find-generic-password:*)`, but that rule is name-anchored and
  # never got the path-spelling sibling `Bash(*/op *)` and `Bash(*/op-agent *)`
  # both have, so `/usr/bin/security find-generic-password -w` walked past it.
  # Only the value-printing subcommands are denied: `security list-keychains`
  # and the rest stay ordinary commands.
  if [ "$prog" = "security" ]; then
    shift
    case "${1:-}" in
      find-generic-password | find-internet-password | find-certificate | find-identity)
        deny "\`security ${1:-}\` is denied. With \`-w\` it prints a keychain secret to stdout, and the item this machine keeps there is the 1Password service-account token — the one credential that can read every item in the agent vault. Read nothing; to USE a secret, pass it with \`op run --\`.

$SAFE_SHAPES"
        ;;
      *) continue ;;
    esac
  fi

  # `git credential` resolves through the helper chain in settings.json, which
  # ends at `op-agent git-credential` — and that prints `password=<PAT>` on
  # stdout. So `git credential fill` hands the model a live PAT: the same class
  # as the 2026-07-25 `op-agent header` incident, through a different door.
  # `Bash(git credential:*)` is name-anchored like the `security` rule above, so
  # `/usr/bin/git credential fill` and `git -C /tmp credential fill` both walked
  # past it. `_skip_global` steps over `-C`/`-c`/`--git-dir` first, so one arm
  # closes every spelling.
  if [ "$prog" = "git" ]; then
    shift
    set -f
    # shellcheck disable=SC2046 # intentional word-split: _skip_global emits space-separated tokens
    set -- $(_skip_global "$@")
    set +f
    case "${1:-}" in
      credential | credential-store | credential-cache)
        deny "\`git ${1:-}\` is denied. The credential helper chain in \`settings.json\` ends at \`op-agent git-credential\`, which prints \`password=<PAT>\` on stdout — so this hands a live GitHub PAT to model context. git uses the helper itself on every push and fetch; an agent never needs to invoke it.

$SAFE_SHAPES"
        ;;
      *) continue ;;
    esac
  fi

  # `boom` is a secret-printing program too, and was in no deny rule and no arm
  # here. Its own --help: "askpass  Resolve a secret ref to stdout (the
  # SUDO_ASKPASS helper — not for interactive use)". Measured 2026-08-28:
  # `boom askpass op://claude-agent/…/credential` reached ALLOW silently, so
  # every item in the service-account vault was one command away — through the
  # binary this repo drives on every sync, past an allow-list built precisely
  # because "a deny-list of verbs missed the one verb that leaked".
  #
  # Allow-listed, not deny-listed, for that same recorded reason: an unknown
  # verb fails CLOSED, which is the direction that stays safe when boom adds a
  # command. That is the treatment this guard already gives an unrecognized
  # `op` subcommand. Extending the list is one word plus a case in cases.tsv.
  if [ "$prog" = "boom" ]; then
    shift
    case "${1:-}" in
      verify | status | plan | source | where | edit | rollback | checkpoint | \
        upgrade | doctor | lock | adopt | init | fleet | module | code | mcp | \
        completions | man | skill | uninstall | --help | -h | --version | -v | '')
        continue
        ;;
      askpass)
        deny "\`boom askpass\` is denied. It resolves a secret ref to stdout, and stdout is model context — the same shape as \`op read\` and \`op-agent header\`, which are denied for the same reason. It exists as a SUDO_ASKPASS helper for boom to exec itself, not as a command to type.

$SAFE_SHAPES"
        ;;
      *)
        deny "\`boom ${1:-}\` is not a verb this guard recognizes, so it is denied rather than assumed safe — \`boom askpass\` prints a live credential to stdout, and a deny-list of verbs is exactly what missed \`op-agent header\` on 2026-07-25. If this verb cannot print a secret, add it to the allow-list in \`dot-claude/hooks/op-guard.sh\` and a case to \`dot-claude/hooks/tests/cases.tsv\`.

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
      if _bad_op_run_child "$child" "$@"; then
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
    # `op item list` and `op item move` — allowed, and the note that used to sit
    # here said they were excluded because inventory browsing "is not what was
    # asked for". It has since been asked for, with a named use: `op-agent audit`
    # reports an item in the agent vault that nothing declares, and moving it out
    # is the fix. Both print titles and metadata, never a secret VALUE, which is
    # this guard's actual criterion.
    #
    # `op item move` IS DIRECTIONAL, and that is the load-bearing part. Moving an
    # item OUT of the agent vault can only narrow this agent's own reach. Moving
    # one IN widens it, which is a self-escalation path — an agent could grant
    # itself a production credential by relocating it into the vault its service
    # account reads. SA vault access is immutable after creation, so membership is
    # the only lever there is; inbound moves are the one way to pull that lever the
    # wrong way. Outbound allowed, inbound denied.
    #
    # `op item get`, `edit`, `create` and `delete` are NOT here and fall through to
    # the default deny: reading prints values, and the rest mutate or destroy.
    item)
      shift
      case "${1:-}" in
        list)
          continue
          ;;
        move)
          shift
          while [ $# -gt 0 ]; do
            case "$1" in
              --destination-vault)
                [ "${2:-}" = "$AGENT_VAULT" ] && deny "\`op item move --destination-vault $AGENT_VAULT\` is denied. Moving an item INTO the agent vault widens what this service account can read — it is how an agent would grant itself a credential it was never given. Moving items OUT is allowed, because that can only narrow its own reach.

$SAFE_SHAPES"
                shift
                ;;
              --destination-vault=*)
                [ "${1#--destination-vault=}" = "$AGENT_VAULT" ] && deny "\`op item move --destination-vault=$AGENT_VAULT\` is denied. Moving an item INTO the agent vault widens what this service account can read — it is how an agent would grant itself a credential it was never given. Moving items OUT is allowed, because that can only narrow its own reach.

$SAFE_SHAPES"
                ;;
            esac
            shift
          done
          continue
          ;;
      esac
      ;;
    # STILL DENIED: `op vault list`, `op account/user/group list`. These print no
    # secret VALUE either, but the measured exposure recorded for them is a
    # different capability from the one just granted: `op vault list` "enumerates
    # every vault in the account (verified 2026-08-05, no prompt)", because the
    # desktop integration answers for vaults far outside `claude-agent`. Scoped
    # item access was asked for; account-wide enumeration was not.
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
