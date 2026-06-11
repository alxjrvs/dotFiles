#!/usr/bin/env bats
# Unit tests for the claude-setup-hardening pass.
# Covers: lock-file-guard fail-closed (jq absent), mcp-guard destructive deny,
# and the format-on-save eslint-removal guard.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
JQDIR="$(dirname "$(mise which jq 2> /dev/null || command -v jq)")"

load 'helpers'

setup() {
  scrub_git_env
  export PATH="$JQDIR:/opt/homebrew/bin:/usr/bin:/bin"
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats.XXXXXX")"
  export HOME="$TDIR"
  mkdir -p "$HOME/.claude/state"
}
teardown() { rm -rf "$TDIR"; }

# Helper: run a hook with a JSON payload on stdin.
run_hook() {
  local hook="$1" json="$2"
  printf '%s' "$json" | "$ROOT/hooks/$hook"
}

# jq pretty-prints deny payloads with a space: "permissionDecision": "deny"
# The jq-absent fail-closed path uses a compact printf, so match both forms.
is_deny() { [[ "$1" == *'"permissionDecision": "deny"'* || "$1" == *'"permissionDecision":"deny"'* ]]; }

# jq_absent: run a hook with a PATH that has bash (/bin) but no jq, so the
# guard's `command -v jq` lookup fails. The shebang uses an absolute /usr/bin/env
# so it resolves regardless of PATH. Used to prove the fail-closed deny path.
jq_absent() {
  local hook="$1" json="$2"
  printf '%s' "$json" | PATH=/bin "$ROOT/hooks/$hook"
}

# ── lock-file-guard: fail-closed when jq is absent ──────────────────────────
# With jq off PATH the guard cannot inspect the payload, so it must DENY rather
# than silently allow the edit.
@test "lock-file-guard: fails closed (deny) when jq is unavailable" {
  run jq_absent lock-file-guard '{"tool_input":{"file_path":"/x/bun.lock"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  [[ "$output" == *"jq unavailable"* ]]
}

# Sanity: even a non-lock path fails closed when jq is gone (cannot inspect).
@test "lock-file-guard: jq absent denies regardless of path" {
  run jq_absent lock-file-guard '{"tool_input":{"file_path":"/x/main.rs"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

# ── lock-file-guard: known lock denied, normal file silent ──────────────────
@test "lock-file-guard: denies Cargo.lock" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/repo/Cargo.lock"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "lock-file-guard: silent on a normal source file" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/repo/src/lib.rs"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── mcp-guard ───────────────────────────────────────────────────────────────
@test "mcp-guard: allows merge_pull_request (PR merges are permitted)" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__merge_pull_request","tool_input":{}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: denies delete_file (and delete_* generally)" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__delete_file","tool_input":{}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "mcp-guard: allows push_files (github writes are permitted)" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__push_files","tool_input":{}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: silent on a read MCP tool (get_file_contents)" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__get_file_contents","tool_input":{}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: non-MCP tool is ignored" {
  run run_hook mcp-guard '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: fails closed (deny) when jq is unavailable" {
  run jq_absent mcp-guard '{"tool_name":"mcp__github__get_file_contents"}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  [[ "$output" == *"jq unavailable"* ]]
}

# ── format-on-save: eslint removal guard ────────────────────────────────────
# The eslint --fix arm was an unsandboxed code-exec vector and was removed.
# "eslint" may still appear in explanatory comments, but it must never be
# invoked: no non-comment line may reference it.
@test "format-on-save: eslint is not invoked (no non-comment reference)" {
  local hits
  # Strip comment lines (optional leading whitespace then '#') before grepping.
  hits=$(grep -vE '^[[:space:]]*#' "$ROOT/hooks/format-on-save" | grep -ci 'eslint' || true)
  [ "$hits" -eq 0 ]
}

# ── lock-file-guard: case-insensitive match (APFS) ──────────────────────────
@test "lock-file-guard: denies BUN.LOCK (case-insensitive)" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/repo/BUN.LOCK"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "lock-file-guard: denies .ENV (case-insensitive)" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/repo/.ENV"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

# ── lock-file-guard / mcp-guard: hard-block (exit 2) if the jq deny-emitter
#    fails. We shadow jq with a stub that passes through real jq EXCEPT for the
#    `-n` emit (used only by emit_deny), forcing the fallback path. The guard
#    must then write the reason to stderr and exit 2 rather than silently allow.
emit_fail_jq() {
  local hook="$1" json="$2"
  local realjq="$JQDIR/jq"
  local stub="$TDIR/stub"
  mkdir -p "$stub"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'for a in "$@"; do [ "$a" = "-n" ] && exit 1; done\n'
    printf 'exec %q "$@"\n' "$realjq"
  } > "$stub/jq"
  chmod +x "$stub/jq"
  printf '%s' "$json" | PATH="$stub:/usr/bin:/bin" "$ROOT/hooks/$hook"
}

@test "lock-file-guard: exits 2 (hard block) when the deny emitter fails" {
  run emit_fail_jq lock-file-guard '{"tool_input":{"file_path":"/repo/Cargo.lock"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"lock files"* ]]
}

@test "mcp-guard: exits 2 (hard block) when the deny emitter fails" {
  run emit_fail_jq mcp-guard '{"tool_name":"mcp__github__delete_file","tool_input":{}}'
  [ "$status" -eq 2 ]
}

# ── user-prompt-submit: the git-data cache is NEVER eval'd ───────────────────
# The cache lives at a sandbox-writable, predictable path; the hook runs
# unsandboxed. A seeded line that isn't the exact GIT_NAME='value' shape must be
# rejected (no command execution). Replicate the cache path the hook computes
# (repo_hash(toplevel).sh under $XDG_CACHE_HOME/git-data) and seed payloads.
@test "user-prompt-submit: malicious cache lines do not execute" {
  local sentinel="$TDIR/PWNED"
  local top="$TDIR/repo"
  mkdir -p "$top"
  export XDG_CACHE_HOME="$TDIR/cache"
  local hash cachedir cache
  # Compute the cache key with the hook's own repo_hash (FNV-1a, no shasum).
  hash=$(bash -c "$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/hooks/user-prompt-submit"); repo_hash \"\$1\"" _ "$top")
  cachedir="$XDG_CACHE_HOME/git-data"
  mkdir -p "$cachedir"
  cache="$cachedir/$hash.sh"
  # Three attack shapes the loose grep|eval would have run; the strict parser
  # rejects all three. Plus one legit line that must still be ingested.
  cat > "$cache" <<EOF
GIT_IS_REPO='1'
GIT_A=1; touch $sentinel
GIT_B='x'; touch $sentinel
GIT_C='\$(touch $sentinel)'
GIT_BRANCH='main'
EOF
  # Run the hook from inside $top so rev-parse/PWD resolves to it. Not a git
  # repo, so it falls back to PWD == $top, matching our computed hash.
  ( cd "$top" && printf '%s' '{"prompt":"hi"}' | "$ROOT/hooks/user-prompt-submit" ) || true
  [ ! -e "$sentinel" ]
}

# ── trim-bash-output: trims oversized output and writes nothing to disk ──────
@test "trim-bash-output: trims oversized output without spilling to a file" {
  local big
  big=$(printf 'x%.0s' $(seq 1 25000))
  local json
  json=$(jq -n --arg s "$big" '{tool_name:"Bash",session_id:"../escape",tool_response:{stdout:$s,stderr:"",interrupted:false,isImage:false}}')
  run run_hook trim-bash-output "$json"
  [ "$status" -eq 0 ]
  # Output is trimmed (elision marker present)...
  [[ "$output" == *"trim-bash-output: elided"* ]]
  # ...and the archive is gone — no spill file is written or referenced.
  [[ "$output" != *"spill"* ]]
  [[ "$output" != *"/tmp/claude/spills"* ]]
}

# ── settings.json: hardening invariants ─────────────────────────────────────
SETTINGS="$ROOT/dot-claude/settings.json"
sjq() { jq -e "$1" "$SETTINGS" > /dev/null; }

@test "settings: ~/.gitconfig is not sandbox-writable (no allowWrite entry)" {
  # The cwd "." root keeps in-project writes working (incl. nested
  # .claude/worktrees/<name> and the enclosing repo .git); ~/.cargo and
  # /opt/homebrew are the only broad allows, carved by denyWrite below.
  # ~/.gitconfig has no legit sandboxed writer, so it stays out of allowWrite.
  run jq -e '.sandbox.filesystem.allowWrite | index("~/.gitconfig")' "$SETTINGS"
  [ "$status" -ne 0 ]
}

@test "settings: allowWrite carries no '**' glob (they compile literally = dead grants)" {
  # Filesystem sandbox paths support only /, ~/, ./ prefixes — '**' is matched
  # as literal characters, never expanded. Past attempts to bridge external
  # worktree .git writes with ~/**/.git and ~/**/node_modules were dead entries
  # (probe-verified): they granted nothing and falsely implied external
  # worktrees were supported. The supported path is the nested
  # .claude/worktrees/<name> layout, writable via the cwd "." root. Keep
  # allowWrite glob-free so no dead entry re-creates that false expectation.
  run jq -e '.sandbox.filesystem.allowWrite | any(test("\\*\\*"))' "$SETTINGS"
  [ "$status" -ne 0 ]
}

@test "settings: denyWrite covers credential + global-git-exec surfaces" {
  sjq '.sandbox.filesystem.denyWrite | index("~/.claude/.credentials.json")'
  sjq '.sandbox.filesystem.denyWrite | index("~/.claude.json")'
  # Global git config only (per-repo .git/config/hooks are intentionally NOT
  # denied — that would break git clone/init, which create them, and git runs
  # sandboxed here so a planted per-repo hook is already sandbox-contained).
  sjq '.sandbox.filesystem.denyWrite | index("~/.gitconfig")'
  sjq '.sandbox.filesystem.denyWrite | index("~/.config/git/config")'
  sjq '.sandbox.filesystem.denyWrite | index("/opt/homebrew/bin")'
  sjq '.sandbox.filesystem.denyWrite | index("~/.cargo/credentials.toml")'
  # ~/.ssh: private keys + config are tamper targets (swap signing key /
  # redirect a host). Defense-in-depth alongside the allowlist (it has no
  # allowWrite entry, like ~/.gitconfig) — does NOT touch the signing socket,
  # which is governed by allowUnixSockets, so git commit signing still works.
  sjq '.sandbox.filesystem.denyWrite | index("~/.ssh")'
}

@test "settings: ~/.ssh write-tamper is mirrored in denyWrite AND Edit()" {
  # The Edit/Write tools bypass the sandbox, so denyWrite alone is half-open —
  # Edit() must mirror it or Claude could rewrite ~/.ssh/config or plant a key.
  sjq '.sandbox.filesystem.denyWrite | index("~/.ssh")'
  sjq '.permissions.deny | index("Edit(~/.ssh/**)")'
}

@test "settings: per-repo .git config/hooks carry NO deny of any kind (clone/init/lefthook must work)" {
  # Not in sandbox denyWrite (would break clone/init), AND not as Edit()
  # rules either: Claude Code MERGES Edit(...) deny paths into the sandbox
  # denyWrite (settings schema: \"Merged with paths from Edit(...) deny
  # permission rules\"), so an Edit() deny here blocked lefthook's hook-stub
  # sync and git maintenance/clone .git/config writes despite the
  # deliberately-clean sandbox list. Verified live 2026-06-09.
  run jq -e '.sandbox.filesystem.denyWrite | any(. == "~/**/.git/config" or . == "~/**/.git/hooks/**")' "$SETTINGS"
  [ "$status" -ne 0 ]
  run jq -e '.permissions.deny | any(test("\\.git/(config|hooks)"))' "$SETTINGS"
  [ "$status" -ne 0 ]
}

@test "settings: denyWrite/Edit do NOT lock the git-tracked repo policy files" {
  # Locking these breaks git/sync and dotfiles maintenance — must stay absent.
  # Absolute Edit(//...) rules are fine for non-repo paths (/opt/homebrew
  # mirrors); what must never appear is one targeting the dotfiles repo.
  run grep -E 'Edit\(//[^)]*dotFiles|dotFiles/(dot-claude|hooks|dot)' "$SETTINGS"
  [ "$status" -ne 0 ]
}

@test "settings: credential read-deny is mirrored in both sandbox denyRead and Read()" {
  # .credentials.json
  sjq '.sandbox.filesystem.denyRead | index("~/.claude/.credentials.json")'
  sjq '.permissions.deny | index("Read(~/.claude/.credentials.json)")'
  # whole ~/.ssh (covers non-id_* keys)
  sjq '.sandbox.filesystem.denyRead | index("~/.ssh")'
  sjq '.permissions.deny | index("Read(~/.ssh/**)")'
  # arbitrary .env.* suffixes
  sjq '.sandbox.filesystem.denyRead | index("**/.env.*")'
  sjq '.permissions.deny | index("Read(**/.env.*)")'
  # docker / cargo creds
  sjq '.sandbox.filesystem.denyRead | index("~/.docker/config.json")'
  sjq '.permissions.deny | index("Read(~/.docker/config.json)")'
}

@test "settings: .env templates are carved back IN for read (allowRead within the .env.* deny)" {
  # The broad `**/.env.*` denyRead also catches non-secret templates
  # (.env.example/.template/.sample). Those must be readable or sandboxed
  # tooling (e.g. `git status` over a repo that tracks apps/*/.env.example)
  # fails with "Operation not permitted". Claude compiles these allowRead
  # entries into the profile's read.allowWithinDeny list; this pins that the
  # carve-outs are declared and can't be silently dropped by a future edit.
  sjq '.sandbox.filesystem.denyRead  | index("**/.env.*")'
  sjq '.sandbox.filesystem.allowRead | index("/**/.env.example")'
  sjq '.sandbox.filesystem.allowRead | index("/**/.env.template")'
  sjq '.sandbox.filesystem.allowRead | index("/**/.env.sample")'
}

@test "settings: destructive dev ops are ask-gated, not hard-denied" {
  for rule in "Bash(git reset --hard *)" "Bash(git clean *)" "Bash(git commit --amend*)" \
              "Bash(gh release delete*)" "Bash(npm publish*)" "Bash(bun publish*)"; do
    # present in ask
    jq -e --arg r "$rule" '.permissions.ask | index($r)' "$SETTINGS" > /dev/null
    # absent from deny
    run jq -e --arg r "$rule" '.permissions.deny | index($r)' "$SETTINGS"
    [ "$status" -ne 0 ]
  done
}

@test "settings: low-friction gh exfil verbs are discouraged" {
  sjq '.permissions.deny | index("Bash(gh gist *)")'
  sjq '.permissions.deny | index("Bash(gh alias set*)")'
  sjq '.permissions.ask  | index("Bash(gh api *)")'
}

@test "settings: keychain Mach lookups kept (needed for gh/git keychain auth)" {
  # These are required so keychain-backed gh/git credential resolution works
  # under the sandbox — especially now that the GitHub PAT is no longer
  # exported and the github MCP relies on gh keychain auth. Removing them
  # broke credential access in testing, so they stay.
  sjq '.sandbox.network.allowMachLookup | index("com.apple.SecurityServer")'
  sjq '.sandbox.network.allowMachLookup | index("com.apple.securityd.systemkeychain")'
}

@test "settings: strict sandbox posture is pinned (enabled, failIfUnavailable, hatch closed)" {
  sjq '.sandbox.enabled == true'
  sjq '.sandbox.failIfUnavailable == true'
  # The load-bearing one: false means a sandbox-blocked command hard-fails
  # (the dangerouslyDisableSandbox retry is ignored). The documented hatch
  # workflow is "flip to true for a named tool, run it, flip back" — this
  # assert is what catches a forgotten flip-back at the next commit.
  sjq '.sandbox.allowUnsandboxedCommands == false'
}

# Mirror convention (CLAUDE.md): the Read/Edit tools bypass the sandbox, so
# every sandbox.filesystem deny entry needs a permissions.deny mirror —
# byte-identical for file/glob entries, /** suffix for directories. Derive
# the expected mirror for EVERY entry instead of spot-checking a few.
@test "settings: every denyRead entry has a Read() mirror in permissions.deny" {
  local e
  while IFS= read -r e; do
    jq -e --arg p "$e" \
      '.permissions.deny as $d
       | (($d | index("Read(" + $p + ")")) != null)
         or (($d | index("Read(" + $p + "/**)")) != null)' \
      "$SETTINGS" > /dev/null \
      || { echo "missing Read() mirror for denyRead entry: $e" >&2; false; }
  done < <(jq -r '.sandbox.filesystem.denyRead[]' "$SETTINGS")
}

@test "settings: every denyWrite entry has an Edit() mirror in permissions.deny" {
  # Absolute sandbox paths (/opt/...) take the absolute-anchor Edit form
  # (Edit(//opt/...)); ~ and glob entries mirror as-is.
  local e p
  while IFS= read -r e; do
    case "$e" in
      /*) p="/$e" ;;
      *) p="$e" ;;
    esac
    jq -e --arg p "$p" \
      '.permissions.deny as $d
       | (($d | index("Edit(" + $p + ")")) != null)
         or (($d | index("Edit(" + $p + "/**)")) != null)' \
      "$SETTINGS" > /dev/null \
      || { echo "missing Edit() mirror for denyWrite entry: $e" >&2; false; }
  done < <(jq -r '.sandbox.filesystem.denyWrite[]' "$SETTINGS")
}

# Reverse mirror: enforcement above is one-directional (sandbox → permission
# mirror). The reverse closes the loop: every Read()/Edit() deny must have a
# sandbox counterpart, so a permission deny can't silently lose its
# Bash-subprocess backstop. There are no \"Edit-only\" rules: Claude Code
# merges Edit() deny paths into the sandbox denyWrite, so an unmirrored
# Edit() rule is really an undocumented sandbox rule (the .git config/hooks
# pair was removed for exactly that reason — see the test above). The
# allowlist stays as the mechanism for any future deliberate exception.
EDIT_ONLY_ALLOWLIST='[]'

@test "settings: every Read() deny has a sandbox denyRead counterpart" {
  local rule path
  while IFS= read -r rule; do
    # Strip Read( ... ) and the directory /** suffix to recover the sandbox form.
    path="${rule#Read(}"
    path="${path%)}"
    path="${path%/\*\*}"
    jq -e --arg p "$path" \
      '.sandbox.filesystem.denyRead | index($p)' "$SETTINGS" > /dev/null ||
      { echo "Read() deny without denyRead counterpart: $rule" >&2; false; }
  done < <(jq -r '.permissions.deny[] | select(startswith("Read("))' "$SETTINGS")
}

@test "settings: every Edit() deny has a denyWrite counterpart (allowlisted extras aside)" {
  local rule path
  while IFS= read -r rule; do
    # Intentional Edit-only extras are allowlisted above.
    if jq -e --arg r "$rule" --argjson a "$EDIT_ONLY_ALLOWLIST" \
      '$a | index($r)' > /dev/null <<< 'null'; then
      continue
    fi
    path="${rule#Edit(}"
    path="${path%)}"
    path="${path%/\*\*}"
    # Absolute-anchor Edit(//x) rules map to sandbox /x.
    case "$path" in
      //*) path="${path#/}" ;;
    esac
    jq -e --arg p "$path" \
      '.sandbox.filesystem.denyWrite | index($p)' "$SETTINGS" > /dev/null ||
      { echo "Edit() deny without denyWrite counterpart: $rule" >&2; false; }
  done < <(jq -r '.permissions.deny[] | select(startswith("Edit("))' "$SETTINGS")
}

# Doctor carries the live-scope merge audit: scope allows that defeat tracked
# ask/deny gates (exact-rule duplicates and shell-wrapper allows) must warn.
@test "doctor: audits live permission scopes against tracked gates" {
  grep -q 'Claude permission scopes' "$ROOT/doctor"
  grep -q 'defeats every tracked Bash ask/deny gate' "$ROOT/doctor"
  grep -q 'duplicates a tracked ask/deny rule' "$ROOT/doctor"
  grep -q 'settings.local.json exists' "$ROOT/doctor"
}
