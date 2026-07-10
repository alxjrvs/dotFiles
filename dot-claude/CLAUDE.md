# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`, vim keys); Claude Code matches via `editorMode: vim`
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

`~/.claude/settings.json` (symlinked from the dotFiles repo) is minimal by design: only deliberate divergences from defaults. **Don't add settings beyond these without asking** — the enumerated divergence list *is* the contract, so anything in the file must appear in it. CLAUDE.md is advisory context, never enforcement; anything that *must* hold is pinned by `permissions`/hooks/`run` guardrails, not prose.

The full enumeration (agent fleet, permissions/auto-mode, models, plugins, UI, the Spacebase/Ninety MCP keys, commit identity) **and** the agent-secret architecture live in the **`claude-agent-config` skill** — load it when modifying `settings.json`, wiring a new MCP server, or debugging agent secret/credential resolution. It's the single source of truth for those two topics; this file no longer duplicates them.

## Agent worktree & merge workflow

Claude Code isolates background/subagent work into git worktrees by default (`worktree.bgIsolation: "worktree"`, `worktree.baseRef: "fresh"` — both stock defaults per the settings schema, not overridden in `settings.json`). Each agent gets its own `.claude/worktrees/<name>` on a **freshly created branch** off `origin/<default-branch>`, so under normal EnterWorktree operation the primary checkout's `main` is never re-targeted and parallel agents shouldn't collide through that path. In practice a "branch 'main' is already used by worktree" error still recurs in heavy parallel-agent sessions and the exact trigger hasn't been pinned down — candidates include the Agent tool's `isolation: "worktree"` option, `claude --worktree` sessions (the actual thing the `worktree.*` settings block governs, per its schema description — distinct from EnterWorktree), and `botu code cmux` running parallel sessions per repo. **Next time it happens, capture the full error text and which mechanism (background job / `Agent isolation: "worktree"` / `claude --worktree` / cmux) produced it** so this can be root-caused instead of guessed at.

- **Recovery, not yet prevention**: `git worktree list` to see what's checked out where; if something is genuinely pinned to `main` in a second worktree, `git worktree remove <path>` (`--force` if dirty) reclaims it, and `git worktree prune` sweeps entries whose directory is already gone. Never manually `git worktree add <path> main` without `-b <new-branch>` — that's the one confirmed way to force this collision yourself.
- **Stale/crashed worktrees**: a killed session leaves its worktree `locked` (`.git/worktrees/<name>/locked` names the holding PID) instead of reaped. `git worktree list --porcelain` shows the PID; if it's dead, `git worktree unlock <path> && git worktree remove <path>` reclaims it. Never force-remove a worktree whose lock PID is alive — that's another session's in-flight work.
- **Completion = commit → push → PR → auto-merge.** Once an agent's work is committed, pushed, and a PR opened, `gh pr merge --auto --squash --delete-branch` is the preferred way to land it — GitHub's own gated queue (waits on required checks, GitHub performs the merge, deletes the branch) rather than a local `git merge`/`git push` into the shared `main` checkout. Confirmed 2026-07-08: alxjrvs wants this to also cover unattended background jobs, not just interactive sessions — but writing that as a blanket standing pre-authorization in this file was blocked twice by the Claude Code auto-mode "instruction poisoning" classifier (chat confirmation doesn't clear that rule by design). So this is **not yet an enforced policy** — it's a documented intent. If you want background jobs to actually auto-merge without asking, the classifier's own guidance is to add an explicit Bash permission rule for `gh pr merge` in `settings.json`/`settings.local.json`, or run `gh pr merge --auto` yourself when a PR is ready. A literal local `git merge`/`git push` onto `main` is still off-limits regardless.

## Repository merge & branch-protection defaults

alxjrvs's standing preference for his personal repos (confirmed 2026-07-08): **squash-only merges, rebase-preferred branch updates, linear history required, CI must be green before merging.** Apply this when setting up a new repo (e.g. via `ignite:kickoff`) or when asked to align an existing one. This is a **per-repo, explicit-confirmation action**, not a standing authorization to change settings unprompted.

- **Squash-only — no merge commits, no rebase-merge**: `gh api -X PATCH repos/<owner>/<repo> -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false`. This is safe to combine with rebase-*preferred updates* below — they're governed by a different setting (see next bullet), not by `allow_rebase_merge`.
- **Rebase-preferred branch updates**: enable `allow_update_branch=true` (`-F allow_update_branch=true` on the same PATCH) to surface the "Update branch" button. Which method that button offers — merge-commit vs. rebase — is reported to be gated by the branch's `required_linear_history` protection setting (next bullet) rather than by `allow_rebase_merge`, though behavior here has been inconsistent per GitHub community reports, not GitHub's own docs. `required_linear_history` is worth setting regardless, since it's a standalone stated preference (below) independent of whether it also unlocks the rebase-update button. The REST API has no endpoint to force a rebase update itself — only the web UI and `gh pr update-branch --rebase` can do it.
- **Linear history + CI green, via classic branch protection** on the default branch — `enforce_admins: true` because "CI needs to be green" was stated as a firm rule, including for alxjrvs's own merges. For a one-off emergency bypass, disable and re-enable it rather than weakening the default: `gh api -X DELETE repos/<owner>/<repo>/branches/main/protection/enforce_admins` (disable), `gh api -X POST repos/<owner>/<repo>/branches/main/protection/enforce_admins` (re-enable):
  ```
  gh api -X PUT repos/<owner>/<repo>/branches/main/protection --input - <<'EOF'
  {
    "required_status_checks": { "strict": true, "contexts": ["<check-name-1>", "<check-name-2>"] },
    "enforce_admins": true,
    "required_pull_request_reviews": null,
    "restrictions": null,
    "required_linear_history": true,
    "allow_force_pushes": false,
    "allow_deletions": false
  }
  EOF
  ```
  `contexts` must list the repo's actual CI check names (there's no wildcard) — find them from a recent commit: `gh api repos/<owner>/<repo>/commits/main/check-runs --jq '.check_runs[].name'`. `enforce_admins: false` leaves alxjrvs able to bypass in an emergency; flip to `true` only if asked for stricter enforcement.

## Agent secret access

The agent resolves 1Password secrets through a **service account** scoped to the single `claude-agent` vault — no Touch ID, no desktop-app dependency, and the token never enters the model's context (read inline inside the `op-agent` CLI, `op-agent secret op://…`). That vault is the entire blast radius. MCP secrets, git-over-HTTPS auth (a **classic** `repo`+`workflow` PAT resolved via `op-agent git-credential` — classic by necessity, since fine-grained PATs need org-owner approval you lack), and the one-vault model are documented in full in the **`claude-agent-config` skill** and the dotFiles repo `CLAUDE.md`.

**Your own dev work** still uses desktop biometric + `op run`/`op://`/Environments — the service account is the agent's path, not yours.
