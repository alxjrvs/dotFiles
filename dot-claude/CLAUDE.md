# User-Level Claude Code Instructions

This file loads into **every session before any work starts**, so it is kept to what a session
must *obey*. The reasoning behind it — incidents, postmortems, removed settings, root-cause
writeups — lives in `DECISIONS.md`, and Claude Code feature notes live in `REFERENCE.md`. Both
sit beside this file in the dotFiles repo (on this machine:
`~/.local/state/boom/config-repo/dot-claude/`) and **neither is symlinked into `~/.claude/`**, so
they cost nothing per session — read them on demand. When you change something here, record *why*
in `DECISIONS.md`.

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`, vim keys); Claude Code matches via `editorMode: vim`
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

`~/.claude/settings.json` (symlinked from the dotFiles repo) is minimal by design: only
deliberate divergences from defaults. **Don't add settings beyond these without asking** — the
enumeration below is the contract, so anything in the file must appear here. CLAUDE.md is
advisory context, never enforcement; anything that *must* hold is pinned by
`permissions`/hooks/`run` guardrails, not prose.

Rules that apply whatever you are touching:

- **No local override layer.** Tighten per-repo in that repo's **checked-in**
  `.claude/settings.json`, never a machine-local `settings.local.json`. A `boom verify` step
  fails while boom's config-repo clone is dirty, so this is enforced, not merely asserted.
- **Key order in `settings.json` is Claude Code's, not ours.** The client rewrites the whole
  file when any setting changes through `/config`. Don't re-sort by hand — reconcile the
  enumeration *after* the client edits, keeping whatever order it last wrote.
- **Installing a plugin dirties this file**, and `boom verify` fails until it is committed.
  That is the clean-tree check working: a plugin is a new capability surface (an MCP server,
  skills, arbitrary code from a marketplace), so it gets enumerated here before it counts as
  adopted.
- **Never echo a secret.** Always redirect to `>/dev/null` and test the exit code. If a token
  is ever printed, rotate it.
- **Any new item in the `claude-agent` vault must be space-free `kebab-case`** — every `op://`
  ref is re-parsed by `sh -c`, so a space silently breaks resolution.

### Current divergences

- **Agent fleet** — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: in-process`
  (Agent teams, experimental). Agent view is left on (no `disableAgentView`) so `claude agents`,
  the `←` entry, `/background`, `claude --bg`, and `boom code claude` work with no idle fleet.
  **Re-evaluate with auto mode** — a standing fleet widens the confused-deputy surface;
  dispatch-on-demand keeps it minimal.
- **Permissions** — `defaultMode: auto` + `skipAutoPermissionPrompt` auto-approve tool calls: a
  productivity tradeoff that removes the per-call human gate. Accepted risk, **re-evaluate
  periodically.** `autoMode.classifyAllShell` routes *every* Bash/PowerShell command through the
  auto-mode classifier, not just arbitrary-code-exec patterns — the classifier still runs and can
  deny under `skipAutoPermissionPrompt`, which suppresses only the interactive prompt, not
  classification.
  - `permissions.deny` is the deterministic floor that survives `auto`/bypass (deny is evaluated
    first): keychain reads of the agent token (`security find-generic-password`), raw private-key
    and cloud-credential files, and the Bash path to secret resolution — **scoped to the binary,
    not the verb**: `Bash(op:*)`, `Bash(op-agent:*)`, `Bash(~/.local/bin/op-agent:*)`,
    `Bash(git credential:*)`. Denying those breaks nothing — the `*_COMMAND` resolvers and `credential.helper` are exec'd by the MCP
    client and by git, and boom's `run` steps spawn `op-agent` as a child of boom, none of which
    go through the Bash tool. The one real cost: asking Claude in-session to run
    `op run -- npm publish` is now denied too. Run it from your own terminal.
  - **Why the binary and not the verb** (changed 2026-08-05). Enumerating verbs is what failed:
    the list blocked `op-agent secret`, `op read` and `op item get` but not `op-agent header` or
    `op-agent git-credential get` — both of which print a live credential to stdout, and stdout is
    model context. `op-agent header` is the command that leaked a PAT into a transcript on
    2026-07-25 (`DECISIONS.md`), so the one verb with a confirmed incident was the one left
    reachable, while `op-agent secret`, which never leaked, was blocked twice. `git credential
    fill` reached the same PAT with no `op` command at all. Four entries out, four in.
  - **Matching is token-aware, not raw string prefix** — verified: `op readx` runs despite a
    `Bash(op read:*)` rule, because `readx` is a different token than `read`. Two consequences,
    and they pull opposite ways. Good: `Bash(op:*)` matches the `op` binary only and does **not**
    catch `open`. Bad: it does not catch a *differently spelled path* to the same binary either,
    which is why `~/.local/bin/op-agent` is enumerated separately — that is the spelling this very
    file uses in its `*_COMMAND` values, so it is the one most likely to be copied. Absolute paths
    remain uncovered and are not coverable here.
  - The floor now has a **regression check** in all three enforcement points (`boomfile.toml`
    `[[section.check]]`, `lefthook.yml`, `lint.yml`). Before that it had none: the whole `deny`
    array could be deleted and every gate stayed green. Note the boomfile patterns are
    regex-escaped — these checks take JS regexes, and bare `Bash(op:*)` matches "Bashop".
  - Be honest about what that buys: **defense-in-depth, not a boundary.** `git push` still
    authenticates with the same PAT; deny matches command *spelling*, so an absolute path
    (`/opt/homebrew/bin/op …`) is not covered and nothing in the permission model can cover it;
    and everything unmatched falls to the auto-mode classifier, which is probabilistic and was
    observed deciding two identically-shaped commands differently. Least privilege rests on the
    PAT's scopes and the SA-scoped vault (see *Agent secret access*).
- **Models** — no `model` or `advisorModel` pinned: sessions use Claude Code's built-in default
  and run no server-side advisor. Fable/Opus/Sonnet stay freely selectable per-session (`/model`)
  and per-subagent. **Fable must never be pinned as the default** — a drift check fails if it is
  (e.g. via `/model`'s "set as default", which rewrites this file).
- **Plugins** — `enabledPlugins` runs two marketplaces. **Both are `autoUpdate: false`** (changed
  2026-08-05): with `autoUpdate` on, a merge to either upstream's main was unattended code
  execution here — new skills, new MCP servers, arbitrary code from a marketplace — reaching a
  session that runs `defaultMode: auto` with credentials available. The cost is updating by hand;
  that is the trade, and it is the same argument the *Standing threats* section already makes for
  keeping the plugin surface minimal.
  - `extraKnownMarketplaces.gnar` → `TheGnarCo/agent-skills`: `audit`, `ignite`,
    `spacebase`, `gninety`; plus `typescript-lsp`, `commit-commands`, `frontend-design`, `expo`
    from `claude-plugins-official`. No "must-install" set exists — each entry earns its place by
    use (`ideate`/`toolkit` deliberately off). Drop `expo` if the Expo work it serves stops.
  - `extraKnownMarketplaces.binfinite` → `BinfiniteLLC/binfinite-app`, enabling
    `binfinite-context@binfinite`. **A private repo**, so it silently fails to load anywhere the
    credential helper can't reach `BinfiniteLLC` — a CI/Cowork box gets no plugin and no error
    worth noticing. Its `project-registry` skill is a **resolver, not a store** —
    it holds the app→site→EAS-app→Convex mapping and routes everything else to the
    Netlify/Expo/Convex MCPs, so it must never accumulate copied prose. Drop it if Binfinite work
    stops.
- **UI / QoL** — custom `statusLine` + `subagentStatusLine` (`~/.local/bin/claude-*statusline`,
  from [`TheGnarCo/claude-statusline`](https://github.com/TheGnarCo/claude-statusline));
  `editorMode: vim` with `vimInsertModeRemaps: {"jj": "<Esc>"}` (`"<Esc>"` is the only supported
  target, added in 2.1.208); `verbose: true`; quieter UI (`showTurnDuration` and
  `terminalProgressBarEnabled` off, `autoScrollEnabled: true`); `tui: "fullscreen"` +
  `theme: "auto"`; `skipWorkflowUsageWarning`; `inputNeededNotifEnabled` + the
  `attribution.commit` trailer.
- **Voice** — `voiceEnabled: true` + `voice: { enabled: true, mode: "hold" }` (push-to-talk).
- **Auto-merge permission** — `permissions.allow` carries `Bash(gh pr merge:*)`. This is the
  classifier's own prescribed mechanism for letting background/unattended jobs land a finished
  PR. It authorizes `gh pr merge --auto` — GitHub's gated queue, which still waits on required
  checks — and does **not** loosen the "no direct `git` merge/push onto `main`" rule.
  `permissions.allow` also carries **`Bash(gh stack merge:*)`** (added 2026-08-04), for the same
  reason applied to stacks: `gh pr merge` literally cannot merge a stack, so without this the
  preferred shape for large agent work had no completion path at all. It is a **narrower**
  authorization than it looks — stack merges cannot bypass merge requirements, so on a repo with
  the `agent-friendly-repo` ruleset it can only land a stack GitHub already considers mergeable.
  The real caveat is timing, not privilege: queue-less, it merges *now* rather than waiting for
  green, so an unattended job on a queue-less repo submits the stack and hands it back instead of
  merging speculatively. That restraint is `ship`'s rule, and it is prose — the permission does
  not enforce it.
- **Worktree-checkout guard** — `PreToolUse` hook (matcher `Bash` →
  `~/.claude/hooks/worktree-checkout-guard.sh`, ordered *before* rebase-guard). Denies a
  `git checkout/switch <branch>` that would fail with "'<branch>' is already used by worktree".
  It tokenizes the command (so `echo git checkout main` and commit messages mentioning it pass),
  then asks git directly — `git worktree list --porcelain | grep -qxF "branch refs/heads/<target>"`
  — denying only when the branch is genuinely held elsewhere and is not the current HEAD. Steers
  to a read-only inspect (`git log <branch>`). Fails **open** on a non-repo cwd or parse error.
- **Rebase-before-push guard** — `PreToolUse` hook (matcher `Bash` →
  `~/.claude/hooks/rebase-guard.sh`). Blocks `git push` / `gh pr create` when the branch is
  **behind** its target, returning `permissionDecision: "deny"` with a rebase instruction. It
  also denies a direct `git push` of the default branch — a bare push while HEAD *is* the
  default, or an explicit `<remote> <default>` / `…:<default>` refspec — enforcing "no direct
  push to `main`". `gh pr create --base <parent>` is judged against that base, so stacked PRs are
  not flattened, and a leading `cd <path>` is honored via `git -C`. It only checks and blocks,
  never rebases itself. Fails **open** on a non-repo cwd, missing `jq`, unresolvable target, or
  parse error — a guard must never wedge the agent. `deny` works even under `defaultMode: auto`
  (PreToolUse fires before the permission classifier) and applies to every Claude session, never
  to plain terminal `git`.
  - **Both guards have a regression suite** (`dot-claude/hooks/tests/`, wired into `lint.yml` and
    pre-commit): 33 hermetic cases against throwaway git fixtures, under 2s.
    **Add a case before changing a guard.**
- **Recorded PR review (`PostToolUse`)** — `~/.claude/hooks/pr-review.sh` fires after
  `gh pr create` / `git push` / **`gh stack submit`**; when the repo is in `PR_REVIEW_REPOS` (a bare **owner**, covering
  every repo under it, or a fully-qualified `owner/repo`; defaults to `TheGnarCo BinfiniteLLC
  SalvageUnion-io RANDSUM alxjrvs`) it runs the adversarial review locally and posts it as a real
  PR review plus a `claude-review` commit status. It backgrounds itself immediately so it can
  never block a turn, and a failed reviewer reports `success` with "review unavailable (not a
  verdict)" rather than masquerading as a clean bill of health. `if` is a field on an individual
  hook handler, never on the matcher group — one rule per handler, so three commands means three
  handlers. The `gh stack submit` arm exists because that command matches *neither* of the other
  two — it creates PRs via the Stacks API and pushes inside the gh process, so no `git push` Bash
  call ever reaches PostToolUse — which meant stacking silently routed the largest changes around
  the reviewer. It reviews the **checked-out layer only**, not the whole stack, so a green
  `claude-review` on one layer is not a verdict on the others. **Advisory until a day-30 finding
  rate justifies requiring it: above ~1 finding per 10 PRs that changed code, promote; below,
  delete it and close the question.**
- **Spacebase MCP key** — `SPACEBASE_API_KEY_COMMAND` resolves the gnar `spacebase` plugin's key
  in-process via `op-agent secret op://…`. Paired with deliberately-empty `SPACEBASE_API_KEY` /
  `_URL` / `_PROJECT_ID` so the plugin's `${VAR}` pass-through resolves to `""` (server defaults)
  instead of a literal `"${VAR}"`. Keep the `op://` ref **quoted** inside the `_COMMAND` value —
  the consumer runs it through `/bin/sh -c`, so a space would word-split it.
- **Ninety (EOS) MCP token** — `NINETY_API_TOKEN_COMMAND` resolves the `gninety` plugin's
  Ninety.io PAT via `op-agent secret op://claude-agent/gninety/credential`. The empty
  `NINETY_API_TOKEN` / `NINETY_BASE_URL` are **load-bearing, not cosmetic**: `auth.ts` checks
  `NINETY_API_TOKEN` *before* the `_COMMAND`, and Claude Code passes an unset `${VAR}` through as
  a literal string, which would be sent as a bearer token and 401. Setting it to `""` makes that
  check falsy so the resolver runs; empty `NINETY_BASE_URL` cleans to the default host.
- **Commit identity** — `GIT_AUTHOR_*`/`GIT_COMMITTER_*` → `Claude <alxjrvs+claude@gmail.com>`;
  `GIT_CONFIG_*` sets `commit.gpgsign`/`tag.gpgsign=false` (Claude's commits are unsigned and
  never need a 1Password unlock) and points `credential.https://github.com.helper` at
  `op-agent git-credential`, fronted by git's `cache --timeout=900` helper. Agent-only — your
  terminal git keeps `alxjrvs` + 1Password signing. The trailer credits you as co-author; add
  `alxjrvs+claude@gmail.com` on GitHub to link these commits.
- **Keep-awake (`SessionStart`)** — `caffeinate -i -w $PPID &`, guarded by `command -v` and
  `|| true`. On battery this machine sleeps after 1 minute idle, so every unplugged session ran
  on a 60-second fuse. `-i` prevents idle sleep only (the display still sleeps); `-w $PPID` ties
  the assertion to the session process so it releases on exit and can never leak past it. Verify
  with `pmset -g assertions | grep PreventUserIdleSystemSleep`.

## Agent worktree & merge workflow

Claude Code isolates background/subagent work into git worktrees by default
(`worktree.bgIsolation: "worktree"`, `worktree.baseRef: "fresh"` — stock defaults, not
overridden). Each agent gets `.claude/worktrees/<name>` on a **freshly created branch** off
`origin/<default-branch>`.

- **A stack of small PRs is the default shape for multi-part work**, via the **official**
  `github/gh-stack` extension (`gh stack`, public preview since 2026-07-30) — installed by the
  dotFiles boomfile's `gh extensions` section, never a same-named community fork.
  `gh stack init` → `gh stack add` per layer → `gh stack submit` (one PR per branch, each based
  on the one below) → `gh stack sync` after a layer lands. It owns the cascading rebase across
  the whole stack, which is the part that is miserable by hand.
  - **Decide the shape before writing code, not at ship time.** Once the work is one large
    commit, splitting it is archaeology. If the plan has separable layers, cut the branches up
    front — that is the entire ergonomic win, and it is unavailable retroactively.
  - **What earns its own layer:** a change that could be reviewed, and reverted, on its own. In
    practice that means a refactor that enables the feature (not the feature), a schema or type
    change ahead of its consumers, a mechanical rename or move separated from behavior, or docs
    separated from code. **What does not:** splitting by file, by commit count, or to hit a size
    target. A layer nobody could review in isolation is not a layer.
  - **Don't stack a single reviewable change.** A one-layer stack is a PR with extra ceremony.
    The test is whether a reviewer would want the layers separately, not whether the diff is big.
  - **Stacks are the default, not a mandate.** When work genuinely resists layering — a change
    that is atomic by nature, or an urgent fix — ship one PR and say why in a sentence. Don't
    manufacture layers to satisfy the rule.
  - `gh stack submit`/`push`/`sync` are **not** matched by the rebase-guard (which tokenizes for
    `git push` / `gh pr create` specifically), so the guard is silent on them. That is not
    permission to publish a stale stack — `gh stack sync` (fetch + cascading rebase + push) is
    the stack-shaped version of the rebase-before-push rule, so run it first.
  - **A stack does not land via `gh pr merge --auto`.** GitHub: "Auto-merge is not supported for
    stacked pull requests", and the legacy merge endpoint `gh pr merge` calls cannot merge a
    stack at all. `gh stack merge [<stack#>|<pr#>]` (the Stacks API) is the only way — it merges
    every PR up to the chosen one all-or-nothing and **cannot bypass** merge requirements, so it
    needs `required_linear_history` and empty `bypass_actors`, which the `agent-friendly-repo`
    checklist already sets. Never enable auto-merge on the bottom PR as a substitute: that lands
    one layer and leaves the rest of the stack rebasing behind it.
  - **Land a stack by watching it green, then merging — no merge queue.** That trade is
    deliberate (`DECISIONS.md`): a queue would buy fire-and-forget but is mutually exclusive with
    the Dependabot auto-merge workflow, since `GITHUB_TOKEN` cannot enqueue. So the completion
    path is `gh pr checks <pr> --watch` on **every** layer, then
    `gh stack merge --yes --squash`. `gh stack merge` waits for nothing — it checks only that
    each PR is open and non-draft, and GitHub evaluates the real rules at merge time, so firing
    it at a pending stack just burns the attempt. If `main` moves while you wait, a `strict`
    policy rejects the merge: `gh stack sync` and retry once, then report rather than loop.
  - Checks are enforced **per PR against the stack's base branch**, so the default-branch ruleset
    governs every layer — no intermediate PR is an unguarded hole, and a required human review
    would block all of them.
  - Stack state lives in `.git/gh-stack` (untracked, per-clone), so a fresh agent worktree does
    not inherit one — `gh stack checkout <stack#|pr#|url|branch>` re-attaches. Run `gh stack view`
    before shipping: a branch that is stacked on GitHub can look unstacked locally.
- **Rebase on the target before pushing.** Before the first `git push` / `gh pr create`:
  `git fetch origin && git rebase origin/<default>` (resolve conflicts; re-push with
  `--force-with-lease` if already pushed). `origin/HEAD` moves while an agent works, so even a
  branch cut from a fresh base can be behind by push time. Do this up front and the rebase-guard
  is a silent no-op; skip it and the guard blocks the push with this same instruction.
- **Completion has two shapes, and the stack one is not a special case.**
  - *Single PR*: commit → push → PR → `gh pr merge --auto --squash`. GitHub waits for green.
  - *Stack*: `gh stack sync` → `gh stack submit` → watch **every** layer green
    (`gh pr checks <pr> --watch`) → `gh stack merge --yes --squash`. Nothing waits for you here,
    so the watch step is mandatory, not diligence.

  Both end at GitHub's own gate; neither is ever a local `git merge`/`git push` into the shared
  `main` checkout. Never `-d`/`--delete-branch`. `delete_branch_on_merge` is enabled
  repo-wide on `alxjrvs/dotFiles` and `alxjrvs/botu`; check `.delete_branch_on_merge` on any
  other repo the agent pushes to and enable it if false. Where it isn't enabled, delete the
  remote branch manually *after confirming the PR merged* (`gh pr view --json state`):
  `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>` — never immediately after an
  `--auto` merge on a not-yet-green PR, since deleting the head branch of a still-open PR closes
  it unmerged and cancels auto-merge. A literal local `git merge`/`git push` onto `main` is
  off-limits regardless.
- **"branch 'main' is already used by worktree"** — two confirmed triggers:
  `gh pr merge --delete-branch` (which is why that flag is banned above), and an agent's
  reflexive `git checkout <default>` inside a linked worktree (now blocked by the
  worktree-checkout guard). If a *new* shape turns up, capture the full error text and the
  mechanism that produced it before assuming it is one of these.
- **Recovery**: `git worktree list` shows what is checked out where; `git worktree remove <path>`
  (`--force` if dirty) reclaims it; `git worktree prune` sweeps entries whose directory is gone.
  Never manually `git worktree add <path> main` without `-b <new-branch>` — that is the one
  confirmed way to force this collision yourself.
- **Stale/crashed worktrees**: a killed session leaves its worktree `locked`
  (`.git/worktrees/<name>/locked` names the holding PID). If that PID is dead,
  `git worktree unlock <path> && git worktree remove <path>`. **Never force-remove a worktree
  whose lock PID is alive** — that is another session's in-flight work.
- **"Worktree kept … has commits that are not pushed anywhere" is usually a false positive.**
  Claude Code's remove guard tests **SHA identity**, and a squash-merge rewrites history, so a
  fully-merged branch's commits exist nowhere by SHA. Reap with `boom code reap`, which re-decides
  by **content** (git patch-id) and removes only worktrees that are clean, unlocked (or locked by
  a dead PID), and either fully pushed or already merged. It deletes the directory, never the
  branch ref, so it cannot lose a commit; `--dry-run` classifies without touching anything; its
  default answer is *keep*. `--push` publishes a clean-but-unpushed worktree first
  (`git push -u origin <branch>`, never forced) so nothing is stuck un-closeable — outward-facing
  by design; dirty trees, live sessions and detached HEADs are never pushed. Runs daily as
  `code reap --push` via `[boom] schedule`; run it by hand any time the backlog bites. The
  one-off escape hatch for a single stuck worktree is the same move manually:
  `git push -u origin HEAD`. `commit-commands:clean_gone` does **not** catch this case (these
  branches have no upstream, so there is no `[gone]` signal).

## Repository merge & branch-protection defaults

Standing preference for personal repos: **squash-only merges, rebase-preferred branch updates,
linear history required, CI green before merging, stacked PRs (`gh stack`) as the default shape
for multi-part work, and no merge queue.** Apply when setting up a new repo (e.g. via
`ignite:kickoff`) or when asked to align an existing one. This is a **per-repo,
explicit-confirmation action**, not standing authorization to change settings unprompted.

**The executable version is the `agent-friendly-repo` skill**
(`dot-claude/skills/agent-friendly-repo/`) — it reads current state, diffs against the checklist,
asks, then applies the merge settings + ruleset. (It can still build a merge queue, but that step
is skipped by default — see below.) Use the skill; the recipes below are the reference it encodes.

- **Squash-only**: `gh api -X PATCH repos/<owner>/<repo> -F allow_squash_merge=true
  -F allow_merge_commit=false -F allow_rebase_merge=false`. Safe to combine with
  rebase-preferred updates — those are governed by a different setting.
- **Rebase-preferred branch updates**: `-F allow_update_branch=true` surfaces the "Update branch"
  button. Which method it offers is gated by `required_linear_history`, not by
  `allow_rebase_merge`. The REST API cannot force a rebase update — only the web UI and
  `gh pr update-branch --rebase` can.
- **Linear history + CI green via a ruleset (preferred) — one mechanism, not classic *and*
  ruleset.** GitHub takes the *union* of the two, so having both is a footgun (edit one, the
  other silently still applies). Make the ruleset the single source of truth and delete the
  redundant classic protection (`gh api -X DELETE repos/<owner>/<repo>/branches/<branch>/protection`)
  once it supersets. Rules for the default branch: `required_linear_history`, `non_fast_forward`,
  `deletion`; `required_status_checks` pointing at a **single aggregate gate job** (an
  `if: always()` job that `needs:` every other job — not each individual check, which strands
  required checks in "pending" on path-filtered PRs); **no required human PR reviews** (agents
  can't approve their own PRs, so a required review blocks auto-merge forever); and
  `bypass_actors: []` so nobody bypasses, admins included. For a one-off emergency,
  disable+re-enable the ruleset rather than adding a standing bypass. Find real check names via
  `gh api repos/<owner>/<repo>/commits/<branch>/check-runs --jq '.check_runs[].name'`.
  - The classic-protection fallback, for repos that cannot use rulesets, is in `DECISIONS.md`.
- **Merge queue — deliberately NOT used.** It is the only fire-and-forget path for a stack, but
  it is mutually exclusive with the Dependabot auto-merge workflow (`GITHUB_TOKEN` cannot
  enqueue) and it carries a `merge_group:` CI sequencing hazard that hangs every PR if the
  trigger isn't on the default branch first. The call: keep Dependabot, land stacks by watching
  them green and merging directly. **Don't propose a queue as the fix for having to wait** — the
  waiting is the accepted cost. The `agent-friendly-repo` skill still knows how to set one up if
  a repo ever justifies it.
- **Dependabot auto-merge** (opt-in, per repo): no required human review already unblocks it, but
  nothing fires `--auto` for the bot, so it takes a one-job workflow
  (`.github/workflows/dependabot-auto-merge.yml` here is the reference). `on: pull_request` with
  an explicit `permissions:` block — never `pull_request_target`. Gate on an **allowlist**
  (`update-type == minor || == patch`), never `!= major`. It cannot coexist with a merge queue
  (`GITHUB_TOKEN` can't add a PR to one), and it silently never fires if CI needs Actions secrets
  (Dependabot runs get only *Dependabot* secrets). Details in `DECISIONS.md`.

## Agent secret access

The agent resolves 1Password secrets through a **service account**, not your desktop biometric
session — so a Claude session (interactive *or* headless/cron) gets its secrets with no Touch ID
prompt and no dependency on the 1Password desktop app. This is the 1Password-recommended
automation tier.

- **Scope = one vault.** The service account can read only the dedicated `claude-agent` vault
  (1Password forbids granting an SA access to Personal/Private, *and* an SA's vault access is
  immutable after creation — so agent secrets are *brought into* this vault rather than the SA
  being granted others). That vault is the entire blast radius.
- **Token lives in the macOS login keychain** (`security … -s op-claude-agent`), never on disk in
  plaintext, never in git. `boom source` runs `op-agent provision`, which creates the vault +
  service account and stores the token on first run.
- **The token never enters the model's context.** It is read from keychain *inline* inside the
  `op-agent` CLI, confined to that one `op` process — so neither the SA token nor the resolved
  secret reaches a Bash subprocess, the transcript, or OTEL tool spans. No wrapper, no exported
  env var. `op-agent` is one verb-dispatched script: `secret` / `header` / `git-credential` /
  `provision` / `status`.
- **Zero measured calls on an MCP server means "broken or unused", and the two are
  indistinguishable from usage data alone.** Check `claude mcp list` before concluding either;
  `boom verify` fails when any server is down.
- **MCP secrets follow one canonical pattern.** For servers we install:
  `op run --env-file=.env -- <server>` (`boom mcp add`) with `op://` references in a committable
  `.env`, resolved in-process and off disk. Surfaces we don't control use the tool's own native
  hook fed by `op` — plugin-bundled stdio servers via a `*_COMMAND` resolver var; the GitHub MCP
  (an `http` server at `api.githubcopilot.com/mcp/`, in the user-scoped `~/.claude.json`) via
  Claude Code's `headersHelper` → `op-agent header op://…`. Claude Desktop supports neither, so
  it runs a *local* stdio `github-mcp-server` via `~/.local/bin/gh-mcp-stdio`, which resolves the
  same vault item in-process — never an `env` block with a literal PAT. A resolved secret never
  enters git, and never write a `${VAR}` into a git-tracked `.mcp.json` (`claude mcp add` can
  expand it back into the tracked file).
- **Agent git auth resolves the PAT through `op`, like every other secret.** A **classic**
  `repo`+`workflow` PAT (SSO-authorized for the orgs it pushes to), stored in the `claude-agent`
  vault. Classic, not fine-grained, by necessity: fine-grained PATs need org-owner enablement and
  approval you don't have for those orgs, whereas a classic token is bounded by your own access
  and is self-SSO-authorizable at member level. Least privilege therefore rests on the SA-scoped
  vault + token expiry, not on per-repo scoping. Git's `credential.helper` points at
  `op-agent git-credential`, so the PAT lives only in 1Password — no keychain cache, no second
  mechanism. Because the resolve path is `securityd` + network rather than a keychain *file*
  read, it survives a sandbox `credentials.files` deny. Rotating is just updating the vault item.
- **Your own dev work** still uses desktop biometric + `op run`/`op://`/Environments — the
  service account is the agent's path, not yours.
