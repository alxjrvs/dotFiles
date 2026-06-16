# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`, vim keys); Claude Code uses its default `normal` input mode (no `editorMode` override)
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

Settings (`~/.claude/settings.json`, symlinked from the dotFiles repo) are minimal by design — they carry only deliberate divergences from Claude Code's defaults:

- Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` + in-process `teammateMode`)
- Agent view enabled (Claude Code default — no `disableAgentView` key). Deliberately re-enabled (the key used to be `true`) to use `claude agents`, the `←` entry from any session, `/background`, and `claude --bg` on-demand dispatch — and so `dot ws --app claude` can pre-populate the agent view with one idle background agent per `~/Code` repo (see the dotFiles repo `CLAUDE.md`). Independent of Agent teams above (teams are a separate experimental feature). **Re-evaluate alongside auto mode**: a fleet of background agents in `auto` widens the confused-deputy surface; `dot ws --app claude` launches them *idle* by default to keep that cool until you dispatch work.
- Quieter UI (`showTurnDuration: false`, `terminalProgressBarEnabled: false`) — no per-turn duration line, no terminal progress bar
- Custom statusline (`~/.local/bin/claude-statusline`, from the separate `claude-statusline` repo)
- Auto permission mode (`permissions.defaultMode`) — a deliberate productivity tradeoff: it auto-approves tool calls, removing the per-call human gate. Accepted risk, but **re-evaluate periodically** — it removes the safety net against prompt injection / confused-deputy scenarios, and the user-scope GitHub MCP server widens that surface across all projects. Scope down via a project-level `settings.local.json` for any repo that warrants it. The standing mitigation is **least privilege at the credential boundary**: the GitHub MCP and agent git use fine-grained PATs, and 1Password access is a service account scoped to a single `claude-agent` vault that physically cannot read Personal/Private.
- Commit attribution trailer + input-needed notifications
- Spacebase MCP key resolver (`env.SPACEBASE_API_KEY_COMMAND`) — the gnar `spacebase` plugin's bundled MCP server resolves its API key by running this command in-process (a non-secret `op read` recipe), so no plaintext key ever sits in env and no launch shim is needed. Replaced the old shim + `deniedMcpServers` workaround; needs a plugin version that reads `SPACEBASE_API_KEY_COMMAND` (`TheGnarCo/agent-skills#368`). Paired with three deliberately-empty vars — `SPACEBASE_API_KEY`, `SPACEBASE_URL`, `SPACEBASE_PROJECT_ID` — because the plugin passes them through as `${VAR}`, and Claude Code substitutes the *literal* placeholder for any var undefined in `env`; blank values make them resolve to `""` so the server uses its defaults (run the key command, default URL, auto-bind project) instead of choking on `"${SPACEBASE_URL}"`. Full rationale in the dotFiles repo `CLAUDE.md`.
- Claude's commit identity (`env` `GIT_AUTHOR_*`/`GIT_COMMITTER_*` → `Claude <alxjrvs+claude@gmail.com>`, `GIT_CONFIG_*` → `commit.gpgsign=false` + `credential.https://github.com.helper` repointed to `osxkeychain`): commits Claude makes are authored under a distinct, unsigned identity so they never need a 1Password unlock, while your own terminal git (and `gh`) keep `alxjrvs` + 1Password signing. The credential-helper override means the agent's git-over-HTTPS pushes authenticate with a least-privilege fine-grained PAT cached in the login keychain (read via the stock `osxkeychain` helper) instead of your broad `gh` OAuth token — agent-only, your terminal git is untouched. The `attribution.commit` trailer credits you as co-author. Add `alxjrvs+claude@gmail.com` on GitHub to link these commits to your profile.

Don't add settings beyond these without asking.

## Agent secret access

The agent resolves 1Password secrets through a **service account**, not your desktop biometric session — so a Claude session (interactive *or* headless/cron) gets its secrets with **no Touch ID prompt** and **no dependency on the 1Password desktop app**. This is the 1Password-recommended automation tier ([secure-ai-access](https://www.1password.dev/get-started/secure-ai-access), [developer-quickstart](https://www.1password.dev/get-started/developer-quickstart)).

- **Scope = one vault.** The service account can read only the dedicated `claude-agent` vault (1Password forbids granting a service account access to Personal/Private, which is *why* agent secrets live in their own vault). That vault is the entire blast radius.
- **Token lives in the macOS login keychain** (`security … -s op-claude-agent`), never on disk in plaintext, never in git. `dot sync` (the `op-agent` module) creates the vault + service account and stores the token on first run.
- **The token never enters the model's context.** It's read from keychain *inline* inside each MCP `headersHelper` shim, confined to that one `op` process — so neither the service-account token nor the resolved secret reaches a Bash subprocess, the transcript, or OTEL tool spans. No `claude()` wrapper, no exported env var.
- **Agent git auth uses a cached PAT, not `op`.** The agent's git-over-HTTPS credential is a least-privilege fine-grained PAT that `dot sync` caches in the login keychain; a Claude session reads it via the stock `osxkeychain` helper (no biometric, headless-safe), keeping the agent off your broad `gh` OAuth token.
- **Your own dev work** still uses desktop biometric + `op run`/`op://`/Environments — the service account is the agent's path, not yours. Full secrets model in the dotFiles repo `CLAUDE.md`.
