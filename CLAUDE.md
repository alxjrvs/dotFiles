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

The config is a typed, validated TOML document; boom parses it once and runs each `[[section]]` under the verb. The authoritative schema lives in the [boom docs](https://alxjrvs.github.io/boom/) — the summary below is orientation, not the source of truth. (**`boom validate` no longer exists**, measured against v0.26.0: "No command registered for `validate`". Use `boom plan`, or `boom source --dry-run`, both of which parse the boomfile and touch nothing. This is the hazard the top of this file already warns about — boom renames verbs across releases, so anything hardcoded here goes stale; the always-current reference is the `boom` skill.) Within a section, resources run in phase order `link → copy → glob → packages → run → hook`. Schema:

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

- **`op-guard.sh` / `rebase-guard.sh` / `worktree-checkout-guard.sh`** — `PreToolUse` guards (see `dot-claude/CLAUDE.md`). They are the only deterministic enforcement in the setup. `op-guard.sh` runs first and is the security one: it makes the 1Password CLI *usable* by agents by allow-listing the shapes that cannot put a secret value on stdout (`op run -- CMD`, `op inject -o FILE`, `op whoami`) and denying everything else `op`-shaped by default. It replaced a binary-scoped `Bash(op:*)` deny that also blocked `op --version` and `op run -- npm publish` — 1Password's own recommended pattern, which masks secrets in the child's output. Deny-lists fail open on the verb you forgot (that is how the one command with a confirmed leak stayed reachable); an allow-list fails closed.
- **`pr-review.sh`** — `PostToolUse`: runs the adversarial review locally after `gh pr create` / `git push` / `gh stack submit` and posts it as a PR review. **No commit status, so it never appears as a check** (removed 2026-08-17: it was required by no ruleset anywhere, and an advisory check that can never fail a merge only trains people to skim the checks list). Backgrounds itself so it can never block a turn. The `gh stack submit` arm matches neither of the others (Stacks API + in-process push, so no `git push` Bash call), and covers the checked-out layer only. The spawned reviewer reads attacker-controlled diff text under `defaultMode: auto` and publishes the result, so it must not be able to execute: it is confined by `permissions.deny` in `pr-review-settings.json` (`--settings`), **not** by `--allowedTools`, which was measured to be additive pre-approval that confines nothing. The hook feeds it `gh pr diff` rather than letting it fetch its own, which also gives a stacked layer the diff against its own base. The finding count still comes from a machine-readable trailer — it now leads the review body instead of a status description — and every failure path posts a "did not complete … not a verdict" comment rather than exiting silently, because a backgrounded hook that fails quietly is indistinguishable from one that found nothing.
- **`hooks/tests/`** — `run.sh` + `cases.tsv`, a hermetic regression suite for the three guards (throwaway git fixtures in `$TMPDIR`, no network, ~6s). Wired into `lint.yml` and lefthook pre-commit. **Add a case before changing a guard**: these are 200+ lines of security-relevant shell, and shipping them untested is how a `--dry-run` substring in an unrelated commit message came to disable the no-push-to-main rule.

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

### The standard we hold ourselves to (1Password's own, verified 2026-08-19)

1Password publishes a four-step pattern for agent credential access ([SDK AI-agent
tutorial](https://www.1password.dev/sdks/ai-agent), [service accounts + agentic
AI](https://1password.com/blog/service-accounts-sdks-agentic-ai)). It is the yardstick for
everything below, so it is recorded here rather than paraphrased per-decision:

1. **"Store credentials in a dedicated vault that's permissioned for the task at hand."**
2. **"Create a service account token with read-only access to that vault."**
3. **"Fetch credentials at runtime using secret reference URIs."**
4. **"Pass the secrets to your agent without hardcoding or exposing sensitive data"** — and,
   explicitly: *"Exposing raw credentials directly to an AI model carries significant risks.
   Where possible, avoid passing secrets to the model."*

Where we sit against it, honestly:

- **Steps 1–3: met.** Dedicated vault, `read_items`-only SA, `op://` refs resolved at runtime.
- **Step 4: exceeded.** 1Password says *"where possible, avoid passing secrets to the model"*;
  `op-guard.sh` plus the `permissions.deny` floor make it structurally impossible for a Claude
  session to put a resolved value on stdout. That is stronger than the published guidance, and
  it is the part of this setup worth keeping unchanged.
- **The gap is step 1** — *"permissioned for the task at hand"*. One vault serving personal,
  Binfinite, Gnar and CI concerns at once is not task-permissioning; it is a shared bucket that
  happens to be separate from `Private`. Since SA vault access is **immutable after creation**,
  the contents of the vault are the only lever available, so membership discipline *is* the
  control.
- **Two published guardrails we cannot use.** *"Activity Log auditability"* and service-account
  **usage reports** are **1Password Business/Teams only** — an Individual/Family account (ours,
  evidenced by a built-in `Private` vault) gets **no per-item, per-timestamp record** of what the
  SA read. The only signal is the aggregate counter from `op service-account ratelimit`.
  **So do not cite auditability as part of our security story.** Least privilege here rests
  entirely on *vault scope* + *token expiry* + *vault membership*, and that is precisely why the
  first two being immutable makes the third non-negotiable.

**Environments are now programmatically readable** (beta: *"Secrets can now be fetched
programmatically from 1Password Environments at runtime through the CLI and SDKs"*), and SDK
desktop auth is GA with authorization *"time-bound … expires after 10 minutes of inactivity"*.
That is a genuine future option for project env vars; it is **not** adopted here yet, and the
Environments MCP below still cannot return secret values.

### Agent secrets — the `op-agent` CLI

`hooks/op-agent.sh` is the single script for all agent-1Password machinery, dispatched by verb:

- `op-agent provision` — idempotently ensures the `claude-agent` vault, a per-host service account with `read_items` on only that vault **and `--expires-in` (default 90d, `BOOM_sa_expiry`)**, and its token in the macOS login keychain (`op-claude-agent`); also confirms the `claude-git-pat` vault item exists (a fresh-machine setup signal — the PAT is resolved on demand, never cached). Run via `on apply op-agent provision`. Foreground-only first run (minting authorizes through the desktop app). **`--expires-in` is create-time only**, and `provision` short-circuits once a keychain token exists, so this affects a *fresh* provision — a new machine, or after deliberately deleting the keychain item and the old service account. An existing open-ended token cannot acquire an expiry: 1Password's "Rotate Token" keeps the permissions but offers no expiry, and there is no CLI/API for it (`op service-account` has exactly `create` and `ratelimit`).
- `op-agent status` — reports keychain token presence, **warns when the SA token is within `BOOM_sa_warn_days` (default 14) of expiry and fails once it has lapsed**, then probes the PAT against the GitHub API and prints only a verdict (`on verify`). The expiry check runs *before* the PAT probe deliberately: a dead SA token breaks every secret path at once including the PAT resolve, so probing first would report a symptom masking its own cause. 1Password exposes no expiry API and sends no pre-expiry notification, so the `exp` claim is decoded locally from the `ops_`-prefixed JWT already in the process — offline, and only a date is ever printed.
- `op-agent audit <manifest>` — asserts the agent vault contains **exactly** the items declared in the repo's `agent-vault.txt`, and that every title is `kebab-case`. Prints titles (never a field value) and a verdict; fails closed on drift in either direction, advisory on tooling gaps. One consumer: a `boom verify` run step. **This is the compensating control for having no audit trail** — Activity Log and service-account usage reports are Business/Teams only, so on this Individual/Family account nothing records what the SA read. Since SA vault access is immutable after creation, scope can never be tightened in place and *membership* is the only control that stays live; this makes it declarative and enforced instead of described.
- `op-agent secret op://ref` — reads one secret value to stdout via the SA, the single read primitive for consumers that want a raw value (the spacebase/gninety `*_COMMAND`s, and `gh-mcp-stdio`). **The ref is an argument, not a per-service file.** It sources the SA token from the keychain inline (no biometric, headless-safe), confined to one short-lived process so neither the token nor the secret reaches a Bash subprocess, the transcript, or OTEL. Follows the `op read` contract: value on success, nothing + nonzero on failure (so a failed read leaves the consumer's var empty and it falls through to its own default).
- `op-agent header op://ref` — MCP `headersHelper` for an HTTP server that bearer-authenticates (the GitHub MCP at `api.githubcopilot.com/mcp/`, in Claude Code). Resolves the vaulted token via the same SA path as `secret` and emits `{"Authorization":"Bearer <token>"}`; on any failure emits `{}` (valid JSON, no header) so the client never sees a malformed response. **The ref is an argument, not a per-service file.**
- `op-agent git-credential get` — git credential helper (scoped to `https://github.com` in the agent git config). Resolves the `claude-git-pat` vault item via the same SA path as `secret` and emits `username=x-access-token` + `password=<pat>`; `store`/`erase` are no-ops (the vault is the source of truth). This is the canonical native-hook-fed-by-`op` pattern applied to git.

Every verb has a live consumer — no speculative surface. **This is a rule, not a description, and it is enforced by deletion.** `header` was deleted on 2026-07-25 with the GitHub MCP, its only consumer, and **restored the same day** when the GitHub MCP was reinstalled — which is the rule working in both directions, not a reversal of it.

**Zero calls means "broken or unused" and the two are indistinguishable from usage data alone.** That distinction is why the server came back: its "0 calls across 3,410 transcripts" was read as *unused*, but it had been **broken the whole time** — an unquoted `op://` ref with spaces (below), not a design that failed. Deleting on a usage signal alone removed a working idea. Check `claude mcp list` before concluding a server is dead weight; `boom verify` fails when a server reports `✘` **or** `! Needs authentication` — but only for servers visible from its CWD, which excludes the project-scoped `github`/`render` servers entirely (see *The GitHub MCP is configured twice*).

**Never resolve a secret verb from a Bash tool call to "check" it.** `op-agent secret`/`op read`/`op item get` are in `permissions.deny` precisely because a diagnostic that forgets `>/dev/null` prints a live PAT into the transcript (this happened on 2026-07-25 with `op-agent header`). To test `header`, compare its output against `{}` instead of printing it — the recipe is in the script's own header comment.

**To USE a secret, don't read it — pass it.** `op run -- <cmd>` is the shape an agent may run (allow-listed by `op-guard.sh`, pre-approved in `permissions.allow`): it injects the secret into the child's environment and never puts it on stdout, and 1Password masks any secret the child does print as `<concealed by 1Password>` — [`op run` reference](https://www.1password.dev/cli/reference/commands/run) — which is why `--no-masking` is denied. `op inject` is allowed only with `-o`/`--out-file`, since bare `op inject` renders the whole template, secrets and all, to stdout. This is not a local convention: 1Password's own agent guidance is *"store credentials in a dedicated vault… create a service account token with read-only access to that vault… fetch credentials at runtime using secret reference URIs"* — which is exactly the `claude-agent` + SA + `op://` architecture below. Their published position on putting values in an agent's context is blunt: *"No strong revocation model exists once secrets are passed into context."*

### MCP secrets — one canonical pattern

Servers we control launch via 1Password's `op run --env-file=.env -- <server>` with `op://` references in a committable `.env` (`boom mcp add`). Plugin-bundled stdio servers use their own `*_COMMAND` resolver (gninety's `NINETY_API_TOKEN_COMMAND` → `op-agent secret op://claude-agent/gninety/credential`; the parallel `SPACEBASE_*` set was deleted on 2026-08-08 with the plugin that read it). HTTP servers that bearer-authenticate use Claude Code's `headersHelper` → `op-agent header` (the GitHub MCP). Plugins that check a literal-token env var *before* their `_COMMAND` (gninety does) also need that var pinned to `""` in `settings.json`, else Claude Code's unset-`${VAR}` passthrough feeds the literal placeholder in as the token.

**Vault item titles are kept space-free, and every `op://` ref is quoted anyway.** Refs run through `/bin/sh -c`, so a title with spaces word-splits into separate arguments and the resolve fails. On 2026-07-25 this had **spacebase and the GitHub MCP both failing to connect** — spacebase logging `SPACEBASE_API_KEY_COMMAND failed`, and the GitHub helper emitting `{}` (op-agent's failure path), so no `Authorization` header was sent and the client fell back to OAuth discovery with the misleading error *"does not support dynamic client registration"* — an error naming neither 1Password nor the helper, which is why it was misread as an OAuth incompatibility and the server was deleted rather than fixed. `gninety`'s ref had no spaces, which is exactly why it was the only server still working. **Every item in the `claude-agent` vault was renamed to a space-free `kebab-case` title on 2026-07-25**, so quoting is now belt-and-braces everywhere rather than load-bearing anywhere: `Claude Git PAT`→`claude-git-pat`, `Spacebase API Key`→`spacebase-api-key`, `Render API Key`→`render-api-key`, `Claude Github PAT`→`claude-github-pat`, `Boom Release PAT`→`boom-release-pat`, `SUSRD RElease PAT`→`susrd-release-pat`, `Google Slides API IMP`→`google-slides-api-imp`, `npm publish token`→`npm-publish-token`, and `Gninety`→`gninety` (case, so the title matches the ref that was already lowercase). **New items in this vault MUST be `kebab-case`** — the invariant only holds if nothing re-introduces a space. **It is prose only, nothing enforces it, and it has already been broken** (measured 2026-08-19): `CloudflarePersonalAgentKey` and `PersonalCloudflareGithubCIKey`, both added 2026-08-18, are PascalCase. Neither contains a space, so the `sh -c` word-split bug did not fire — the invariant held by luck, not by design. This is the exact failure mode `dot-claude/CLAUDE.md` names: *"CLAUDE.md is advisory context, never enforcement; anything that must hold is pinned by permissions/hooks/run guardrails, not prose."* It wants a `boom verify` step asserting every agent-vault title matches `^[a-z0-9]+(-[a-z0-9]+)*$`. Item *IDs* are stable across a rename, so renaming never invalidates a ref that uses an ID. Other vaults (`Private` 52, `Binfinite` 28, `Gnar` 22 spaced titles) are deliberately untouched: their consumers are Environments, CI, and other machines that can't be verified from here. `boom verify` fails when an MCP server is down or needs re-auth, with the CWD caveat above. **Never write a `${VAR}` placeholder into a git-tracked `.mcp.json`/`.env`** (a later `claude mcp add` can expand it). The `git-template` pre-commit fails on a `${VAR}` in a tracked `.mcp.json` and on a resolved-token literal in any tracked `.mcp.json`/`.env`; `boom verify` has no such check today.

### The 1Password Environments MCP server — the one exception to all of the above (adopted 2026-08-18)

`1password` (user scope) → `/Applications/1Password.app/Contents/MacOS/1password-mcp`, a **stdio** server that ships inside the desktop app. It is the one MCP server here with **no secret in its configuration at all** — no `op://` ref, no `*_COMMAND`, no `headersHelper`, nothing for `boom mcp add` to wrap. That is not an oversight to fix; it is the design.

**It manages Environments, not vaults, and it never returns a secret value.** 1Password Environments are a separate object type from vaults, for a project's env vars. The server exposes eight tools — `authenticate`, `list_environments`, `create_environment`, `rename_environment`, `list_variables`, `append_variables`, `create_local_env_file`, `list_local_env_files` — and 1Password's guarantee is explicit: *"The server can only see variable and Environment names, and never returns the secrets stored in your Environments"* and *"The server cannot return secret values stored in 1Password to the client, even if an agent requests them."* Note `list_variables` retrieves **names**, not values. Values reach a *process* through a virtually-mounted `.env` (a UNIX pipe, never written to disk, so git cannot stage it) — never through a tool result into model context.

That property is why it is adoptable here at all, and it is the same principle the rest of this file enforces the hard way. 1Password's own position on the general case: *"No strong revocation model exists once secrets are passed into context."* This server is their answer to that, not an exception to it.

**Measured before adopting, because two things could have bitten:**
- **It reports `✔ Connected` with nobody at the keyboard.** The human approval gate is at *tool-call* time and per Environment, not at connect. Had it needed authorization to connect, the existing `claude mcp list | grep ✘` check would have failed `boom verify` on every unattended nightly run. It does not.
- **Tool calls genuinely do block on a desktop prompt.** A probe calling `authenticate` hung until killed. So it is useless in a background/cron session — harmless there, but do not build anything unattended on it.

**Caveats worth keeping.** It is beta. Local `.env` mounting is Mac/Linux only. Approvals reset when 1Password locks. 1Password documents setup tabs for Codex and Kiro only — Claude Code is "Other", and there is an open community request for docs; the generic `mcpServers` stdio block is what applies, which is what `claude mcp add` writes. **It has zero consumers today** (no Environments exist yet), so it is on the same "earn its place by use" clock as `enabledPlugins` — count real invocations (`"name":"mcp__1password__`) before treating it as settled, and per the user-scope rule it should migrate into a specific repo's checked-in `.claude/settings.json` once one project actually owns an Environment.

Registration lives in `~/.claude.json`, which nothing tracks — so the boomfile carries a `sync` step to register it and a `verify` step to assert it, the latter because a `run` bound to `sync` is invisible to `verify` by construction.

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
- npm registry auth → `npm/npmrc` (linked to `~/.npmrc`, the canonical userconfig) carries `_authToken=${NPM_TOKEN}`, expanded by npm at read time. Daily public installs need no token, so nothing exports a secret to the session env. **`op run -- npm publish` alone does NOT work** (measured 2026-08-19): `op run` injects only what it is given, and nothing defined `NPM_TOKEN` as an `op://` reference — no `--env-file`, no shell export, no `.env`. `NPM_TOKEN` stayed unset and npm read an empty `_authToken`. The storage side was always correct (the file holds the literal placeholder, never a token); the **resolution** side was never wired. **Now wired**: `npm/publish.env` carries `NPM_TOKEN=op://claude-agent/npm-publish-token/credential`, so the working shape is `op run --env-file=npm/publish.env -- npm publish`. That file is committable because it holds a reference, not a value.
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
- `skills/*` — glob-linked into `~/.claude/skills/`, so a new directory is picked up with no boomfile change. **Read the directory for the roster; it is deliberately not enumerated here** — a hand-maintained list of a glob-linked directory goes stale the next time a skill is added or removed, with no symptom, and nothing checks it.

### The Butter Stack (`dot-claude/skills/butter-stack/`)

**Butter, because it goes on the Bun** — the house shape for personal TypeScript work, and the one place it is written down so an agent can copy it rather than re-derive it per repo: **B**un · **U**nified workspace (`apps/*` + `packages/*`) · **T**ypeScript (strict-plus) · **T**anStack · **E**dge-deployed (Netlify/Render/Convex) · **R**eact.

It is descriptive before it is prescriptive. `RANDSUM/randsum`, `SalvageUnion-io/SU-SRD`, `alxjrvs/optfall` and `BinfiniteLLC/binfinite-app` arrived at it **independently**, never templated from one another — that convergence is the evidence, and it is why the skill records what four repos re-decided under pressure rather than a preferred toolchain. (Those are the GitHub names; the local checkouts under `~/Code` are spelled differently, and `BinfiniteLLC/BinfiniteApp` is a directory name that does not resolve on GitHub.)

Two things in it matter more than the tool list:

- **The signature habit** — conventions get promoted from prose into executable `check:*` gates wired into the aggregate CI job. A rule nothing enforces is a rule that has already drifted; this repo's own guard tests are the same instinct.
- **The deliberate-exceptions table** — a set of per-repo deviations that each look like drift and are load-bearing, so a tidying pass doesn't remove them. **Read it in the skill and check it before calling anything drift.** Deliberately not summarized here: copying those rows into always-loaded context is the same hand-maintained-duplicate problem as the skills roster above, and the table is the one thing in the skill that must never be consulted from a stale copy.

The skill audits (read-only) or scaffolds (writes only after a go-ahead), and hands off to `agent-friendly-repo` for merge settings — a `CI Success` gate is only real once it is the required check.

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

- **dot-claude vs .claude**: `dot-claude/` is the source of truth for **user/global** Claude config (committed, symlinked into `~/.claude/`). The repo-root `.claude/` is this repo's **project-scoped** config, gitignored **except** the one tracked `.claude/settings.json` carrying the `project.name` telemetry tag — attribution is a property of the repo, not of a machine, so it is checked in rather than left to a per-clone `settings.local.json`. Don't conflate them.
- **Sheldon plugin order**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml` (it wraps every existing ZLE widget at load).
- **`gh` auth is keychain-backed**: token in the login keychain (gh secure storage); `~/.config/gh/hosts.yml` carries only non-secret metadata. Never `gh auth login --insecure-storage`.
- **The engine is `boom`** (the BoomTube project): anything about apply/verify/fix/rollback semantics, symlink internals, the manifest/journal, or orphan reaping lives in `github.com/alxjrvs/boom`, not here. This repo is config.
