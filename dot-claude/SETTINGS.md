# settings.json — what each key is for

One line per key in `dot-claude/settings.json`. **Not auto-loaded** — nothing symlinks this into
`~/.claude/`, so it costs nothing per session. Read it on demand.

This file exists because the alternative was 42,574 bytes of prose in `CLAUDE.md` — four times
larger than the JSON it described — narrating a checked-in file, in every session, and drifting
from it. The JSON is the truth. This is the index. Where a key *must* hold, the assertion lives
in `lint.yml`, `lefthook.yml`, or a `boomfile.toml` verify step, and **that** is the control —
never this page.

Two rules for editing it:

- **A key that equals the current default does not belong in `settings.json` at all.** Delete the
  key, not the line here. `teammateMode` was removed for exactly this.
- **Never record a client version here.** A version-pinned claim expires unnoticed and nothing
  owns it. Reasoning and measurements go to `DECISIONS.md`.

## Permissions and enforcement

| key | what it is for |
|---|---|
| `permissions.deny` | The deterministic floor; survives auto/bypass mode. Keychain reads, the `op`/`op-agent` verbs that print a secret value, raw key and cloud-credential files, `git credential`. Every entry is asserted by array membership — not substring — in each gate that checks it. |
| `permissions.allow` | Pre-approvals for the completion path: `gh pr merge`, `gh stack merge`, `git stash`, and `op run` — the last only because `op-guard.sh` strips its unsafe variants first. `git stash` is here because the auto-mode classifier blocks it and nothing in this repo asked for that: `worktree-freshness.sh` *tells* the agent to "commit or stash, then rebase", and the block made that instruction unfollowable. It is local, reversible, and reaches no remote. `op --version`, `op whoami` and `op item list` are the non-printing shapes `op-guard.sh`'s own denial message advertises as safe — the guard permits them and the classifier was refusing them anyway. An `allow` entry does not skip `PreToolUse`, so op-guard still adjudicates every one of these. |
| `autoMode.classifyAllShell` | Route every shell command through the classifier, not just arbitrary-exec shapes. |
| `autoMode.hard_deny` | The classifier-level floor under CLAUDE.md's first rule. `v2.1.211` removed the built-in protected-branch treatment — *"pushes to any branch of the repository you're working in are allowed by default, so there is no protected-branch default to configure"* — which left `rebase-guard.sh` as the only thing enforcing it. `hard_deny` blocks unconditionally: user intent and `allow` exceptions do not apply, unlike `soft_deny`. It leads with the literal `"$defaults"` or the built-in rules are silently discarded. `soft_deny` stays unset: the defaults already cover force push, `curl \| bash`, production deploys and exfiltration. It overlaps `rebase-guard.sh` completely on the push shape, and both stay — a classifier miss and a tokenizer gap are uncorrelated failures; see DECISIONS.md, *the protected-branch rule is enforced twice*. A sibling `allow` was removed 2026-08-28 — it held only `["$defaults"]`, which resolves to exactly the unset behaviour and so did nothing but invite a future edit to assume it was load-bearing. |
| ~~`autoMode.environment`~~ | **Deliberately absent.** It described one repo's stack while telling the classifier no other orgs existed, in every session on this machine — so it misinformed the control it fed. `autoMode` is ignored in project settings, so a per-project payload cannot be pushed down to the repo it belongs to. If it returns, it names orgs and nothing repo-specific. |
| `hooks` | `PreToolUse` guards (`op-guard`, `worktree-checkout-guard`, `rebase-guard` — in that order), the `Stop` verify gate, and the worktree hooks: `worktree-freshness` + `worktree-port` at session start. There is no `PostToolUse` block (its only occupants were the PR reviewer's three handlers) and no `SessionEnd` block (its only occupant was `worktree-publish`) — both deleted 2026-08-28. The hooks are the enforcement; their scripts carry their own reasoning. |

## Identity and git

| key | what it is for |
|---|---|
| `env.GIT_AUTHOR_*` / `GIT_COMMITTER_*` | Agent commits are authored as `Claude`, distinct from your own terminal git. |
| `env.GIT_CONFIG_*` | Disables commit/tag signing for agent commits, and points `credential.helper` at `op-agent git-credential` behind git's 15-minute cache. |
| `attribution.commit` | Adds the co-author trailer. |
| `env.NINETY_API_TOKEN_COMMAND` | Resolves the Ninety PAT from the agent vault on demand. |
| `env.NINETY_API_TOKEN` / `NINETY_BASE_URL` | **Empty strings are load-bearing.** The plugin checks the literal var before the `_COMMAND`, and an unset `${VAR}` is passed through as a literal and read as a real token — producing a misleading 401. |

## MCP servers

Not a `settings.json` key — these live in `~/.claude.json`, which is app-owned and tracked by
nothing. A `boom verify` step asserts every configured `headersHelper` is executable, and another
fails when `claude mcp list` reports `✘` or `! Needs authentication`.

| server | what it is for |
|---|---|
| `1password` | Manages 1Password **Environments**, not vaults. Ships inside the desktop app, so there is no token and no `op://` ref — it structurally cannot return a secret value. Reproduced by a `sync` step and asserted on `verify`, so this row is orientation and the boomfile is the control. |
| `sentry` | Remote HTTP (`mcp.sentry.dev`). Genuinely used — the invocation ledger shows real `search_events` / `search_issues` traffic, so it earns its place. **Reproduced by no boomfile step**, so a fresh machine does not get it; this row is the only record it is expected at all. |

**The health check is scoped to these two, deliberately.** `claude mcp list` also reports
account-level **claude.ai connectors** — Asana, Atlassian, Box, Canva, Figma, HubSpot, Intercom,
Linear, monday.com, Notion and more — which are configured at claude.ai, not here. Most sit
unauthenticated, so an unfiltered check failed on essentially every run and would have trained the
nightly notify to be ignored. The verify step now skips lines the client prefixes with
`claude.ai `, so it only judges what this machine actually configures.

If one of these two genuinely needs re-authentication, the check fires and that is correct — run
the server's `authenticate` tool. It is a prompt to act, not noise, because it is a server we own.

**Deliberately absent: any third-party GitHub MCP.** Anthropic's own GitHub integration replaces
it. Do not re-add `api.githubcopilot.com/mcp/` behind a bespoke `headersHelper`, or a local
`github-mcp-server` launched through `op run` — both existed here, both authenticated someone
else's server with our PAT, and one broke silently for weeks behind a misleading OAuth error. See
`DECISIONS.md`.

## Agents and plugins

| key | what it is for |
|---|---|
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enables the agent fleet. |
| `enabledPlugins` | One marketplace, entries earned by measured use. Check `~/.claude.json` `.skillUsage` before adding or defending one — transcripts are pruned and undercount. |
| `extraKnownMarketplaces` | The `gnar` marketplace. `autoUpdate` stays off: a merge upstream would otherwise be unattended code execution here. |

## What is deliberately absent

| file | why |
|---|---|
| `settings.local.json` | Machine-local override is not a pattern here. `.gitignore` stops it being committed but never stopped it existing — Claude Code writes one itself on "always allow", and one carrying `Bash(gh api *)` in `permissions.allow` sat unreviewed because git was told to ignore it. boom's `absent` resource removes it on every sync and fails `boom verify` if one reappears; removal is a displacement into the run's backup tree, so `boom rollback` restores it — it records a permission someone actually approved. |

If you want a setting, it goes in the committed `settings.json` where it can be
reviewed. If you want it on one machine only, that is the case this setup has
decided not to support.

## Subprocess credential scrubbing

| key | what it is for |
|---|---|
| `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | Strips Anthropic and cloud-provider credentials from *all* subprocesses, unconditionally. This is the layer that reaches past `permissions.deny` and `op-guard.sh`: both of those gate the *command* that resolves a secret, and neither can do anything once the value is already in the environment of a process that then prints it. |

**There is no `sandbox` block, deliberately.** One was written and carried six
`credentials.envVars` entries and four `filesystem.denyRead` paths — none of
which ever ran, because `sandbox.enabled` was never set and the sandbox is
opt-in. It sat in that state from the commit that added it (titled *DO NOT
MERGE UNTIL VERIFIED*) until it was removed; two commits in between found it
inert and left it. Describing a control is not the control.

If it is ever reinstated, the reinstating change must set `sandbox.enabled`
in the same commit, and two things are worth knowing first.

**It is not the `~/.ssh` rule it looks like.** `~/.ssh/` on this machine holds
`id_ed25519.pub`, `known_hosts` and `allowed_signers` — no private key. Signing
goes through 1Password's agent socket (`ssh/config` `IdentityAgent`). A
`~/.ssh/id_*` entry is cheap insurance against a key appearing there later, not
the thing such a block would be for. The env-var masking is.

**It can break `git push` silently.** `.gitconfig` sets `helper = osxkeychain`
globally and `!gh auth git-credential` for GitHub, and `op-agent` runs as a
credential helper. A sandbox that blocks the keychain read those depend on
produces "git is broken", not "the sandbox is wrong". Verify with a real push
before trusting it.

## Behaviour

| key | what it is for |
|---|---|
| `outputStyle` | `Proactive` — execute, assume, don't ask. Advisory prose, never a safety control. |
| `askUserQuestionTimeout` | The default is *never*; bounded because unattended sessions would otherwise block forever. |
| `inputNeededNotifEnabled` | Surfaces a waiting prompt, which matters once prompts are not suppressed. |

## Interface

| key | what it is for |
|---|---|
| `editorMode` + `vimInsertModeRemaps` | vim keys; `jj` to escape. |
| `statusLine` / `subagentStatusLine` | The Gnar statusline scripts. |
| `voice` | Push-to-talk. |
| `theme` / `tui` / `verbose` / `showTurnDuration` / `terminalProgressBarEnabled` / `skipWorkflowUsageWarning` | Appearance and noise. `skipWorkflowUsageWarning` is the exception to this file's own rule and stays anyway: it is undocumented, marked `@internal`, and absent from the published JSON schema, so by the usual test it should go — but the app WRITES IT BACK when the warning is accepted, and this file is tracked and symlinked into `~/.claude/`. `boomfile.toml` carries a `verify` step asserting `dot-claude/` is clean, so removing the key buys one clean commit and then a permanently red `boom verify` the next time the app rewrites it. A key you cannot keep out is not a key you can delete. Each of the others is a deletion candidate: the cheap test is to remove them, run one session, and restore only what you notice missing — a UI regression is instant and free to revert, where a documented default expires. |
| `$schema` | Editor completion for this file. |
