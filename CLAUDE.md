# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS dotfiles repository owned end-to-end by a handful of **shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, and apply macOS defaults. The shell prompt is [starship](https://starship.rs) (config in `starship.toml`). The Claude Code statusline lives in its own repo (`github.com/alxjrvs/claude-statusline`). Just `bash`, `git`, and `jq`.

Each subsystem lives in its own topic folder. The helpers shared by the standalone scripts (`os_kind`, `resolve_dotfiles_dir`, and the `link()` symlinker) live in one small **`lib/common.sh`**, sourced by `sync` and `doctor`.

Source of truth for setup behavior is `sync` + `install/*.sh`. The shell prompt is starship (`starship.toml`, symlinked to `~/.config/starship.toml`). The Claude Code statusline is a separate project (`github.com/alxjrvs/claude-statusline`). `install/60-claude.sh` (claude tag) clones it **beside the dotfiles repo** (sibling of `$DOTFILES_DIR`, so it travels with the repo across moves rather than a hardcoded `~/Code` path) and runs its `install.sh`, which symlinks `claude-statusline` + `claude-subagent-statusline` into `~/.local/bin`; `dot-claude/settings.json` references those paths.

## Northern Principles

One North Star: **small, exemplary, easily shareable — a senior engineer's showpiece, not an over-engineered personal artifact.** The principles below are the compass headings that point there; every concrete rule, policy, and guardrail in this file is downstream of one of them. They are the *why* behind the *what* — when you face a decision no rule covers, derive the answer from these. When a specific rule and a principle appear to collide, **surface the tradeoff to the owner rather than silently keeping the bespoke thing.**

1. **Native over special.** Prefer a tool's stock behavior to bespoke machinery wrapped around it; deleting custom code in favor of a built-in is the highest-value change you can make here. Configs carry only *intentional divergences* from defaults, in the idiomatic form — never a line that merely restates a default. (This is why the prompt is stock starship, the editor is a single plugin-free `init.lua`, and `settings.json` is deliberately minimal.)

2. **Guilty until proven load-bearing.** Every dependency, wrapper, convention, and line of config must earn its weight on a *personal* repo. Nothing stays because it's "best practice" — ceremony justifies itself by what it prevents, or it goes. When in doubt, cut and see what breaks. Protected, never cut without asking: `brew`, `neovim`, `ghostty`.

3. **No gratuitous wrappers.** Don't wrap a command just to re-expose it — call tools natively (`op run --`, `eval "$(starship init zsh)"`). Keep *only* the shims an external program execs by path with no native alternative: `git-ssh-sign` (1Password commit signing) and `gh-mcp-auth-header` (GitHub MCP `headersHelper`). A shim that merely forwards is a smell. (Agent git auth deliberately uses the *stock* `osxkeychain` helper, not a custom shim — see Secrets.)

4. **One config, every machine.** No host detection, no per-host overlay. If a genuine per-machine divergence appears, add the *smallest possible guard at that point* — never a host-overlay system built preemptively. (Machine-local escape hatches that already exist: `~/.gitconfig.local` for signing, `DOTFILES_DIR` for relocation.)

5. **Standard, and agentic-enabled.** 1Password, Git, SSH, `gh`, and the MCP wiring stay stock installs — but wired for agents end-to-end (op MCP, op SSH agent, GitHub MCP, the on-demand auth shims). Secrets resolve through `op` on demand, never plaintext, never exported to env or written to disk.

6. **Keep it legible.** Plain integer ops over clever math; if the math turns obscure, drop the feature instead. One small shared `lib/common.sh` over duplicated inline helpers. Docs explain the *decision and the gotcha* — the *what* is already in the code, so don't restate it.

The sections that follow (Packaging policy, Terminal stack, One config, Secrets, Guardrails) are this repo's de-facto ADRs — each is a principle made concrete. There are no separate ADR files by design: the decision lives next to the thing it governs.

## Key Commands

```bash
dot sync                # Idempotent install/resync. Fast on no-op.
dot sync --upgrade      # Same + brew update/upgrade/cleanup + mise upgrade.
dot sync --only=brew,mise   # Only the listed section tags.
dot update              # Bump everything (equivalent to sync --upgrade).
dot sync --dry-run      # Mutate nothing; print what each module WOULD do.
dot doctor              # Read-only health check. Exit: 0 clean, 1 failures, 2 warnings only.
dot doctor --fix        # Same + repair symlinks: reap orphans, relink missing/incorrect.
dot doctor --full       # Same + a full-history gitleaks scan (slow, on-demand).
dot watchtower          # Local 1Password security audit via the op CLI (foreground only).
lefthook run pre-commit # shellcheck + shfmt -i 2 -ci -sr over staged shell files.
mise x -- bats test/    # Run the lib/common.sh unit tests.
```

Fresh machine: `git clone … ~/dotFiles && ~/dotFiles/bootstrap.sh` (execs `dot sync`).

## Architecture

### The `dot` dispatcher + topic folders

`dot` (repo root) is a short bash script — the single command on `PATH` at `~/.local/bin/dot`, installed there as a **copy** (not a symlink, so it survives a repo move — see Gotchas). It resolves `DOTFILES_DIR` once, then execs the matching topic script, passing args through:

| Subcommand | Execs | Purpose |
|------------|-------|---------|
| `dot sync` | `./sync` | Install/resync. Tag-gated steps (`--only=<tag,...>`). Idempotent. |
| `dot update` | `./sync --upgrade` | Bump everything. |
| `dot doctor` | `./doctor` | Read-only diagnostics; exits non-zero on failures. `--fix` repairs the symlink contract (reap orphans + relink missing/incorrect) — doctor's only mutation. |
| `dot watchtower` | `./watchtower` | Local "Watchtower"-style 1Password audit (breached/reused/weak/unsecured) built on the `op` CLI. Reads passwords locally, emits only hashes/metadata. Dev creds (localhost/`.local`/LAN URL, or the `watchtower-ignore` tag) are listed separately, never flagged. Foreground only (op desktop-auth needs the calling session); `--vault=NAME`, `--no-breach`. |
| `dot ws` | `./cmux/mirror` | Mirror `~/Code` into cmux workspaces (`ws` = workspace): crawl until repos, repos become workspaces (a repo is a leaf — worktrees never become workspaces), each top-level folder of repos becomes one flat cmux group (created via the `workspace-group` CLI — cmux has no auto-by-directory grouping; the group is anchored with a terminal at the folder). Each new group and flat top-level repo gets a *unique* color from cmux's palette (never repeated, never colliding with one already in the sidebar), and a group's members are shaded from that group's color so they read as one family (any `gnar`-named item — the owner's brand — is themed orange instead). Interactive top-down (`workspace?`/`group?`); repos already *covered* by any existing workspace (at or inside the repo, incl. custom setups) are skipped, `Legacy` folders default-skip. `--target-dir D` (mirror `D` instead of `~/Code`), `--target-ws W` (migrate only the single folder `W` — repo→workspace, folder→group; mutually exclusive with `--hard`), `--headless` (create all new, skip Legacy), `--hard` (archive all existing workspaces into an "Archive" group, then mirror exactly), `--dry-run`. `--app claude\|cmux` picks the backend the same crawl feeds (default `claude`): `claude` launches one idle `claude --bg` background agent per repo (auto permission mode, ready in `claude agents`) — flat, no groups/colors; coverage reads live background sessions via `claude agents --json`; `--prompt T` seeds each session with a task instead of leaving it idle; `--hard` is rejected (no archive concept). `--app claude` needs the agent view enabled; `--app cmux` needs a running cmux (drives it over the control socket). |

`DOTFILES_DIR` resolution lives only in `dot`: `$DOTFILES_DIR` env → the script's own dir (in-repo `./dot`) → the breadcrumb `sync` records at `${XDG_STATE_HOME:-~/.local/state}/dot/dir` (the path the on-PATH copy uses, since its own dir is `~/.local/bin`, not the repo) → fallback `~/dotFiles`; first candidate that is a directory containing a `Brewfile` wins. The top-level scripts (`sync`, `doctor`) are standalone — run them directly for development. The `install/NN-*.sh` modules are **sync-sourced, not standalone**: `sync` sources `lib/common.sh` (which defines `link()` alongside the other shared helpers), then exports those helpers (`os_kind`, `resolve_dotfiles_dir`, `link`) before sourcing each module, so the modules carry no helpers of their own.

### sync / install modules

`sync` sources `install/NN-*.sh` modules in numeric order; each declares its tags and a `run` function, gated by a tag filter (`--only=<tags>`). Modules: `00-brew 30-mise 40-symlinks 45-ssh 47-op-agent 60-claude 85-lefthook 90-macos`. To add a sync section, add an `install/NN-name.sh` module, give it a tag, and `sync` will pick it up. macOS defaults data + `audit` live in `90-macos.sh`. (`30-mise` also locks sheldon plugins — sheldon is a mise tool, so its binary only exists after `mise install`.)

### Symlink Model

`link()` (defined in `lib/common.sh`, exported by `sync` to the install modules, and reused by `dot doctor --fix`) creates idempotent symlinks. On conflict, behavior depends on `$LINK_MODE`: `overwrite` (replace, set via `-f`), `skip` (`-s`), or default `interactive` (prompt). Overwrite does not back up the displaced file — the canonical content is in this git repo. Mapping:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile`, `.zshenv`, `.hushlogin` | `~/` |
| `.gitconfig`, `.gitmessage`, `.gitignore`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `zsh/[0-9]*.zsh` | `~/.config/zsh/` (sourced in numeric order by thin `.zshrc`) |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` (tools only) |
| `mise-settings.toml` | `~/.config/mise/conf.d/settings.toml` (global-only `[settings]`; mise loads `conf.d/*` only as global, so `trusted_config_paths` isn't ignored+warned the way it is when `mise.toml` is read as this repo's project-local config) |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `starship.toml` | `~/.config/starship.toml` |
| `cmux/cmux.json` | `~/.config/cmux/cmux.json` (cmux app config; rendering comes from `ghostty/config`) |
| `ghostty/config` | `~/.config/ghostty/config` (cmux's terminal-rendering layer; fixed path) |
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
| `karabiner/karabiner.json` | `~/.config/karabiner/karabiner.json` |
| `atuin/config.toml` | `~/.config/atuin/config.toml` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` (mode 600) |
| `ssh/1password-agent.toml` | `~/.config/1Password/ssh/agent.toml` |
| `gh/gh-mcp-auth-header` | `~/.local/bin/gh-mcp-auth-header` (github MCP headersHelper → `op read`) |
| `render/render-mcp-auth-header` | `~/.local/bin/render-mcp-auth-header` (Render MCP headersHelper → `op read`) |
| `git-template/hooks/pre-commit` | `~/.config/git/template/hooks/pre-commit` (copied into new repos via `init.templateDir`) |
| `dot-claude/{CLAUDE.md, settings.json}` | `~/.claude/` (individually) |

Everything here is symlinked — every destination traces back to a file in this repo. The lone exception is `~/.local/bin/dot`, which `sync` installs as a **copy** (plus a breadcrumb) so the dispatcher keeps working even if the repo dir moves — see the `dot` survives a repo move gotcha.

### Claude Code Configuration (`dot-claude/`)

Each entry is symlinked individually into `~/.claude/` by `dot sync` (claude tag):

- `CLAUDE.md` — user-level global instructions (identity, preferences).
- `settings.json` — **deliberately minimal**; it carries only deliberate divergences from Claude Code defaults, enumerated in `dot-claude/CLAUDE.md` (the canonical list — don't restate it here). Don't add settings without asking.

Don't add `agents/`, `commands/`, or `hooks/` directories without asking — `dot-claude/` stays at these two symlinked files plus `REFERENCE.md`.

### Linting & tests

Three lightweight automation layers:

- **pre-commit** (`lefthook.yml`, installed by `dot sync` lefthook tag): `shellcheck` + `shfmt -i 2 -ci -sr` + `gitleaks protect` + a `settings.json` validity check over staged shell files.
- **commit-msg** (`lefthook.yml`): rejects throwaway subjects (bare `WIP`/`wip` or a single character) so they don't enter permanent history. Commit convention is `scope: summary` or `type(scope): summary` (e.g. `feat(mcp): …`, `docs+chore: …`). Bypass once with `git commit --no-verify`.
- **CI** (`.github/workflows/lint.yml`): mirrors the pre-commit gate (shellcheck/shfmt/gitleaks/settings) and runs the `bats` unit tests on push to `main` and on PRs. Lint only — never runs `dot sync` or mutates anything.

Tests live in `test/` (`bats`): `test/common.bats` covers the `lib/common.sh` helpers (`link`, `os_kind`, `resolve_dotfiles_dir`). Run locally with `mise x -- bats test/`. The surface is deliberately small — `lib/common.sh` has the highest fan-in (sourced by `sync`, `doctor`, `watchtower`), so that's where a unit test earns its weight; the installer modules stay verified by `dot sync --dry-run` rather than a heavier harness.

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

Brewfile holds **only**: `mise` (chicken-and-egg bootstrap), casks (GUI apps, fonts), and any system library that has no mise equivalent.

`mise.toml` holds: all language toolchains AND all dev CLIs (including `jq`, `shellcheck`, `shfmt`). Use the registry short-name where it resolves; fall back to `aqua:` then `github:` backends.

If you're about to add a CLI to `Brewfile`, stop — put it in `mise.toml` unless it's `mise` itself or it's a cask.

## Terminal: cmux (canonical), Ghostty (embedded engine)

`cmux` is the canonical terminal — set via `TERMINAL=cmux` in
`zsh/00-exports.zsh`. It's a libghostty-based agent multiplexer for
running parallel Claude Code sessions with vertical tabs and git-worktree
isolation. macOS has no system "default terminal" role, so the env var is
a declaration of intent (the XDG convention), not a hard switch; launch
cmux directly (Dock/Raycast).

cmux config is **split across two files, both symlinked by `dot sync`**:

- **`cmux/cmux.json`** → `~/.config/cmux/cmux.json` — cmux's own app config
  (sidebar, shortcuts, automation, notifications). Carries *intentional
  divergences only* (currently just `app.sendAnonymousTelemetry = false`);
  every omitted key falls back to cmux's in-app default, so the file stays
  small. `settings.json` is a legacy read-only fallback — don't manage it.
  This is the "portable cmux" piece: it now travels with the repo.
- **`ghostty/config`** → `~/.config/ghostty/config` — terminal *rendering*
  (theme/font/colors). cmux embeds libghostty and reads this from a **fixed
  path with no override**, so the file must live at the Ghostty path even
  though cmux owns it. cmux honors only the visual subset — keybinds and the
  quick-terminal visor are Ghostty.app-only and were dropped from the file.

Ghostty is kept installed purely as the **embedded rendering engine** (the
`ghostty` cask provides libghostty), not a separate daily driver. `dot
doctor` validates both symlinks via the generic `_symlink_pairs` audit.

The third cmux piece is **`cmux/mirror`** (run as `dot ws`, for *workspace*): it
populates the sidebar by mirroring `~/Code` — crawling until it hits git repos,
turning repos into workspaces and each top-level folder of repos into one flat
cmux group.
Groups are created explicitly via the `workspace-group` CLI (cmux has **no**
auto-by-directory grouping), anchored with a terminal at the folder; cmux
groups are flat, so nested folders collapse into their top-level group. Each
created top-level item (group or flat repo) gets a *unique* color from cmux's
palette (`workspace-group set-color` / `workspace-action set-color`) — never
repeated and never colliding with a color already in the sidebar (it seeds the
used set from the live `custom_color`s) — and each group's members are shaded
from that group's color (lightness-spread, plain integer math) so they read as
one color family. The one exception: any `gnar`-named item (the owner's brand,
gnar.dog) is always themed orange (`#FF8000`, the claude-statusline's orange)
instead of a palette color, so the brand reads consistently. A repo is a
**leaf**: the crawl stops there, so worktrees (`.claude/worktrees`,
`.worktrees`) and submodules never spawn stray workspaces. It's *generated per
machine, not stored* — it reads the local `~/Code` and drives the running cmux
over its control socket, so it honors "one config, every machine" without
baking any host's repo list into the repo (that's why this is a runtime
command, not portable cmux state). It first scans the existing workspace config
and skips any repo already *covered* — a workspace at or inside the repo, so
hand-made/custom setups count, not just exact `~/Code` mirrors. Interactive by
default (asks `workspace?`/`group?` top-down; `Legacy` folders default-skip; an
existing group is filled in without asking, so only brand-new groups prompt),
with `--headless` (create all new, skip Legacy), `--hard` (archive every
existing workspace into an "Archive" group, then mirror `~/Code` exactly,
ignoring coverage — nothing is lost, the prior set is just parked out of the
way), and `--dry-run`. Two scope flags narrow the target: `--target-dir D`
mirrors `D` instead of `~/Code` (overrides `$CODE_DIR`), and `--target-ws W`
migrates just the one folder `W` (absolute, or relative to the target dir) —
a repo becomes a workspace, a folder of repos becomes a group — instead of
walking the whole tree; it's mutually exclusive with `--hard` (a full-sidebar
operation). Lives in `cmux/` beside `cmux.json`; it's a dispatcher target, not
symlinked.

`--app claude|cmux` (default `claude`) picks the **backend** the one crawl feeds —
the same `~/Code` walk, leaf rule, coverage, `Legacy`-skip, and interactive
per-repo naming drive both; only the *leaf action* differs. `--app claude`
launches **one idle `claude --bg` background agent per repo** (in `auto`
permission mode, named after the repo), so `claude agents` opens pre-populated
with every directory you want at hand. It is flat — `claude agents` has no
groups, so the cmux group/color/anchor machinery is skipped — and **coverage
reads live background sessions** (`claude agents --json`, `kind == "background"`)
rather than the cmux workspace list, so a re-run skips a repo that already has a
standby agent (a *foreground* interactive `claude` in that repo does **not**
count — you can still want a background one there). A session with no `--prompt`
is genuinely **idle** (it waits for your first message — zero tokens, nothing
runs in `auto` until you prompt it, which is why this beat seeding an
orientation turn); `--prompt T` seeds each new session with task `T` instead.
`--hard` is rejected for `--app claude` (no archive concept for agents), and
`--prompt` is rejected for `--app cmux`. The claude path needs the agent view
enabled (`disableAgentView` unset) — it gates `claude --bg` and `claude agents`
both — but no running cmux. Note the **blast radius**: `auto` mode plus a fleet
of background agents across every repo is exactly the confused-deputy surface
`dot-claude/CLAUDE.md` flags for periodic review; idle-by-default keeps it cool
until you actually dispatch work.

No other terminal emulators (iTerm2, WezTerm, Kitty, Alacritty, Warp) are
managed by this repo. The stack is exactly cmux (the terminal) plus Ghostty
(the engine under it) — one unit. If you find yourself adding a third, stop;
revisit only if Mitchell Hashimoto abandons Ghostty.

## One config, every machine

This repo runs on more than one Mac but is deliberately **single-config**:
there is no host detection and no per-host overlay. `Brewfile`,
`mise.toml`, the macOS defaults in `install/90-macos.sh`, symlinks, and zsh
fragments are identical everywhere. If a genuine per-machine divergence
ever appears, add the smallest possible guard at that point — don't
add a host-overlay system preemptively.

## Secrets management

1Password (`op`) is the source of truth for secrets. The setup follows 1Password's own two-tier model ([secure-ai-access](https://www.1password.dev/get-started/secure-ai-access), [secure-ssh-git-workflows](https://www.1password.dev/get-started/secure-ssh-git-workflows), [developer-quickstart](https://www.1password.dev/get-started/developer-quickstart)):

- **Interactive dev (you)** — 1Password desktop app + biometric unlock; resolve via `op run` / `op://` references / Environments. Tiered patterns below.
- **Hands-off agent (Claude, MCP, cron)** — a **service account** scoped to the `claude-agent` vault; no biometric, no desktop-app dependency. See *Agent secrets* below.

### Interactive patterns

(priority order; drop a tier only when the one above doesn't apply)

**1. `op run -- <cmd>` — one-shot CLI injection**
```sh
op run -- npm publish            # resolves op:// refs at exec time; masking ON
```
For any CLI invocation that reads a token from env. Nothing is exported to the shell session; `op` resolves `op://` references at exec time only. Masking is on by default (no `--no-masking`): the child gets the real resolved value but 1Password redacts it from the child's stdout/stderr, so secrets don't leak into output an agent/transcript could capture. If a tool genuinely breaks under masked output, pass `--no-masking` for that one call and note why rather than making it the default.

**2. `op://` references in config files**
```ini
# .npmrc
//registry.npmjs.org/:_authToken=op://Private/npm/credential
```
Pair with `op run --` (pattern 1) — it resolves the references just for the child process.

**3. Environments — project-local secret sets**
1Password Environments (beta) are **app/web-only — the `op` CLI cannot create or mount them** (no `op environment` command), so the CLI-native equivalent we use is: a per-project **vault** of items plus a committed `.env` of `op://` *references* (never values), resolved at launch:
```sh
op run --env-file=.env -- npm run dev   # op:// refs → child env only; nothing resolved hits disk
```
`op inject -i tpl -o out` does the same for non-`.env` config files. Only references are git-tracked. If you want the literal mounted-`.env` Environment UX, create it in the 1Password app as an optional overlay on top of this.

**4. `gh auth token` keychain resolution — GitHub specifically**
The token lives in the macOS keychain (managed by `gh auth login`, secure storage), never on disk, and is NOT exported to the environment (a standing export would leak it into every subprocess). Resolve it on demand — `GITHUB_TOKEN="$(gh auth token)" some-tool` — only when a tool actually needs it.

**5. `mise` `[env]` — project-local inheritance**
For values a project's subprocesses must inherit at fork time, put them in the project's `mise.toml` `[env]`, resolving secrets through `op` at activation:
```toml
# mise.toml
[env]
STRIPE_KEY = "{{ exec(command='op read op://Private/stripe/credential') }}"
```
mise activates on `cd` (its shims are already on PATH via `.zshenv`). For one-off commands, `op run -- <cmd>` (pattern 1) is simpler.

### Agent secrets (service account)

The agent never borrows your biometric session. `dot sync` (the `op-agent` module, `install/47-op-agent.sh`) provisions, idempotently:

- a dedicated **`claude-agent` vault** — 1Password *forbids* granting a service account access to Personal/Private, so agent secrets **must** live apart; that vault is the entire blast radius;
- a **service account** (`claude-agent-<host>`) with `read_items` on only that vault;
- its token in the **macOS login keychain** (`op-claude-agent`), never on disk, never in git.

MCP auth is a **`headersHelper` → `op read` shim** (`gh/gh-mcp-auth-header`, `render/render-mcp-auth-header`). Each shim sources the keychain token *inline* (`OP_SERVICE_ACCOUNT_TOKEN="$(security find-generic-password -s op-claude-agent -w)" op read …`), confined to that one `op` process — so neither the service-account token nor the resolved secret reaches a Bash subprocess, the transcript, or OTEL spans. The payoff: **no Touch ID prompt and no desktop-app dependency** (works headless/cron). No `claude()` wrapper. When the keychain item is absent the shim falls back to desktop biometric, so nothing breaks pre-bootstrap. Generalize the shim to any HTTP MCP server needing a bearer token; store each such secret in `claude-agent` and point `OP_REF` at `op://claude-agent/...`.

**Stdio MCP servers resolve their key via a resolver command** — for the gnar `spacebase` plugin's bundled stdio server, no `headersHelper` hook exists (Claude Code expands only `${VAR}` into a stdio plugin server's env from its own launch env). Rather than wrap the server in a launch shim and shadow it (the old approach — a separate user-scope server plus a `deniedMcpServers` entry to hide the failed bundled one), the plugin server itself reads `SPACEBASE_API_KEY_COMMAND` and resolves the key in-process: `dot-claude/settings.json` `env` carries the **recipe** (`OP_SERVICE_ACCOUNT_TOKEN="$(security … -s op-claude-agent -w)" /opt/homebrew/bin/op read 'op://claude-agent/Spacebase API Key/credential'`) — a *non-secret* string, safe in plaintext — and the bundled server runs it, so the SA token and resolved key stay inside that one server process, never touching Claude Code's env, a Bash subprocess, the transcript, or OTEL. `op` is invoked by **absolute path** because the plugin server is spawned at Claude Code startup with a minimal PATH that lacks the homebrew bin dir — a bare `op` fails to resolve there, so the recipe pins `/opt/homebrew/bin/op` (consistent with this repo's existing Apple-Silicon homebrew assumption, e.g. `zsh/30-plugins.zsh`). When the keychain item is absent `op read` falls back to desktop biometric. This is the native fix tracked in `TheGnarCo/agent-skills#368` — it retired the `spacebase/spacebase-mcp` shim, its symlink + user-scope registration, and the fragile version-pinned denylist. **Requires a plugin version that reads `SPACEBASE_API_KEY_COMMAND`** (passing it through in its `mcpServers` env); on an older plugin the bundled server fails until upgraded. The key is a manual vault bootstrap (like the Claude Git PAT), not auto-provisioned: `op item create --category "API Credential" --title "Spacebase API Key" --vault claude-agent credential=<sw_token>`.

**Gotcha — the empty-string trio.** The plugin's `mcpServers.env` also passes through `SPACEBASE_API_KEY`, `SPACEBASE_URL`, and `SPACEBASE_PROJECT_ID` as `${VAR}` placeholders. For a var defined *nowhere* in `settings.json` `env`, Claude Code substitutes the **literal placeholder string** (not empty, not dropped) — so the server received `"${SPACEBASE_URL}"` as its base URL and died at startup with `Failed to resolve Spacebase project at startup: Invalid URL` (a valid default URL never throws that — only the literal does), and `"${SPACEBASE_API_KEY}"` is a truthy literal that would *shadow* the resolver command (`resolveApiKey` returns the first non-empty `SPACEBASE_API_KEY`). The fix is to define all three as **empty strings** in `settings.json` `env`, so each placeholder resolves to `""` and the server falls back to its intended defaults: empty key → run `SPACEBASE_API_KEY_COMMAND`; empty URL → built-in `https://spacebase.thegnar.com`; empty project id → auto-bind the single accessible project. Without these three lines the bundled server cannot start, even with a correct key recipe. (Only `SPACEBASE_API_KEY_COMMAND` carries a real value — the other three are deliberately blank.)

**Agent git auth uses the stock `osxkeychain` helper, not `op` directly** — so the agent pushes with a **least-privilege, fine-grained PAT** instead of your broad `gh` OAuth token, and authenticates headlessly with no biometric prompt (a keychain read, not an `op`/desktop-app call). The credential is the **login keychain**, populated out-of-band:

- `dot sync` (`install/47-op-agent.sh`) resolves the **fine-grained, all-repos, `Contents:read+write` PAT** from `op://claude-agent/Claude Git PAT/credential` and `git credential-osxkeychain store`s it as the `github.com` credential.
- A Claude session then authenticates git-over-HTTPS by **reading** that cached PAT via `osxkeychain` — no `op`, no biometric. Rotation = re-run `dot sync`.

Wired *agent-only* via `dot-claude/settings.json` `GIT_CONFIG_*` (`credential.https://github.com.helper` → `osxkeychain`, with an empty-string reset first to drop the inherited `gh` helper) — so the agent pushes with the least-privilege PAT instead of your broad `gh` OAuth token, while your own terminal git keeps the `gh` helper from `~/.gitconfig`. (SSH auth was rejected for the agent: 1Password's SSH agent is interactive-only — per-process biometric, no headless mode.) Bootstrap: mint the PAT and `op item create --category "API Credential" --title "Claude Git PAT" --vault claude-agent credential=<pat>`, then `dot sync`.

Rotation: delete the service account in the 1Password web UI and re-run `dot sync` — it re-mints whenever the keychain item is missing. Each machine gets its own per-host service account, so a single machine can be revoked without touching the others.

### Rules

- **Never commit a plaintext token** to any file. Use `op://` references or `op run --` instead.
- **Never add a token to a config file as plaintext.** If `.npmrc`-shape tools need credentials, use `op://` refs + `op run --`.
- **If you find a plaintext token anywhere**, revoke first, then migrate to `op` or a keychain CLI.
- **Deliberately not done**: secret injection via PreToolUse hooks (hook tool-I/O flows through OTEL telemetry unredacted — an exfil path), and any 1Password MCP that returns raw secret values to the agent (the official op MCP refuses to by design — which matches our threat model).
- `gitleaks` runs from the pre-commit hook template (`git-template/hooks/pre-commit`, copied into new repos via `init.templateDir`); it's a backstop, not the policy.

## Guardrails

Pause and confirm with the user before doing any of these:

- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*`): never edit by hand.
- **`link()` symlink semantics**: the `link()` function prompts on conflict (interactive `$LINK_MODE`) unless `-f` or `-s` is passed. Do not change the default behavior to auto-overwrite. (`dot doctor --fix` deliberately invokes it with `LINK_MODE=overwrite` for its opt-in repair path — that's explicit, not the default.)
- **The prompt is starship**: configured by `starship.toml` (symlinked to `~/.config/starship.toml`), initialized via `eval "$(starship init zsh)"` in `zsh/50-prompt.zsh`. Keep the config minimal.
- **Shared helpers live in `lib/common.sh`**: `os_kind`, `resolve_dotfiles_dir`, and `link()`, sourced by `sync` and `doctor` (callers set `_DOTFILES_SELF_DIR` first). Don't re-inline them.
- **Neovim is plugin-free**: the editor is configured by a single `nvim/init.lua` (sensible defaults + native LSP via `vim.lsp.config`/`vim.lsp.enable`, requires Neovim 0.11+). There is no plugin manager (lazy.nvim, packer) and no AstroNvim/LazyVim distro — don't propose adding one; keep the config to a single self-contained `init.lua`.

## Important Gotchas

- **dot-claude vs .claude**: `dot-claude/` is the source of truth for **user/global** Claude config (committed, symlinked into `~/.claude/` by `dot sync`). The repo-root `.claude/` is this repo's **project-scoped** config and is entirely gitignored — nothing under it is committed. Don't conflate the two: `dot-claude/` is the global config this repo ships; `.claude/` is local-only.
- **Sheldon plugin order matters**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml`. It wraps every existing ZLE widget at load time, so anything that registers a widget must run before sheldon's `eval` line in `zsh/30-plugins.zsh`.
- **`dot` survives a repo move**: `~/.local/bin/dot` is a **copy**, not a symlink (the *one* destination not symlinked — a symlink would dangle the instant the repo dir moved, making the very command that repairs symlinks unrunnable). The copy stays runnable; a breadcrumb at `${XDG_STATE_HOME:-~/.local/state}/dot/dir` (written by `sync`) lets it relocate the repo with no env var. Resolution order: `$DOTFILES_DIR` env → the script's own dir (in-repo `./dot`) → breadcrumb → `~/dotFiles`. To move the repo: `mv` it, then `DOTFILES_DIR=<new> dot sync` once — that relinks everything, re-copies the launcher, and re-records the breadcrumb (`dot` keeps working throughout, since the copy doesn't move; if the breadcrumb is stale it prints the exact heal command). `dot doctor` flags a stale/symlinked launcher or a wrong breadcrumb. `--force` is no longer needed for the relink.
- **`gh` auth is keychain-backed**: the OAuth token lives in the macOS login keychain (gh secure storage); `~/.config/gh/hosts.yml` carries only non-secret host metadata. If a future `gh auth login` ever uses `--insecure-storage` it will dump the token plaintext into `hosts.yml` — don't; re-login with default (secure) storage. `gh auth status` should show `(keyring)`.
- **`dot sync --only=<tag>` requires the tag to exist**: a module's declared tag and the `--only=` value must agree. A tag no module declares fails loudly (`==> ✗ --only=foo matched no module`, exit 1) — it does not silently run nothing.
