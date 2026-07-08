---
name: secrets-architecture
description: Reference for this repo's agent-secret architecture — the op-agent CLI verbs, the MCP secrets pattern, and how agent git auth resolves its PAT. Invoke when adding/debugging an MCP server, wiring a new secret, or touching hooks/op-agent.sh or agent git auth.
---

## Agent secrets — the `op-agent` CLI

`hooks/op-agent.sh` is the single script for all agent-1Password machinery, dispatched by verb:

- `op-agent provision` — idempotently ensures the `claude-agent` vault, a per-host service account with `read_items` on only that vault, and its token in the macOS login keychain (`op-claude-agent`); also confirms the `Claude Git PAT` vault item exists (a fresh-machine setup signal — the PAT is resolved on demand, never cached). Run via `on apply op-agent provision`. Foreground-only first run (minting authorizes through the desktop app).
- `op-agent status` — reports keychain token presence (`on verify`).
- `op-agent secret op://ref` — reads one secret value to stdout via the SA, the single read primitive for consumers that want a raw value (e.g. the spacebase `*_COMMAND`). **The ref is an argument, not a per-service file.** It sources the SA token from the keychain inline (no biometric, headless-safe), confined to one short-lived process so neither the token nor the secret reaches a Bash subprocess, the transcript, or OTEL. Follows the `op read` contract: value on success, nothing + nonzero on failure (so a failed read leaves the consumer's var empty and it falls through to its own default).
- `op-agent header op://ref` — MCP `headersHelper` for HTTP servers that bearer-authenticate (the GitHub MCP at `api.githubcopilot.com/mcp/` and the Render MCP). Resolves the vaulted token via the same SA path as `secret` and emits `{"Authorization":"Bearer <token>"}`; on any failure emits `{}` (valid JSON, no header) so the client never sees a malformed response. **The ref is an argument, not a per-service file.**
- `op-agent git-credential get` — git credential helper (scoped to `https://github.com` in the agent git config). Resolves the `Claude Git PAT` vault item via the same SA path as `secret` and emits `username=x-access-token` + `password=<pat>`; `store`/`erase` are no-ops (the vault is the source of truth). This is the canonical native-hook-fed-by-`op` pattern applied to git.

Every verb has a live consumer — no speculative surface: the GitHub and Render MCP servers' `headersHelper` formats its Bearer line from `op-agent header <its op:// ref>`.

## MCP secrets — one canonical pattern

Servers we control launch via 1Password's `op run --env-file=.env -- <server>` with `op://` references in a committable `.env` (`botu mcp add`). Plugin-bundled stdio servers use their own `*_COMMAND` resolver (spacebase's `SPACEBASE_API_KEY_COMMAND` → `op-agent secret op://claude-agent/…`; gninety's `NINETY_API_TOKEN_COMMAND` → `op-agent secret op://claude-agent/gninety/credential`); HTTP servers (the GitHub and Render MCP) format their `headersHelper` from `op-agent header op://…`. Plugins that check a literal-token env var *before* their `_COMMAND` (both spacebase and gninety do) also need that var pinned to `""` in `settings.json`, else Claude Code's unset-`${VAR}` passthrough feeds the literal placeholder in as the token. **Never write a `${VAR}` placeholder into a git-tracked `.mcp.json`/`.env`** (a later `claude mcp add` can expand it). `botu verify` and the `git-template` pre-commit both fail on a `${VAR}` in a tracked `.mcp.json` and on a resolved-token literal in any tracked `.mcp.json`/`.env`.

## Agent git auth

Git's native `credential.helper` is pointed at `op-agent git-credential` (fronted by git's `cache --timeout=900` helper), so the agent resolves its PAT from the `claude-agent` vault on demand — the **same single `op` primitive as every other agent secret**, the canonical "tool's own native hook fed by `op`" pattern (git's hook is the credential helper). The PAT lives only in 1Password: no keychain cache, no second mechanism.

The vault token is a **classic** `repo`+`workflow` PAT, **SSO-authorized** for the orgs the agent pushes to — *not* a fine-grained one, and that's deliberate. Fine-grained PATs are gated on org-owner enablement + approval, which `alxjrvs` lacks for the orgs in play; a classic token is bounded by your own access and is self-SSO-authorizable (member-level), so it's the narrowest credential that actually reaches those org repos. Least-privilege therefore rests on the SA-scoped vault + a token expiry, not on per-repo scoping. The helper is token-agnostic, so rotation/scope changes are just an update to the `Claude Git PAT` vault item — no code change. **Do not "downgrade" this to a fine-grained PAT** expecting org access; it will silently lose the org repos.

Headless, no biometric (SA token via `securityd`); the `cache` helper amortizes the per-op round-trip; and because the resolve path is `securityd` + network rather than a keychain *file* read, it survives a sandbox `credentials.files` deny on the keychain. Wired agent-only via `dot-claude/settings.json` `GIT_CONFIG_*`. Your own terminal git keeps its `gh` helper + 1Password signing. (Agent commits are unsigned by design — if a target org enforces *require signed commits*, the agent would also need a signing path; none configured today.)
