# De-dotctl: Replace the Rust binary with structured shell scripts

**Date:** 2026-06-03
**Status:** Design — pending user review
**Branch:** `worktree-dedotctl`

## Goal

Remove the `dotctl` Rust binary entirely and reimplement its behavior as
isolated, shareable, composable shell scripts organized by topic, fronted by a
single thin dispatcher. No `cargo`, no `dotctl/` directory, no Rust toolchain
dependency in the bootstrap path.

The previous (pre-dotctl) regime was a pile of `install/*.sh` + `sync.sh` +
`scripts/theme.sh`. This rewrite returns to shell but with stronger isolation:
each subsystem is one folder, each script is independently runnable, and shared
logic lives in sourceable helper libraries rather than being copy-pasted.

## Decisions (from brainstorming)

| Decision | Choice |
|----------|--------|
| Scope | **All five subsystems** — installer, prompt, statusline, hooks, render |
| Layout | **Topic dirs, self-contained** — `shared/`, `install/`, `prompt/`, `statusline/`, `hooks/`, `render/` |
| Prompt/statusline fidelity | **Pixel-identical** — reproduce every glyph, gradient pip, marker collision, OSC8 link, daily-cost line |
| Entrypoint | **Thin `dot` dispatcher** on PATH; topic scripts are standalone but `dot <area> <cmd>` is the front door |
| JSON / math tooling | `jq` (already a managed mise tool), `awk` (system) for float math, `gdate` (coreutils) for ms timestamps |
| Shell dialect | `bash` (`#!/usr/bin/env bash`, `set -euo pipefail`) for all scripts — matches the existing shellcheck/shfmt lefthook tooling. The sourced zsh prompt fragments under `zsh/` stay zsh. |

## Non-goals

- No behavior changes to the visible prompt, statusline, or hook decisions.
  This is a port, not a redesign.
- No change to `mise.toml` / `Brewfile` packaging policy.
- No change to the symlink mapping (same source→dest pairs as today).
- No new managed tools beyond what's already installed.

## Target directory layout

```
dot*                     # thin dispatcher (the ONE command on PATH)
bootstrap.sh             # rewritten: no rustup/cargo; clone → ./dot sync
doctor*                  # read-only health check (top-level command)
render*                  # op:// template resolver (top-level command)

shared/                  # cross-cutting sourceable libs (NOT executable)
  log.sh                 # info/warn/err/section, color helpers
  os.sh                  # os_kind (darwin|linux), host_id (air|pro|unknown)
  paths.sh               # resolve_dotfiles_dir, xdg_cache_home, etc.
  symlink.sh             # link() idempotent symlink w/ mode + .bak backup
  json.sh               # jq field helpers w/ defaults
  git-cache.sh           # read+parse git-data cache into shell vars
  color.sh               # Nord palette, gradient pip math (awk), %{%}/ANSI/OSC8 wrappers
  lock.sh                # pid-based exclusive lock (sync)

install/                 # sync modules, sourced by ./dot sync in numeric order
  00-brew.sh
  10-linux.sh
  20-sheldon.sh
  30-mise.sh
  40-symlinks.sh
  50-ghostty.sh
  60-claude.sh
  70-gh.sh
  80-git-maint.sh
  85-lefthook.sh
  90-macos.sh            # macOS defaults data + apply + audit
  95-prune.sh            # .bak / stale-worktree / orphan-worker / stale-cost cleanup

sync*                    # the one orchestrator (sourced-modules driver)

prompt/
  git-data*              # gather git state → shell-sourceable cache (HOT PATH)
  prompt-render*         # cache → zsh PROMPT string (HOT PATH)

statusline/
  statusline*            # stdin CC JSON → 3–6 lines
  subagent-statusline*   # stdin CC JSON → tasks JSON

hooks/
  lock-file-guard*
  policy-guard*
  format-on-save*
  trim-bash-output*
  user-prompt-submit*
  session-start*
  stop*
```

`dotctl/` is deleted in full at the end.

## The `dot` dispatcher

~20-line bash script, the single command installed on PATH (symlinked to
`~/.local/bin/dot` by sync). Resolves `DOTFILES_DIR` once, then execs the
matching topic script:

```
dot sync [...]              → exec $DOTFILES_DIR/sync "$@"
dot update                 → exec $DOTFILES_DIR/sync --upgrade
dot doctor                 → exec $DOTFILES_DIR/doctor "$@"
dot prune [...]            → exec $DOTFILES_DIR/sync --only=prune (or install/95)
dot render <tpl>           → exec $DOTFILES_DIR/render "$@"
dot git-data               → exec $DOTFILES_DIR/prompt/git-data
dot prompt-render          → exec $DOTFILES_DIR/prompt/prompt-render
dot statusline             → exec $DOTFILES_DIR/statusline/statusline
dot subagent-statusline    → exec $DOTFILES_DIR/statusline/subagent-statusline
dot hook <event>           → exec $DOTFILES_DIR/hooks/<event>
```

`DOTFILES_DIR` resolution (mirrors `util::resolve_dotfiles_dir`): `$DOTFILES_DIR`
env → directory of the `dot` script's symlink target (`readlink -f`) → legacy
`~/dotFiles`; first candidate that is a directory containing a `Brewfile` wins.
This is the *only* place relocation logic lives.

Topic scripts remain directly runnable (`./prompt/git-data`) for development and
sharing; they source `shared/*` via a path computed from their own location.

## Subsystem ports

### 1. Installer (`sync` + `install/*` + `doctor` + `shared/`)

`sync` is a bash driver that:
- Prepends mise shims to PATH if present.
- Acquires the exclusive lock (`shared/lock.sh`, pid + `kill -0` stale check) at
  `$TMPDIR/dotfiles-sync.lock`.
- Resolves `DOTFILES_DIR`, detects OS + host.
- Parses flags: `--upgrade`, `--only=<tags>`, `--host=<air|pro>`, `-f`/`--force`,
  `-s`/`--skip`.
- Sources each `install/NN-*.sh` in numeric order; each module declares its tags
  and a `run()` body, gated by a `should_run` tag-filter helper and OS guard.
- Runs the prune pass at the end (`install/95-prune.sh`), then prints "Done!".

Each `install/NN-*.sh` is a port of the corresponding `step_*` in `sync.rs`:
brew (+ host Brewfile, docker conflict, xcode-select), linux apt, sheldon
install, mise install/upgrade/trust, symlinks (the full mapping table via
`shared/symlink.sh` `link()`), ghostty shim, claude install, gh extensions,
git maintenance, lefthook install, macOS defaults.

`shared/symlink.sh` `link()` reproduces the three `LinkMode`s
(overwrite-with-`.bak` / skip / interactive prompt) and the no-op-if-correct
check, plus mode bits (700 for `~/.ssh`, 600 for `ssh/config`). The symlink
mapping table is data (an array of `src dst [mode]` rows) consumed by
`40-symlinks.sh`.

`90-macos.sh` carries the `SHARED` defaults table (18 entries) as data, plus the
dynamic screenshot-location entry, the `expected_read` bool normalization, the
per-host overlay merge (`AIR_OVERLAY`/`PRO_OVERLAY` currently empty), the three
`killall`s, and an `audit` function for doctor.

`doctor` is a standalone read-only script reproducing all 13 checks, honoring
`DOTCTL_DOCTOR_SKIP_EXTERNAL=1` (renamed env TBD — see Open question 1), exiting
non-zero when `fails > 0`. The doc-drift scan's dead-string list gains
`dotctl`/`cargo install --path .../dotctl` and drops nothing (it already lists
`sync.sh`, `starship`, etc.).

`95-prune.sh` ports the four prune passes (backups, stale worktrees, orphan
workers, stale cost dirs) with the same `AskDefaultYes`/`AutoYes`/`DryRun`
prompt modes.

### 2. Prompt (`prompt/git-data` + `prompt/prompt-render`) — HOT PATH

`git-data` ports `git_data.rs`:
- `git rev-parse` repo detection + worktree detection.
- `git status --porcelain=v2 --branch --ahead-behind` single call, parsed in
  bash (case on entry-kind `1`/`2`/`u`/`?`), tallying conflict/staged/unstaged/
  untracked counts.
- `git remote get-url origin` → https/name derivation.
- `git stash list` count.
- PR status via `gh pr status --json ... --jq ...` with the same 60s reuse
  window (read prior cache's `GIT_PR_CHECKED_AT`).
- Writes the same `GIT_*` key set as `KEY='value'` lines, atomically (temp +
  `mv`), to `$XDG_CACHE_HOME/git-data/<hash>.sh`, dir 700 / file 600.

Cache filename hash: Rust used SHA-256 truncated to 12 chars. Shell uses
`shasum -a 256` (or `sha256sum` on Linux) on the toplevel path, first 12 chars.
**This changes the cache filename**, but that's invisible (cache is
regenerated). `prompt-render` and `statusline` read via the same hash function
in `shared/git-cache.sh`, so they stay consistent.

`prompt-render` ports `prompt.rs`: sources the cache, emits the powerline zsh
`PROMPT` string with `%{...%}`-wrapped escapes. All Nord colors, PR-state
colors, status-pip cells, worktree cell (`STATUSLINE_WORKTREE` env first), and
the CWD `~`-substitution fallback reproduced exactly. Pure string assembly, no
subprocesses. Powerline glyphs use bash `$''`-style escapes (the repo's
documented rule: never paste raw glyphs).

**Performance note:** This is the biggest regression risk. Rust did this in
microseconds with zero forks for render; bash `git-data` already forks several
`git` processes (so does Rust), so the gather cost is comparable. `prompt-render`
is pure string work — fast enough in bash since it makes no subprocess calls.
The existing zsh caching (`git-data` only re-runs on state change, background
refresh otherwise) is preserved, so per-keystroke cost is just `prompt-render`.

### 3. Statusline (`statusline/statusline` + `subagent-statusline`)

`statusline` ports `statusline.rs` + `render.rs` bar logic:
- Reads CC JSON from stdin (jq for all ~20 fields), refreshes + loads the git
  cache.
- Reads `~/.claude/settings.json` `.advisorModel` via jq.
- Emits the same 3–6 lines: repo/branch/worktree/PR/counters/lines; model/
  advisor/effort; CTX bar; 5h + 7d rate-limit bars; cost line.
- Bar rendering (`shared/color.sh`): `DEFAULT_PIP_COUNT=30` scaled by terminal
  columns; filled `▰` / empty `▱`; **per-pip blackbody gradient color computed
  in awk** (this is the heavy math — pixel-identical means porting the exact
  gradient formula); marker pip (amber autocompact / blue clock); yellow
  projection pip with the same blue-wins-the-cell collision rule.
- Daily cost: writes `~/.claude/state/cost/<date>/<session_id>`, sums the date
  dir, displays cross-session total under the same threshold rule.

`subagent-statusline` ports `subagent_statusline.rs`: maps task `status`→`state`
strings, computes `elapsed` from `startTime` epoch ms vs `gdate +%s%3N` now,
compact vs normal formatting by columns, token formatting (`1.0k`/`1.0M`),
passes `tokenSamples` through, emits `{"tasks":[...]}` via jq.

**Performance note:** Statusline runs on a 10s refresh interval (not
per-keystroke), so the awk gradient cost is acceptable. The exact blackbody
gradient port is the single largest piece of new shell code and the main
correctness risk; it gets dedicated tests (see Testing).

### 4. Hooks (`hooks/*` — one script per event)

Each hook is a standalone bash script reading CC JSON from stdin via jq,
emitting the same structured JSON responses (exit 0 + JSON for structured
deny/context/updated-output; exit 2 reserved for legacy block).

- `lock-file-guard`: file_name against the 13-name list → deny JSON.
- `policy-guard`: the 6 git-policy patterns. **Regex moves from Rust `regex` to
  bash `[[ =~ ]]`** (force-push w/ force-with-lease exemption, amend, no-verify,
  no-gpg-sign, branch-delete advisory). Only fires when `tool_name == "Bash"`.
- `format-on-save`: extension routing (`.sh`→shfmt; ts/js→prettier+eslint;
  css→prettier), each formatter skipped if absent (`command -v`); eslint stdout
  surfaced as `additionalContext`.
- `trim-bash-output`: 20k threshold, spill full stdout to
  `/tmp/claude/spills/<session>/<ts>.txt`, trim to 200+100 lines or 8000+4000
  chars, emit `hookSpecificOutput.updatedToolOutput`. JSON manipulation via jq.
- `user-prompt-submit`: repo-root lookup, 60s-stale cache check → detached
  `dot git-data &` refresh, suppress on clean default branch, else emit the
  `git: ...` summary line.
- `session-start`: `<repo>:<branch>` title via `hookSpecificOutput.sessionTitle`.
- `stop`: append session JSONL record.

Optional `DOTCTL_HOOK_TIMING=1` jsonl logging is ported (env name TBD — Open
question 1).

### 5. Render (`render`)

Ports `render.rs`: read template, find `{{ op "op://..." }}` placeholders,
dedupe, resolve each via `op read`, fail loudly on first miss, write to stdout.
Bash regex + an associative-array dedupe.

## External references to update (s/dotctl/dot/)

- `dot-claude/settings.json`: 7 hook commands, `statusLine.command`,
  `subagentStatusLine.command`, and the `permissions.allow` entry (`dotctl` →
  `dot`). Also `sandbox.excludedCommands` per the CLAUDE.md gotcha (add `dot`).
- `zsh/50-prompt.zsh`: `dotctl git-data` / `dotctl prompt-render` → `dot ...`.
- `zsh/70-aliases.zsh`: `env-sync`/`env-doctor` aliases → `dot sync`/`dot doctor`.
- `lefthook.yml`: `pre-push.doctor` → `dot doctor` (skip-external env); **remove
  `pre-push.cargo-test`** (no more Rust).
- `bootstrap.sh`: remove rustup + cargo install; `git clone … && ./dot sync`
  (symlink `dot`→`~/.local/bin` happens inside sync's symlink module, but
  bootstrap needs a pre-sync way to invoke it — run `"$DOTFILES_DIR/dot" sync`
  directly).
- `mise.toml`, `helix/languages.toml`, `dot-claude/commands/*`,
  `dot-claude/agents/bash-hardener.md`: comment/doc updates; the
  `add-dotctl-hook` command is rewritten to scaffold a shell hook (or removed).
- `CLAUDE.md`: rewrite the dotctl-centric architecture sections to describe the
  shell layout. (Large doc edit; part of the final step.)

## Testing strategy

The Rust suite (`cargo nextest`) disappears. Replacement:

- **bats** (Bash Automated Testing System) for unit-level coverage of the
  pure-logic pieces that had Rust tests: `policy-guard` pattern matching,
  `lock-file-guard` name matching, the git-porcelain-v2 parser, the gradient
  pip-color function, `expected_read` normalization, the symlink `link()` mode
  branches, `trim-bash-output` thresholds, the cache hash. bats is added to
  `mise.toml`.
- **Golden tests** for pixel-identical output: capture current `dotctl
  statusline` / `dotctl prompt-render` output for a set of canned JSON/cache
  inputs *before* deleting the binary, store as golden fixtures, assert the
  shell ports match byte-for-byte.
- `dot doctor` itself remains the integration smoke test.
- `lefthook.yml` pre-push runs `bats` + `dot doctor` instead of cargo.

## Migration / sequencing

1. Capture golden fixtures from the current Rust binary (statusline,
   prompt-render, git-data cache) before touching anything.
2. Build `shared/` libs + `dot` dispatcher.
3. Port installer (`sync` + `install/*` + `doctor`), keep Rust hooks/prompt/
   statusline live meanwhile.
4. Port prompt (`git-data` + `prompt-render`); switch zsh refs; verify against
   golden + live.
5. Port statusline + subagent; switch settings.json refs; verify against golden.
6. Port hooks one at a time; switch each settings.json ref; verify decisions.
7. Port `render`.
8. Flip `bootstrap.sh`, `lefthook.yml`, aliases, remaining doc refs.
9. Delete `dotctl/`, remove cargo-test hook, update `CLAUDE.md` + README.
10. Full `dot sync` on this host + `dot doctor` green.

Each step keeps the system bootable: the old Rust binary stays installed until
its subsystem's shell replacement is verified, so a half-finished port never
breaks the prompt or hooks.

## Resolved defaults (override any of these if you disagree)

1. **Env var names → rename to `DOTFILES_*`.** `DOTCTL_HOST` → `DOTFILES_HOST`,
   `DOTCTL_DOCTOR_SKIP_EXTERNAL` → `DOTFILES_DOCTOR_SKIP_EXTERNAL`,
   `DOTCTL_HOOK_TIMING` → `DOTFILES_HOOK_TIMING`. One-time grep-and-replace;
   `dotctl` ceases to exist so the prefix shouldn't linger. (`DOTFILES_DIR` is
   already that prefix.)
2. **`prune` stays a command.** `dot prune` wraps a standalone entry in
   `install/95-prune.sh` (it's used interactively, not just at sync tail).
3. **`add-dotctl-hook` → rewritten as `add-hook`.** Scaffolds a new
   `hooks/<event>` shell script and wires it into `settings.json`.

These are defaults baked into the plan; say so if you want any flipped.
```

