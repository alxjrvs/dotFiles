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

## Sandbox

| key | what it is for |
|---|---|
| `sandbox.credentials.envVars` | The reason this block exists. `permissions.deny` and `op-guard.sh` both gate the *command* that resolves a secret; neither can do anything once the value is in the environment of a process that then prints it. An OS-enforced boundary is the only layer that reaches there, and it is the countermeasure for the transcript leak in `DECISIONS.md`. `mode: "deny"` unsets the variable before each sandboxed command. |
| `sandbox.filesystem.denyRead` | The OS-level path to a credential FILE. The reason recorded here until 2026-08-28 — that `Read()` deny rules gate the Read tool only and never covered `cat` — is no longer true: deny rules now *"apply to Claude's built-in file tools and to file commands Claude Code recognizes in Bash, such as `cat`, `head`, `tail`, and `sed`."* The block still earns its place on the half that remains uncovered: those rules *"don't apply to arbitrary subprocesses that read or write files indirectly, like a Python or Node script that opens files itself."* That is what an OS boundary reaches and a permission rule cannot. |
| ~~`env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`~~ | **Deliberately absent.** Set 2026-06-05 as the half of this block that worked without `sandbox.enabled`; removed 2026-08-31. Its name list matches no variable this machine sets, and omits the three it does (`GITHUB_TOKEN`, `GH_TOKEN`, `NPM_TOKEN`) — so it scrubbed nothing while silently forcing every session's permission mode to `default`. See DECISIONS.md, *the credential scrub was also a permission-mode switch*. Do not re-add it to get the scrub: the flag that enables the scrub is the flag that forces the mode. |

**None of the `sandbox.*` block does anything until `sandbox.enabled` is `true`,
and it is not set here.** The sandbox is opt-in, and both sub-blocks affect
sandboxed Bash commands only. Enabling it is deliberately a separate change from
getting its contents right, because it is the one setting here that can break a
working machine. See `DECISIONS.md` for why the modes read `deny` rather than
`mask`.

Two more things worth knowing before editing this block.

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
| `theme` / `tui` / `verbose` / `showTurnDuration` / `terminalProgressBarEnabled` / `skipWorkflowUsageWarning` | Appearance and noise. `skipWorkflowUsageWarning` is the exception to this file's own rule and stays anyway: it is undocumented, marked `@internal`, and absent from the published JSON schema, so by the usual test it should go — but the app WRITES IT BACK when the warning is accepted, and this file is tracked and symlinked into `~/.claude/`. `boomfile.toml` carries a `verify` step asserting `dot-claude/` is clean, so removing the key buys one clean commit and then a permanently red `boom verify` the next time the app rewrites it. A key you cannot keep out is not a key you can delete. Each of the others is a deletion candidate: the cheap test is to remove them, run one session, and restore only what you notice missing — a UI regression is instant and free to revert, where a documented default expires. |
| `$schema` | Editor completion for this file. |
