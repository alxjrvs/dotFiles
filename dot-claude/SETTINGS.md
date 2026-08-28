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
| `permissions.allow` | Pre-approvals for the completion path: `gh pr merge`, `gh stack merge`, and `op run` — the last only because `op-guard.sh` strips its unsafe variants first. |
| `autoMode.classifyAllShell` | Route every shell command through the classifier, not just arbitrary-exec shapes. |
| `autoMode.allow` | Classifier prose rules — routine verify commands. It must lead with the literal `"$defaults"` or the built-in rules are silently discarded. A sibling `soft_deny` is supported and deliberately unset: the built-in defaults already cover force push, `curl \| bash`, production deploys and exfiltration. |
| ~~`autoMode.environment`~~ | **Deliberately absent.** It described one repo's stack while telling the classifier no other orgs existed, in every session on this machine — so it misinformed the control it fed. `autoMode` is ignored in project settings, so a per-project payload cannot be pushed down to the repo it belongs to. If it returns, it names orgs and nothing repo-specific. |
| `hooks` | `PreToolUse` guards (`op-guard`, `worktree-checkout-guard`, `rebase-guard` — in that order), the `PostToolUse` PR reviewer, and the worktree hooks: `worktree-freshness` + `worktree-port` at session start, `worktree-publish` at Stop/SessionEnd. The hooks are the enforcement; their scripts carry their own reasoning. |

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

## Sandbox

| key | what it is for |
|---|---|
| `sandbox.credentials.envVars` | The reason this block exists. `permissions.deny` and `op-guard.sh` both gate the *command* that resolves a secret; neither can do anything once the value is in the environment of a process that then prints it. Seatbelt-enforced masking is the only layer that reaches there, and it is the countermeasure for the transcript leak in `DECISIONS.md`. |
| `sandbox.filesystem.denyRead` | The Bash path to a credential FILE. `permissions.deny`'s `Read(~/.ssh/id_*)` gates the Read tool only — `cat` was never covered by it. |

Two things worth knowing before editing this block.

**It is not the `~/.ssh` rule it looks like.** `~/.ssh/` on this machine holds
`id_ed25519.pub`, `known_hosts` and `allowed_signers` — no private key. Signing
goes through 1Password's agent socket (`ssh/config` `IdentityAgent`). The
`~/.ssh/id_*` entry is cheap insurance against a key appearing there later, not
the thing this block is for. The env-var masking is.

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
| `theme` / `tui` / `verbose` / `showTurnDuration` / `terminalProgressBarEnabled` / `skipWorkflowUsageWarning` | Appearance and noise. Each is a deletion candidate: the cheap test is to remove them, run one session, and restore only what you notice missing — a UI regression is instant and free to revert, where a documented default expires. |
| `$schema` | Editor completion for this file. |
