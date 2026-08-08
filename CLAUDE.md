# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in this repository.

## What This Is

A macOS **dotfiles repo** that is pure **config for [BoomTube](https://github.com/alxjrvs/boom)** — the small TypeScript dotfiles+workspace engine (the executable is `boom`), compiled to a single binary on `PATH`. This repo is its *first consumer*. There is no engine code here: the whole repo is a `boomfile.toml` (the config), a handful of TypeScript `hooks/`, and the payload (`.zshrc`, `zsh/`, `nvim/`, `dot-claude/`, `Brewfile`, `mise.toml`, …) that boom symlinks into place.

boom's command surface is boom's to document, not this repo's — and boom renames
verbs across releases (repair↔fix, apply→source), so anything hardcoded here goes
stale. The always-current agentic reference is the **`boom` skill**, regenerated
from the installed binary on every `boom source` (a `run` step, `boom skill
--install`) — so it can't lag a `boom upgrade`. For humans: the [boom
docs](https://alxjrvs.github.io/boom/), `boom --help`, or `boom man`. Don't
restate the full command list here. Day-to-day: `boom source` reconciles the
machine from `boomfile.toml` (symlink/copy/install/run), and `boom verify` checks
drift (exit 0 ok / 2 warn / 1 fail; `--json` for a report).

Fresh machine: `curl -fsSL https://raw.githubusercontent.com/alxjrvs/boom/main/install.sh | sh && boom source set alxjrvs/dotFiles` (installs boom, clones + records this repo, reconciles).

## The `boomfile.toml`

The config is a typed, validated TOML document; boom parses it once and runs each `[[section]]` under the verb. The authoritative schema lives in the [boom docs](https://alxjrvs.github.io/boom/) (`boom validate` checks a file against it) — the summary below is orientation, not the source of truth. Within a section, resources run in phase order `link → copy → glob → packages → run → hook`. Schema:

- `[[section]]` with `name` (the `--only`/tag) and optional `when = { os, host, profile }` to gate by machine.
- `link` / `copy` `[{ src, dst, mode? }]` and `glob [{ pattern, into }]` — the symlink/copy contract (`dst` may use `~`).
- `brewfile = "FILE"` / `mise = true` — packages via the stock tools (the `Brewfile` / `mise.toml` are the data).
- `osx_default [{ domain, key, type, value }]` — a macOS default (the engine restarts the UI automatically when any changed).
- `run [{ on = "sync"|"verify", cmd }]` — a small inline imperative step.
- `hook [{ name, with? }]` — loads `hooks/<name>.ts` (a TypeScript resource module), passing `with` as inputs. For substantial imperative logic only.

Multi-machine: gate sections with `when`, or layer overlay files `boomfile.<os|host|profile>.toml`.

## Northern Principles

One North Star: **small, exemplary, easily shareable — a senior engineer's showpiece, not an over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff to the owner.

1. **Native over special.** Prefer stock behavior to bespoke machinery; deleting custom code for a built-in is the highest-value change. (Extracting the engine into `boom` was the largest application of this.)
2. **Guilty until proven load-bearing.** Every dependency, wrapper, and line earns its weight on a *personal* repo, or it goes.
3. **No gratuitous wrappers.** Call tools natively. The lone bash script that survives is `op-agent`, which an external program execs by path (a plugin `*_COMMAND` resolver, see Secrets); git commit signing lives in the `git-signing.ts` hook.
4. **One config, every machine.** No host detection. Add the smallest possible guard at the point a genuine per-machine divergence appears.
5. **Standard, and agentic-enabled.** 1Password, Git, SSH, `gh`, MCP stay stock — but wired for agents. Secrets resolve through `op` on demand, never plaintext in git, never exported to the session env.
6. **Keep it legible.** Plain ops over clever math; docs explain the *decision and the gotcha*, not the *what*.

## hooks/

The imperative residue the config can't express. A boom hook is a `hooks/<name>.ts` module exporting `apply`/`verify`/`fix` functions that receive a typed `HookApi` (`with` inputs, `dryRun`, `env`, and `ok`/`warn`/`fail`/`note`); it self-locates this repo via `import.meta.dir`, and `fix` falls back to `apply`.

- **`git-signing.ts`** — converges git commit/tag signing via 1Password `op-ssh-sign` (machine-local `~/.gitconfig.local` + `~/.ssh/allowed_signers`), using the agent key named by `with.key` (default `GitHubSSH`).
- **`claude_statusline.ts`** — clones the `claude-statusline` repo (`repo=` in the boomfile — now `TheGnarCo/claude-statusline`, the collectively-owned continuation of `alxjrvs/claude-statusline`) beside this one and runs its installer. It re-clones when that input changes, since the Gnar repo was *seeded* from the old one rather than forked: no shared history, so nothing can fast-forward across the switch.
- **`op-agent.sh`** — NOT a boom hook: a standalone bash CLI for all 1Password-agent machinery (see Secrets), `link`ed onto `PATH` as `op-agent` and driven by `run` steps (`op-agent provision` / `op-agent status`). Stays bash because external programs exec it by path (a plugin `*_COMMAND` resolver; git's `credential.helper`).

Also NOT boom hooks — Claude Code hooks, linked into `~/.claude/hooks/`:

- **`rebase-guard.sh` / `worktree-checkout-guard.sh`** — `PreToolUse` guards (see `dot-claude/CLAUDE.md`). They are the only deterministic enforcement in the setup.
- **`pr-review.sh`** — `PostToolUse`: runs the adversarial review locally after `gh pr create` / `git push` / `gh stack submit` and posts it as a PR review + a `claude-review` commit status. Backgrounds itself so it can never block a turn. The `gh stack submit` arm matches neither of the others (Stacks API + in-process push, so no `git push` Bash call), and covers the checked-out layer only. The spawned reviewer reads attacker-controlled diff text under `defaultMode: auto` and publishes the result, so it must not be able to execute: it is confined by `permissions.deny` in `pr-review-settings.json` (`--settings`), **not** by `--allowedTools`, which was measured to be additive pre-approval that confines nothing. The hook feeds it `gh pr diff` rather than letting it fetch its own, which also gives a stacked layer the diff against its own base. Its `claude-review` status comes from a machine-readable trailer and fails closed on an unparseable body — the previous prose grep matched nothing and reported 15 straight clean bills of health over reviews that contained real findings.
- **`hooks/tests/`** — `run.sh` + `cases.tsv`, a hermetic regression suite for the two guards (throwaway git fixtures in `$TMPDIR`, no network, ~5s). Wired into `lint.yml` and lefthook pre-commit. **Add a case before changing a guard**: these are 200+ lines of security-relevant shell, and shipping them untested is how a `--dry-run` substring in an unrelated commit message came to disable the no-push-to-main rule.

Small steps (`chmod 700 ~/.ssh`, `lefthook install`) are inline `run` (`on = "apply"`) entries, not files.

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

`Brewfile` holds **only** `mise` (bootstrap), casks (GUI apps, fonts), and system libs with no mise equivalent. `mise.toml` holds all language toolchains AND dev CLIs (`jq`, `shellcheck`, `shfmt`). If you're about to add a CLI to `Brewfile`, stop — it goes in `mise.toml` unless it's `mise` itself or a cask.

**`gh` extensions are the one exception to both** — they aren't packages either manager knows about, and boom has no `gh` manager, so the `gh extensions` section carries install-if-absent `run` steps (today: the official `github/gh-stack` for stacked PRs, plus `dlvhdr/gh-dash`, `meiji163/gh-notify`, and `actions/gh-actions-cache`). Each grep is **owner-qualified** — `gh ext search stack` alone returns four same-named community forks, so a bare name is not an identity. That section **must stay after `packages`**: `gh` comes from mise and sections run in file order, so a fresh machine has no `gh` on PATH before it.

## Terminal: Ghostty (sole terminal)

Ghostty is the only terminal (`TERMINAL=ghostty`, `ghostty/config`) — one symlinked file for rendering + keybinds/visor. Parallel Claude Code sessions run through `claude agents` mode directly (standalone Ghostty, no multiplexer: `claude agents` already does parallel dispatch, session persistence, and git-worktree isolation, so a multiplexing terminal is redundant). `boom code` mirrors `~/Code` into workspaces: `boom code init [DIR]` records the dir, `boom code claude` symlinks every repo into one flat dir and opens `claude agents` there so each repo is `@`-taggable for dispatch. (cmux, a libghostty agent multiplexer, was removed for this reason; `boom code cmux` — the per-repo workspace variant — is an unused engine feature.)

## Secrets management

1Password (`op`) is the source of truth, following 1Password's two-tier model:

- **Interactive dev (you)** — desktop app + biometric; resolve via `op run` / `op://` refs / Environments.
- **Hands-off agent (Claude, MCP, cron)** — a **service account** scoped to the `claude-agent` vault; no biometric, no desktop dependency.

### Agent secrets — the `op-agent` CLI

`hooks/op-agent.sh` is the single script for all agent-1Password machinery, dispatched by verb:

- `op-agent provision` — idempotently ensures the `claude-agent` vault, a per-host service account with `read_items` on only that vault **and `--expires-in` (default 90d, `BOOM_sa_expiry`)**, and its token in the macOS login keychain (`op-claude-agent`); also confirms the `claude-git-pat` vault item exists (a fresh-machine setup signal — the PAT is resolved on demand, never cached). Run via `on apply op-agent provision`. Foreground-only first run (minting authorizes through the desktop app). **`--expires-in` is create-time only**, and `provision` short-circuits once a keychain token exists, so this affects a *fresh* provision — a new machine, or after deliberately deleting the keychain item and the old service account. An existing open-ended token cannot acquire an expiry: 1Password's "Rotate Token" keeps the permissions but offers no expiry, and there is no CLI/API for it (`op service-account` has exactly `create` and `ratelimit`).
- `op-agent status` — reports keychain token presence, **warns when the SA token is within `BOOM_sa_warn_days` (default 14) of expiry and fails once it has lapsed**, then probes the PAT against the GitHub API and prints only a verdict (`on verify`). The expiry check runs *before* the PAT probe deliberately: a dead SA token breaks every secret path at once including the PAT resolve, so probing first would report a symptom masking its own cause. 1Password exposes no expiry API and sends no pre-expiry notification, so the `exp` claim is decoded locally from the `ops_`-prefixed JWT already in the process — offline, and only a date is ever printed.
- `op-agent secret op://ref` — reads one secret value to stdout via the SA, the single read primitive for consumers that want a raw value (the spacebase/gninety `*_COMMAND`s, and `gh-mcp-stdio`). **The ref is an argument, not a per-service file.** It sources the SA token from the keychain inline (no biometric, headless-safe), confined to one short-lived process so neither the token nor the secret reaches a Bash subprocess, the transcript, or OTEL. Follows the `op read` contract: value on success, nothing + nonzero on failure (so a failed read leaves the consumer's var empty and it falls through to its own default).
- `op-agent header op://ref` — MCP `headersHelper` for an HTTP server that bearer-authenticates (the GitHub MCP at `api.githubcopilot.com/mcp/`, in Claude Code). Resolves the vaulted token via the same SA path as `secret` and emits `{"Authorization":"Bearer <token>"}`; on any failure emits `{}` (valid JSON, no header) so the client never sees a malformed response. **The ref is an argument, not a per-service file.**
- `op-agent git-credential get` — git credential helper (scoped to `https://github.com` in the agent git config). Resolves the `claude-git-pat` vault item via the same SA path as `secret` and emits `username=x-access-token` + `password=<pat>`; `store`/`erase` are no-ops (the vault is the source of truth). This is the canonical native-hook-fed-by-`op` pattern applied to git.

Every verb has a live consumer — no speculative surface. **This is a rule, not a description, and it is enforced by deletion.** `header` was deleted on 2026-07-25 with the GitHub MCP, its only consumer, and **restored the same day** when the GitHub MCP was reinstalled — which is the rule working in both directions, not a reversal of it.

**Zero calls means "broken or unused" and the two are indistinguishable from usage data alone.** That distinction is why the server came back: its "0 calls across 3,410 transcripts" was read as *unused*, but it had been **broken the whole time** — an unquoted `op://` ref with spaces (below), not a design that failed. Deleting on a usage signal alone removed a working idea. Check `claude mcp list` before concluding a server is dead weight; `boom verify` fails when a server reports `✘` **or** `! Needs authentication` — but only for servers visible from its CWD, which excludes the project-scoped `github`/`render` servers entirely (see *The GitHub MCP is configured twice*).

**Never resolve a secret verb from a Bash tool call to "check" it.** `op-agent secret`/`op read`/`op item get` are in `permissions.deny` precisely because a diagnostic that forgets `>/dev/null` prints a live PAT into the transcript (this happened on 2026-07-25 with `op-agent header`). To test `header`, compare its output against `{}` instead of printing it — the recipe is in the script's own header comment.

### MCP secrets — one canonical pattern

Servers we control launch via 1Password's `op run --env-file=.env -- <server>` with `op://` references in a committable `.env` (`boom mcp add`). Plugin-bundled stdio servers use their own `*_COMMAND` resolver (gninety's `NINETY_API_TOKEN_COMMAND` → `op-agent secret op://claude-agent/gninety/credential`; the parallel `SPACEBASE_*` set was deleted on 2026-08-08 with the plugin that read it). HTTP servers that bearer-authenticate use Claude Code's `headersHelper` → `op-agent header` (the GitHub MCP). Plugins that check a literal-token env var *before* their `_COMMAND` (gninety does) also need that var pinned to `""` in `settings.json`, else Claude Code's unset-`${VAR}` passthrough feeds the literal placeholder in as the token.

**Vault item titles are kept space-free, and every `op://` ref is quoted anyway.** Refs run through `/bin/sh -c`, so a title with spaces word-splits into separate arguments and the resolve fails. On 2026-07-25 this had **spacebase and the GitHub MCP both failing to connect** — spacebase logging `SPACEBASE_API_KEY_COMMAND failed`, and the GitHub helper emitting `{}` (op-agent's failure path), so no `Authorization` header was sent and the client fell back to OAuth discovery with the misleading error *"does not support dynamic client registration"* — an error naming neither 1Password nor the helper, which is why it was misread as an OAuth incompatibility and the server was deleted rather than fixed. `gninety`'s ref had no spaces, which is exactly why it was the only server still working. **Every item in the `claude-agent` vault was renamed to a space-free `kebab-case` title on 2026-07-25**, so quoting is now belt-and-braces everywhere rather than load-bearing anywhere: `Claude Git PAT`→`claude-git-pat`, `Spacebase API Key`→`spacebase-api-key`, `Render API Key`→`render-api-key`, `Claude Github PAT`→`claude-github-pat`, `Boom Release PAT`→`boom-release-pat`, `SUSRD RElease PAT`→`susrd-release-pat`, `Google Slides API IMP`→`google-slides-api-imp`, `npm publish token`→`npm-publish-token`, and `Gninety`→`gninety` (case, so the title matches the ref that was already lowercase). **New items in this vault MUST be `kebab-case`** — the invariant only holds if nothing re-introduces a space. Item *IDs* are stable across a rename, so renaming never invalidates a ref that uses an ID. Other vaults (`Private` 52, `Binfinite` 28, `Gnar` 22 spaced titles) are deliberately untouched: their consumers are Environments, CI, and other machines that can't be verified from here. `boom verify` fails when an MCP server is down or needs re-auth, with the CWD caveat above. **Never write a `${VAR}` placeholder into a git-tracked `.mcp.json`/`.env`** (a later `claude mcp add` can expand it). The `git-template` pre-commit fails on a `${VAR}` in a tracked `.mcp.json` and on a resolved-token literal in any tracked `.mcp.json`/`.env`; `boom verify` has no such check today.

### The GitHub MCP is configured twice, on purpose

The two Claude clients cannot share one mechanism, so each gets the only one it supports. Both resolve the **same** vault item through the **same** `op` primitive, so there is still one credential and one source of truth.

| | Claude Code | Claude Desktop |
|---|---|---|
| Server | remote HTTP, `api.githubcopilot.com/mcp/` | local stdio, `aqua:github/github-mcp-server` |
| Config | `~/.claude.json` (user scope) | `claude_desktop_config.json` → `gh-mcp-stdio` |
| Auth | `headersHelper` → `op-agent header` | `GITHUB_PERSONAL_ACCESS_TOKEN` env, injected in-process |

Desktop can't use the remote server: it authenticates through a registered GitHub App, and Desktop's *Add custom connector* OAuth flow doesn't support that — [GitHub's own `install-claude.md`](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md) says to run it locally. And Desktop has no `headersHelper`, so `gh-mcp-stdio` resolves the PAT at launch and exports it into that one process. **GitHub's documented Desktop config hardcodes the PAT in an `env` block; we deliberately don't** — a `boom verify` check fails if `GITHUB_PERSONAL_ACCESS_TOKEN` ever appears in `claude_desktop_config.json`.

`claude_desktop_config.json` is **merged, never linked** (`hooks/claude-desktop-mcp.sh`, `on sync`): the app owns that file and rewrites `preferences`/device IDs into it continuously, so a symlink would mean the app permanently dirtying a tracked file and a fresh `boom source` clobbering real app state.

### Agent git auth

Git's native `credential.helper` is pointed at `op-agent git-credential` (fronted by git's `cache --timeout=900` helper), so the agent resolves its PAT from the `claude-agent` vault on demand — the **same single `op` primitive as every other agent secret**, the canonical "tool's own native hook fed by `op`" pattern (git's hook is the credential helper). The PAT is *stored* only in 1Password: no keychain cache, no second mechanism. It is not *resident* only there — the `cache` helper holds it in `git-credential-cache--daemon`'s memory for 15 minutes after any agent git operation, readable by any same-user process via `git credential fill`, which is why `Bash(git credential:*)` is denied. The cache still earns its place: 1Password's daily rate limit is **per account** (1,000 combined reads on Individual/Family), so it is doing quota work, not just latency work.

The vault token is a **classic** `repo`+`workflow` PAT, **SSO-authorized** for the orgs the agent pushes to — *not* a fine-grained one, and that's deliberate. Fine-grained PATs are gated on org-owner enablement + approval, which `alxjrvs` lacks for the orgs in play; a classic token is bounded by your own access and is self-SSO-authorizable (member-level), so it's the narrowest credential that actually reaches those org repos. Least-privilege therefore rests on the SA-scoped vault + a token expiry, not on per-repo scoping. The helper is token-agnostic, so rotation/scope changes are just an update to the `claude-git-pat` vault item — no code change. **That one item now backs three consumers** — agent git auth, the Claude Code GitHub MCP, and the Claude Desktop GitHub MCP — so rotating it rotates all three at once, and a lapse breaks all three at once (`op-agent status` probes it on every `boom verify`). **Do not "downgrade" this to a fine-grained PAT** expecting org access; it will silently lose the org repos.

Headless, no biometric (SA token via `securityd`); the `cache` helper amortizes the per-op round-trip; and because the resolve path is `securityd` + network rather than a keychain *file* read, it survives a sandbox `credentials.files` deny on the keychain. Wired agent-only via `dot-claude/settings.json` `GIT_CONFIG_*`. Your own terminal git keeps its `gh` helper + 1Password signing. (Agent commits are unsigned by design — if a target org enforces *require signed commits*, the agent would also need a signing path; none configured today.)

### Rules

- Never commit a plaintext token. Use `op://` references or `op run --`.
- Controlled servers → `op run --env-file`; plugin servers → their `*_COMMAND` (→ `op-agent secret`); HTTP servers that bearer-authenticate → `headersHelper` (→ `op-agent header`); a stdio server for Claude Desktop → a launcher that exports the token in-process (→ `op-agent secret`), never an `env` block in `claude_desktop_config.json`.
- npm registry auth → `npm/npmrc` (linked to `~/.npmrc`, the canonical userconfig) carries `_authToken=${NPM_TOKEN}`, expanded by npm at read time; publish via `op run -- npm publish`. Daily public installs need no token, so nothing exports a secret to the session env.
- If you find a plaintext token anywhere, revoke first, then migrate.

### Standing threats (keep the surface small)

The minimal MCP/plugin footprint is a *security* decision, not just taste — every enabled server widens the prompt-injection/exfil blast radius. Two live vectors shape the posture:

- **`~/.claude.json` postinstall hijack** (Mitiga, unpatched-by-design): a malicious npm/bun package's `postinstall` can rewrite `~/.claude.json` to MITM MCP traffic and steal OAuth tokens — invisible in provider logs. No patch is coming (it presupposes code execution as the Claude user). Native mitigations, already mostly in place: don't run untrusted `npm/bun install` as the agent user; keep MCP OAuth surface minimal; prefer scoped tokens with an expiry (the `claude-agent` SA caps what the agent can read, and its tokens are bounded by your own access); the `editorMode`-level `permissions.deny` floor blocks direct keychain token reads. No bespoke `~/.claude.json` integrity-checker — that's machinery this repo would otherwise delete.
- **Repo-controlled config CVEs** (CVE-2025-59536 RCE, the `enableAllProjectMcpServers` auto-approve bypass, CVE-2026-21852 `ANTHROPIC_BASE_URL` key-exfil): all patched in current Claude Code, all pre-trust-dialog. Mitigation: stay current, never set `enableAllProjectMcpServers`/`enabledMcpjsonServers` globally (`boom verify` greps for them), don't open untrusted repos under `auto` mode.

There is no canonical "must-install" plugin set; `enabledPlugins` earns each entry by use, not by hype.

## Claude Code Configuration (`dot-claude/`)

Symlinked individually into `~/.claude/` (the `Claude` section of the boomfile):

- `CLAUDE.md` — user-level global instructions (identity, preferences).
- `settings.json` — **deliberately minimal**; only divergences from defaults (enumerated in `dot-claude/CLAUDE.md`). Don't add settings without asking.

## Guardrails

- **Dependency lockfiles** (`*-lock*`, `*.lock*`): never edit by hand.
- **The prompt is starship** (`starship.toml`); keep it minimal.
- **Neovim is plugin-free** (single `nvim/init.lua`, native LSP, ≥0.11). No plugin manager, no distro.
- **`link` semantics live in boom, not here** — this repo only *declares* links in the boomfile.
- **`biome.json` carries only divergences from biome's defaults** — same discipline as `settings.json`. The lint rules are stock: there is no `rules` block, so it is biome's recommended set, and `linter.enabled` is omitted because it already defaults true (verified — omitting the block still catches `noDebugger`; only an explicit `false` disables it). `formatter.enabled` and `indentWidth: 2` were dropped for the same reason. The three keys that remain are each load-bearing, so don't "tidy" them away:
  - `vcs.useIgnoreFile` — biome does **not** respect `.gitignore` by default. Without it, a bare `biome check` descends into `.claude/worktrees/`, which holds full copies of this repo.
  - `formatter.indentStyle: "space"` — biome's default is **tab**. `useEditorconfig` defaults to *false*, so `.editorconfig` alone does not make biome agree with the rest of the repo.
  - `overrides` → `dot-claude/settings.json` `expand: "always"` — stops biome and the Claude Code client rewriting that file past each other (see #91).

## Gotchas

- **dot-claude vs .claude**: `dot-claude/` is the source of truth for **user/global** Claude config (committed, symlinked into `~/.claude/`). The repo-root `.claude/` is this repo's **project-scoped**, gitignored config. Don't conflate them.
- **Sheldon plugin order**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml` (it wraps every existing ZLE widget at load).
- **`gh` auth is keychain-backed**: token in the login keychain (gh secure storage); `~/.config/gh/hosts.yml` carries only non-secret metadata. Never `gh auth login --insecure-storage`.
- **The engine is `boom`** (the BoomTube project): anything about apply/verify/fix/rollback semantics, symlink internals, the manifest/journal, or orphan reaping lives in `github.com/alxjrvs/boom`, not here. This repo is config.
