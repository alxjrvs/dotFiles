#!/usr/bin/env bash
# Claude Code PreToolUse guard — makes the 1Password CLI USABLE by agents while
# keeping resolved secrets out of model context.
#
# It is an ALLOW-list of shapes that provably do not put a secret VALUE on
# stdout, and denies everything else `op`-shaped. The direction is the whole
# design: under a deny-list a forgotten verb sails through; under an allow-list
# a new verb, an unlisted one and a typo all fail the same closed way. What DOES
# get through is SAFE_SHAPES below — a control that blocks the vendor's
# recommended pattern is an outage, not a floor.
#
# WHAT IT NEVER DOES: emit `permissionDecision: "allow"`. A hook `allow` bypasses
# the permission system entirely, putting this script *above* `permissions.deny`.
# It only ever denies or stays silent, so it can subtract permission and never
# add it, and the two compose instead of racing.
#
# Wired via dot-claude/settings.json `hooks.PreToolUse` (matcher "Bash"),
# alongside rebase-guard.sh, worktree-remove-guard.sh and repo-scope-guard.sh.
# It FAILS OPEN on a missing jq, a bad envelope or a missing guard-lib: the
# residual `permissions.deny` entries still cover the paths with confirmed
# incidents, so that degrades to a floor rather than to nothing.
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
# prints a live credential and none of them contains an `op` token. Each is
# anchored on that SUBCOMMAND, not on the program name, and that is load-bearing
# rather than tidy: waking on the bare word `git` or `boom` drags every ordinary
# invocation into this guard's unconditional deny paths (a program name from a
# command substitution, a name it cannot statically read), which are correct for
# an `op`-shaped command and wrong for anything else. `security
# find-generic-password` needs its own anchor because the keychain item is named
# `op-claude-agent`, and `-` is outside the `op` anchor's word class.
#
# `op` keeps its bare-program anchor: every verb is a candidate, which is the
# premise of the allow-list below.
printf '%s' "$cmd" | grep -qE '(^|[^A-Za-z0-9_.-])(op(-agent)?([^A-Za-z0-9_-]|$)|boom([^A-Za-z0-9_-]|$).*askpass|security([^A-Za-z0-9_-]|$).*find-(generic|internet)-password|security([^A-Za-z0-9_-]|$).*find-(certificate|identity)|git([^A-Za-z0-9_-]|$).*credential)' || allow

# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

SAFE_SHAPES='Non-printing shapes an agent may use:
  op run [--env-file=F] -- CMD    inject secrets as env into CMD (values masked in its output)
  op inject -i TPL -o OUT         render a template TO A FILE
  op whoami / op --version        identity and version, no values
  op item list [--vault V]        titles and metadata, no values
  op item move ITEM --destination-vault V   OUT of the agent vault only
  op plugin list|inspect|init|clear         shell-plugin config, no values
  op plugin run -- CMD                      inject a plugin credential into CMD
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
    # A language runtime is a more capable `printenv`, not a less capable one:
    # `op run -- python3 -c "print(os.environ)"` prints every INJECTED value,
    # which is precisely what listing `env` and `printenv` here exists to stop.
    # `awk`'s program is inline by construction, so it has no safe shape here.
    awk) return 0 ;;
    # The other runtimes DO have a safe shape, and it is the main reason `op run`
    # exists: `op run -- node build.js` hands a secret to a program that consumes
    # it, so denying the whole runtime breaks the feature. The INLINE script is
    # what is unsafe — `-e`/`-c` is an unpredictable `printenv` — so the FLAG
    # decides, not the language.
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
    # THE SAME ARGUMENT, APPLIED TO `op` ITSELF. `permissions.deny` cannot help:
    # its rules are anchored on `op read` / `op-agent` as the FIRST token, while
    # the first token here is `op run` — and `permissions.allow` carries
    # `Bash(op run:*)`, so the shape is pre-approved rather than merely allowed.
    # Masking does not rescue it: `op run` conceals values it INJECTED, and a
    # child that reads a secret itself injected nothing, so the credential lands
    # on stdout. Path spellings are covered because the caller basenames $child.
    op | op-agent) return 0 ;;
    *) return 1 ;;
  esac
}

# The vetting shared by `op run --` and `op plugin run --`. Both hand a live
# credential to a child process, so both are safe exactly to the extent that the
# child cannot print its own environment. One function rather than a copy,
# because a copy is how the two spellings drift.
#
# `--no-masking` is rejected for BOTH although 1Password documents it only on
# `op run`: masking on `op plugin run` is undocumented either way, so rejecting
# it costs nothing today and fails closed if the flag is added tomorrow.
#
# $1 = label for the deny messages, $2.. = argv AFTER the verb.
_vet_injecting_run() {
  local _label=$1 _child _seen_ddash=0
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-masking)
        deny "\`$_label --no-masking\` is denied. Masking is the property that makes an injecting invocation safe in an agent session: with it on, a secret that reaches the child's stdout is replaced with \`<concealed by 1Password>\`; with it off, the raw value lands in model context. Drop the flag.

$SAFE_SHAPES"
        ;;
      --)
        _seen_ddash=1
        shift
        break
        ;;
      *) shift ;;
    esac
  done
  if [ "$_seen_ddash" = 0 ]; then
    deny "\`$_label\` needs an explicit \`--\` before the command it runs (\`op run --env-file=.env -- npm publish\`, \`op plugin run -- gh repo list\`). Without it this guard cannot tell which words are the child command, and it will not guess about a secret-bearing invocation.

$SAFE_SHAPES"
  fi
  _child=${1:-}
  _child=$(_unquote "$_child")
  _child=${_child##*/}
  if [ -z "$_child" ]; then
    deny "\`$_label --\` has no command after the \`--\`.

$SAFE_SHAPES"
  fi
  if _bad_op_run_child "$_child" "$@"; then
    deny "\`$_label -- $_child\` is denied. Either it exists to print the environment (which defeats masking and dumps every injected secret into model context), or it is an interpreter/VCS command whose payload this guard cannot see through — \`$_label -- git push\` in particular would hide the push from rebase-guard.sh. Run \`$_label --\` against the actual program that needs the secret.

$SAFE_SHAPES"
  fi
}

# The op-subcommand pattern, named once because two scans share it and must
# never drift apart. Anchored on a real SUBCOMMAND, so the bare word `op` in a
# commit message is not a match.
#
# `header` stays in this list although the verb has been deleted. This pattern is
# DETECTION, not documentation, and a hook resolves `~/.claude/hooks/` at run
# time while `op-agent` resolves on PATH — a machine mid-provision, or holding a
# stale link, can pair this guard with an op-agent that still has the verb.
#
# `plugin` is here for ONE of its verbs: `op plugin run -- CMD` injects a live
# credential exactly as `op run --` does, so `sh -c "op plugin run -- env"` is
# the trampoline re-spelled. The discovery verbs pay for that — `sh -c "op
# plugin list"` is denied although it prints nothing. Run it directly.
_OP_VERB_RE='(^|[^A-Za-z0-9_-])op(-agent)?[[:space:]]+(read|inject|run|item|document|vault|account|user|group|service-account|whoami|signin|secret|header|git-credential|plugin)([^A-Za-z0-9_-]|$)'

# A payload piped INTO an interpreter is never an argv token of the interpreter's
# own segment: in `echo "op read op://…" | bash`, the `echo` segment carries the
# secret command and the `bash` segment carries nothing. Neither is deniable
# alone, so this scans the WHOLE command — but only when it genuinely pipes into
# an interpreter.
#
# The pipe is matched against a STRUCTURE-ONLY view (heredoc bodies removed,
# quoted runs blanked); on the raw command a pipe inside a quoted argument counts
# as a shell operator and denies `git commit -m "note: x |eval can run op read
# op://a/b/c"`. The op-verb scan below still reads the RAW command on purpose:
# an attack's payload lives INSIDE the quotes. Structure from the blanked view,
# content from the raw one.
if printf '%s' "$(_blank_quoted "$(_strip_heredocs "$cmd")")" |
  grep -qE '\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?([A-Za-z0-9_./-]*/)?(sh|bash|zsh|dash|ksh|fish|eval|python[23]?|ruby|perl|node|bun|deno|php|lua|awk)([[:space:]]|$)'; then
  if _scan_text "$cmd" | grep -qE "$_OP_VERB_RE"; then
    deny "This command pipes a payload containing an \`op\` command into an interpreter. Neither the producing segment nor the interpreter segment names \`op\` as its program, so the shape walks past both this guard's tokenizer and \`permissions.deny\`. Run the op command directly.

$SAFE_SHAPES"
  fi
fi

# A command substitution in PROGRAM position — `` `echo op` read op://… `` or
# `$(echo op) read op://…` — names a program only the shell can resolve, after
# this guard has run. It cannot be caught after `_split`, which treats the
# substitution as a separator and decomposes it into `echo op` and `read op://…`,
# neither of which has `op` in program position.
#
# Anchored at the start of the command or immediately after a separator, so a
# substitution inside an ARGUMENT is untouched — `git commit -m "fix \`op read\`
# guard"` and `tar -C "$(pwd)" -cf -` are prose or paths, not a program name.
# Quoted runs are blanked with state carried ACROSS LINES first: `^` is a LINE
# anchor in grep, so otherwise the start of every line of a multi-line argument
# reads as program position.
if printf '%s' "$(_blank_quoted_ml "$(_strip_heredocs "$cmd")")" |
  grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(\$\(|`)'; then
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
    # Only interpreter segments get a substring scan, so a prose `-m "add op
    # support"` on a `git` segment is never reached. Anchored on a real op
    # SUBCOMMAND, not the bare word: `xargs grep op foo` and `bash -c 'echo
    # loop'` must not trip this; `sh -c 'op read op://x'` and `sh -c
    # '/opt/homebrew/bin/op read …'` must. A leading `/` is outside the word
    # class, so every path spelling is caught by the same pattern.
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
  # read every item in the agent vault. The `permissions.deny` rule for it is
  # name-anchored with no path-spelling sibling, so `/usr/bin/security
  # find-generic-password -w` walks past it. Only the value-printing subcommands
  # are denied: `security list-keychains` and the rest stay ordinary commands.
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
  # stdout, handing the model a live PAT. `Bash(git credential:*)` is
  # name-anchored like the `security` rule above, so `/usr/bin/git credential
  # fill` and `git -C /tmp credential fill` both walk past it. `_skip_global`
  # steps over `-C`/`-c`/`--git-dir` first, so one arm closes every spelling.
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

  # `boom askpass` resolves a secret ref to stdout (its own --help: "the
  # SUDO_ASKPASS helper — not for interactive use"), so every item in the
  # service-account vault is one command away through the binary this repo drives
  # on every sync.
  #
  # Allow-listed, not deny-listed: an unknown verb fails CLOSED, which stays safe
  # when boom adds a command. Extending it is one word plus a case in cases.tsv.
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
    # 1Password additionally masks any known secret value in the child's output.
    run)
      shift
      _vet_injecting_run "op run" "$@"
      continue
      ;;

    # ---- op plugin: the biometric path, for the CLIs an agent must NOT drive -
    # Shell plugins keep a CLI's credential in the vault instead of plaintext on
    # disk (`~/.netrc`, a `credentials.toml`), released per-invocation behind
    # Touch ID. They are admitted not because they are harmless but because they
    # move a credential OUT of a file this agent can already read — and the
    # biometric prompt is a control an agent cannot satisfy, which keeps the
    # agent off the deploy CLIs while giving the human a keychain-free path.
    #
    # `list`, `inspect`, `clear` and `init` print configuration metadata, never a
    # credential VALUE. `run` is the one verb that injects, so it takes the same
    # vetting as `op run --` through the same function.
    plugin)
      shift
      case "${1:-}" in
        list | inspect | init | clear | --help | -h | '')
          continue
          ;;
        run)
          shift
          _vet_injecting_run "op plugin run" "$@"
          continue
          ;;
      esac
      deny "\`op plugin ${1:-}\` is not a verb this guard recognizes, so it is denied rather than assumed safe — \`op plugin run\` hands a live credential to a child process, and a deny-list of verbs is exactly what missed \`op-agent header\` on 2026-07-25. If this verb cannot print or inject a secret, add it to the allow-list in \`dot-claude/hooks/op-guard.sh\` and a case to \`dot-claude/hooks/tests/cases.tsv\`.

$SAFE_SHAPES"
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
    # `op item list` and `op item move` print titles and metadata, never a secret
    # VALUE, which is this guard's actual criterion.
    #
    # `op item move` IS DIRECTIONAL, and that is the load-bearing part. Moving an
    # item OUT of the agent vault can only narrow this agent's own reach; moving
    # one IN widens it — an agent granting itself a production credential by
    # relocating it into the vault its service account reads. SA vault access is
    # immutable after creation, so membership is the only lever there is.
    # Outbound allowed, inbound denied.
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
    # secret VALUE either, but they enumerate every vault and every account in
    # the account, far outside `claude-agent` — scoped item access was asked for,
    # account-wide enumeration was not.
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
