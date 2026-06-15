# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`, vim keys); Claude Code uses its default `normal` input mode (no `editorMode` override)
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

Settings (`~/.claude/settings.json`, symlinked from the dotFiles repo) are minimal by design — they carry only deliberate divergences from Claude Code's defaults:

- Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` + in-process `teammateMode`)
- Agents view disabled (`disableAgentView: true`) — turns off the `claude agents` view / `--bg` / `/background` on-demand dispatch. Independent of Agent teams above (teams stay on; only the view is off).
- Quieter UI (`showTurnDuration: false`, `terminalProgressBarEnabled: false`) — no per-turn duration line, no terminal progress bar
- Custom statusline (`~/.local/bin/claude-statusline`, from the separate `claude-statusline` repo)
- Auto permission mode (`permissions.defaultMode`) — a deliberate productivity tradeoff: it auto-approves tool calls, removing the per-call human gate. Accepted risk, but **re-evaluate periodically** — it removes the safety net against prompt injection / confused-deputy scenarios, and the user-scope GitHub MCP server widens that surface across all projects. Scope down via a project-level `settings.local.json` for any repo that warrants it. Two standing mitigations now layer: **least privilege at the credential boundary** (the GitHub MCP and agent git use fine-grained PATs; 1Password access is a service account scoped to a single `claude-agent` vault that physically cannot read Personal/Private), and **OS containment** via the lightweight bash sandbox (below).
- Commit attribution trailer + input-needed notifications
- Silenced spacebase bundled MCP server (`deniedMcpServers`) — the gnar `spacebase` plugin ships a bundled MCP server that can't resolve its key (no `op` hook for stdio plugin servers), so the user-scope `op`-resolving shim shadows it and the bundled one fails to connect. The `deniedMcpServers` entry suppresses that cosmetic failure. **Fragile by necessity** — the denylist matches only an exact, fully-expanded `serverCommand`, so the entry hardcodes the version-pinned plugin path and `/Users/jarvis`; it silently stops matching (failure reappears) on every plugin version bump. Full rationale + the re-pin instruction live in the dotFiles repo `CLAUDE.md`.
- Claude's commit identity (`env` `GIT_AUTHOR_*`/`GIT_COMMITTER_*` → `Claude <alxjrvs+claude@gmail.com>`, `GIT_CONFIG_*` → `commit.gpgsign=false` + `credential.https://github.com.helper` repointed to `osxkeychain`): commits Claude makes are authored under a distinct, unsigned identity so they never need a 1Password unlock, while your own terminal git (and `gh`) keep `alxjrvs` + 1Password signing. The credential-helper override means the agent's git-over-HTTPS pushes authenticate with a least-privilege fine-grained PAT cached in the login keychain (read in-box via the stock `osxkeychain` helper, since `op` can't run inside the sandbox) instead of your broad `gh` OAuth token — agent-only, your terminal git is untouched. The `attribution.commit` trailer credits you as co-author. Add `alxjrvs+claude@gmail.com` on GitHub to link these commits to your profile.
- Lightweight bash sandbox (`sandbox.enabled` + `autoAllowBashIfSandboxed` + `allowUnsandboxedCommands:false`) — OS-level containment (macOS Seatbelt) as a standing safety net under auto mode: filesystem writes confined to the workdir, no dynamic escape (a blocked command fails hard — unattended-safe). Deliberately **carve-out-free**: no `op`/1Password-specific config, because secrets resolve *outside* the sandbox. Known boundaries (all measured): `op` can't run in-box (the sandbox MITM-proxies TLS; `op` pins system trust → `errSecNotTrusted`), so MCP auth resolves outside it and agent git auth uses the `osxkeychain`-cached PAT (keychain reads work in-box); `.claude/` is OS-write-protected in-box. Repos needing system-wide writes or in-box `op` (e.g. the dotFiles installer) opt out with a committed project `.claude/settings.json` (`sandbox.enabled:false`).

Don't add settings beyond these without asking.

## Agent secret access

The agent resolves 1Password secrets through a **service account**, not your desktop biometric session — so a Claude session (interactive *or* headless/cron) gets its secrets with **no Touch ID prompt** and **no dependency on the 1Password desktop app**. This is the 1Password-recommended automation tier ([secure-ai-access](https://www.1password.dev/get-started/secure-ai-access), [developer-quickstart](https://www.1password.dev/get-started/developer-quickstart)).

- **Scope = one vault.** The service account can read only the dedicated `claude-agent` vault (1Password forbids granting a service account access to Personal/Private, which is *why* agent secrets live in their own vault). That vault is the entire blast radius.
- **Token lives in the macOS login keychain** (`security … -s op-claude-agent`), never on disk in plaintext, never in git. `dot sync` (the `op-agent` module) creates the vault + service account and stores the token on first run.
- **The token never enters the model's context.** It's read from keychain *inline* inside each MCP `headersHelper` shim, confined to that one `op` process — so neither the service-account token nor the resolved secret reaches a Bash subprocess, the transcript, or OTEL tool spans. No `claude()` wrapper, no exported env var.
- **This works because MCP auth resolves *outside* the bash sandbox.** Inside the sandbox `op` can't reach 1Password (the sandbox MITM-proxies TLS; `op` pins system trust). So the two in-box needs are handled without `op`: **git auth** reads an `osxkeychain`-cached PAT (populated out-of-band by `dot sync`); arbitrary in-box `op read`/`op run` is simply unavailable — run it from your terminal or a sandbox-opted-out repo.
- **Your own dev work** still uses desktop biometric + `op run`/`op://`/Environments — the service account is the agent's path, not yours. Full secrets + sandbox model in the dotFiles repo `CLAUDE.md`.
