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
| `permissions.deny` | The deterministic floor; survives auto/bypass mode. Keychain reads, the `op`/`op-agent` verbs that print a secret value, raw key and cloud-credential files, `git credential`. Asserted by value in three gates. |
| `permissions.allow` | Pre-approvals for the completion path: `gh pr merge`, `gh stack merge`, and `op run` — the last only because `op-guard.sh` strips its unsafe variants first. |
| `autoMode.classifyAllShell` | Route every shell command through the classifier, not just arbitrary-exec shapes. |
| `autoMode.allow` / `soft_deny` | Classifier prose rules. Each array must lead with the literal `"$defaults"` or the built-in rules for that section are silently discarded. |
| ~~`autoMode.environment`~~ | **Deliberately absent.** It described one repo's stack while telling the classifier no other orgs existed, in every session on this machine — so it misinformed the control it fed. `autoMode` is ignored in project settings, so a per-project payload cannot be pushed down to the repo it belongs to. If it returns, it names orgs and nothing repo-specific. |
| `hooks` | `PreToolUse` guards (`op-guard`, `worktree-checkout-guard`, `rebase-guard` — in that order), the `PostToolUse` PR reviewer, and the session-start/stop worktree hooks. The hooks are the enforcement; their scripts carry their own reasoning. |

## Identity and git

| key | what it is for |
|---|---|
| `env.GIT_AUTHOR_*` / `GIT_COMMITTER_*` | Agent commits are authored as `Claude`, distinct from your own terminal git. |
| `env.GIT_CONFIG_*` | Disables commit/tag signing for agent commits, and points `credential.helper` at `op-agent git-credential` behind git's 15-minute cache. |
| `attribution.commit` | Adds the co-author trailer. |
| `env.NINETY_API_TOKEN_COMMAND` | Resolves the Ninety PAT from the agent vault on demand. |
| `env.NINETY_API_TOKEN` / `NINETY_BASE_URL` | **Empty strings are load-bearing.** The plugin checks the literal var before the `_COMMAND`, and an unset `${VAR}` is passed through as a literal and read as a real token — producing a misleading 401. |

## Agents and plugins

| key | what it is for |
|---|---|
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enables the agent fleet. |
| `enabledPlugins` | One marketplace, entries earned by measured use. Check `~/.claude.json` `.skillUsage` before adding or defending one — transcripts are pruned and undercount. |
| `extraKnownMarketplaces` | The `gnar` marketplace. `autoUpdate` stays off: a merge upstream would otherwise be unattended code execution here. |

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
