# Claude Config — Decisions & Incidents

Why the Claude Code setup is the way it is: root causes, postmortems, settings that were
removed and why, and the measurements behind the calls.

**Not auto-loaded.** Only `CLAUDE.md` and `settings.json` are symlinked into `~/.claude/`, so
this costs nothing per session — read it on demand. It exists so `CLAUDE.md` can stay a short
list of things to *obey*: an instruction file that also carries its own changelog gets skimmed,
and it is paid for on every request of every session.

When you change the config, put the *rule* in `CLAUDE.md` and the *reasoning* here.

---

## Permissions & security

### The GitHub MCP was deleted for looking unused, then restored (2026-07-25)

Usage data showed "0 calls in 3,410 transcripts", which read as *unused* and got the server
removed. It was **broken, not unused** — misconfigured, so it never had the chance to be called.
It was reinstalled the same day, taking `op-agent header` back with it.

The lesson generalised into a standing rule in `CLAUDE.md`: zero measured calls on an MCP server
means "broken or unused", and those two are indistinguishable from usage data alone. Check
`claude mcp list` before concluding either. `boom verify` now fails when any server is down, so
the ambiguity surfaces instead of being inferred.

The server is deliberately full read/write, not the `/readonly` endpoint, and it is user-scoped —
so a write-capable PAT is reachable from every session in every repo. That widens the
confused-deputy surface `defaultMode: auto` already accepts, which is why the re-evaluate note
stays on the permissions bullet.

### A diagnostic printed a live PAT into a transcript (2026-07-25)

A command ran `op-agent header` without redirecting stdout, so a live PAT landed in a session
transcript. The token was rotated.

This is the origin of the "never echo a secret — always `>/dev/null` and test the exit code" rule.
The `op-agent` design keeps secrets out of the model's context *by default*; that guarantee only
holds if callers don't defeat it by printing the result.

### What `permissions.deny` actually buys

It blocks the Bash path to secret resolution and raw credential files, and it survives `auto` and
bypass because deny is evaluated before everything else. But it is **defense-in-depth against an
unsophisticated injected one-liner, not a floor** — `git push` authenticates with the same PAT, so
an attacker who can run git can still use the credential. Least privilege genuinely rests on the
SA-scoped vault plus token expiry, not on the deny list. Stated plainly here so the deny list is
never mistaken for a security boundary.

---

## Settings removed deliberately

### `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` and `ENABLE_PROMPT_CACHING_1H=1` (removed 2026-07-25)

Both were inert. Measured over **30,983 requests**: p50 context 143,853 tokens, p90 441,802, and
only **1.4% above 800K**. An 80% threshold on a 1M window is essentially never reached. The
statusline also reads the env var itself (`statusline.sh:492-497`), so the "the marker is
hardcoded at 80%" rationale for keeping it was already false. The 1-hour prompt-cache TTL is
requested by default on a subscription.

Two enumerated divergences that did nothing. Principle 2 says they go.

### `SessionStart` + `SubagentStart` git-fetch hooks (removed 2026-07-25)

They existed to freshen `origin/HEAD` before a worktree branch was cut. `[boom] schedule` already
runs `code fetch` every 15 minutes across every `~/Code` repo — `FETCH_HEAD` was verified stamped
within 2 minutes of wall clock — so every repo is permanently warm on an interval that does not
depend on session cwd. That also covers the `boom code claude` flat-symlink case the hooks never
could, since there the cwd is not a repo at all and the hook silently no-opped.

The freed `SessionStart` slot is now the keep-awake hook.

---

## Hooks

### Worktree-checkout guard: rewritten to test the condition, not the name (2026-07-25)

The original matched the *default branch name* inside a *linked worktree*. But git fails on a
**condition** — any branch already checked out in another worktree, not just `main`. Of 43 real
collisions measured after it shipped, **9 were `main` and 34 were other branches**, so the
dominant population walked straight past it.

It now tokenizes the command and asks git directly. This is **strictly better on both axes** than
the old regex: it cannot false-positive, it needs no regex escaping for branches like
`release/1.0`, and it is shorter. It supersedes the in-source note that said "precision beats
coverage here — we accept false negatives to kill false positives"; that tradeoff existed only
because the check was name-based.

Now caught that previously escaped: `git checkout -q main`, `git checkout main 2>&1 | tail -5`,
quoted `"main"`, `git -C <dir> checkout main`, and every non-default branch.

### Rebase guard: three defects, all from scanning the whole command string (2026-07-25)

All three came from matching against the entire command rather than the matched `git push`
segment:

1. A `--dry-run` *anywhere* — including inside an unrelated commit message — disabled the
   direct-push-to-default rule entirely, so `git commit -m "test --dry-run flag" && git push origin main`
   was **allowed**. The one rule called non-negotiable, defeated by a substring.
2. The mirror image: a commit message merely containing the word "main" **denied** an ordinary
   feature-branch push.
3. `gh pr create --base <parent>` was judged against `origin/HEAD`, telling the agent to rebase a
   stacked PR onto the default branch — which would flatten the stack `rebase-prs` deliberately
   builds. `--base` is now parsed and used as the target.

Additionally, a leading `cd <path>` in a compound command is now honored via `git -C`, so
`cd other-repo && git push` evaluates *that* repo rather than the session cwd.

### Why the guards have a regression suite

`dot-claude/hooks/tests/` — 33 cases against throwaway git fixtures in `$TMPDIR`; hermetic, no
network, under 2s. Every case came from a real transcript or a reproduction, and **10 of them fail
against the pre-fix guards.**

200+ lines of load-bearing, security-relevant shell had no tests, which is exactly how the
`--dry-run` hole shipped and survived. Add a case before changing a guard.

### PR review hook: the `if` filter was in the wrong place and had never worked (2026-07-25)

It sat on the *matcher group* (`{"matcher": "Bash", "if": …}`), but `if` is a field on an
**individual hook handler**, so Claude Code dropped it as an unknown key on its next rewrite — and
that drop is what made the bug visible. Net effect for the hook's whole life: it was invoked on
*every* Bash call, and only the script's own `case "$cmd"` gate kept it from acting. The config had
also been duplicated into two identical `matcher: "Bash"` groups, so it forked twice per call; the
per-SHA lock (`mkdir "$lock"`) meant that wasted work rather than double-posting a review.

Now one group, two handlers, each carrying its own `if` — `if` holds exactly one rule with no `||`,
so two commands means two handlers.

Verified by experiment, not by reading: an `if` rule matches when **any** subcommand of a compound
command matches, so `git commit -m … && git push` still fires and a non-git command fires nothing.
That mattered — had `if` required the *whole* command to match, adding it would have silently
stopped reviews on exactly the compound push the `ship` flow uses.

### Why the PR review runs locally rather than in CI

Three things make it the right shape:

- The adversarial review already existed but covered ~2% of PRs, because it waited to be invoked
  by hand.
- Running it locally is subscription-covered, whereas an agent in GitHub Actions bills metered
  money — roughly **1,600 paid runs per half-year at 8.8 PRs/day**.
- **A commit status posted with your own token is a valid `required_status_checks` context**, so a
  ruleset can eventually require it — real blocking enforcement with zero LLM tokens in CI.

---

## Plugins & marketplaces

- **`expo` (added 2026-07-25)** ships an MCP server (EAS builds/submits/workflows, store reviews)
  plus ~20 skills, making it the largest single addition to the plugin set. Drop it if the Expo
  work it serves stops.
- **`binfinite` marketplace (added 2026-07-26)** is unlike gnar and `claude-plugins-official`: it
  is **our own private repo**, and the marketplace manifest lives in the *same* repo as the product
  code (`.claude-plugin/marketplace.json` → `./plugins/binfinite-context`). Two consequences worth
  stating: resolving it needs authenticated GitHub access to a private repo, so it silently fails
  to load where the credential helper can't reach `BinfiniteLLC`; and `autoUpdate: true` means the
  plugin tracks that repo's default branch, so a merge to `binfinite-app` main changes agent
  context everywhere on the next update. That is deliberate — the point is that deployment facts
  stay current — but it does make that repo's main a live input to every session, not just sessions
  inside it.

---

## UI

### Statusline provenance moved to the Gnar repo (2026-07-27)

`~/.local/bin/claude-*statusline` now comes from
[`thegnarco/claude-statusline`](https://github.com/thegnarco/claude-statusline), migrated from
`alxjrvs/claude-statusline`, which that repo was seeded from. The scripts were **byte-identical at
the switch**, so this changed provenance only; future updates now come from the shared Gnar repo.

### `tui` and `theme` arrived via the client, not by hand

Both were set through the UI and then written out by Claude Code's own rewrite of `settings.json`.
That is exactly why they are enumerated in `CLAUDE.md` now: the contract is "everything in the file
appears in this list", and for a self-rewriting file that means **reconciling after the client
edits, not preventing it**.

### Voice was adopted rather than left dirty

`voiceEnabled` + `voice: { enabled: true, mode: "hold" }` had been sitting as an uncommitted local
edit in boom's config-repo clone — live on the machine, in neither git nor the enumeration. Adopting
it deliberately, and adding a `boom verify` step that fails while that clone is dirty, is what turned
"no local override layer" from an assertion into something enforced.

---

## Worktrees & merges

### Root cause of issue [#53](https://github.com/alxjrvs/dotFiles/issues/53) — `gh pr merge --delete-branch`

`-d`/`--delete-branch` deletes the *local* branch after merging, which requires `gh` to switch off
it first — so it checks out the base branch (`main`) in the worktree session's own repo. Since the
primary checkout normally has `main` checked out at the same time, git refuses with
`fatal: 'main' is already used by worktree at '<primary checkout path>'`.

The GitHub-side merge has already succeeded by that point (the PR shows `MERGED`), so only the
trailing local-cleanup step fails — leaving the remote branch undeleted. Recovery is just
`gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>`.

Reproduced under a plain background-job `EnterWorktree` session; none of the earlier-suspected
Agent `isolation: "worktree"` / `claude --worktree` / cmux mechanisms were needed.

### The native fix (applied 2026-07-08)

`delete_branch_on_merge` enabled repo-wide on `alxjrvs/dotFiles` and `alxjrvs/botu`
(`gh api -X PATCH repos/<owner>/<repo> -f delete_branch_on_merge=true`). With it on, GitHub deletes
the remote branch server-side once the merge lands — no local git checkout, no `-d` flag, no timing
hazard with `--auto` on a not-yet-green PR. Local cleanup of the disposable worktree branch already
happens via `ExitWorktree`/`git worktree remove`, so there is nothing left for `gh` to do locally.

### Why auto-merge is a permission rule and not prose

Confirmed 2026-07-08 that unattended background jobs should auto-merge too, not just interactive
sessions. Writing that as a blanket standing pre-authorization in `CLAUDE.md` was **blocked twice by
the Claude Code auto-mode "instruction poisoning" classifier** — chat confirmation does not clear
that rule, by design.

The classifier's own prescribed mechanism is an explicit Bash permission rule in the *committed*
`settings.json` (auto mode reads permission rules from checked-in settings, not a machine-local
override — see 2.1.207). Hence `permissions.allow: Bash(gh pr merge:*)`. A literal local
`git merge`/`git push` onto `main` remains off-limits regardless.

### Why `boom code reap` exists

Claude Code's worktree-remove guard keeps any worktree whose HEAD commits exist on no remote, but it
tests **SHA identity** — and a squash-merge rewrites history, so the content lands on the default
branch under a new SHA while the branch's own commits genuinely exist nowhere by SHA. The guard
can't tell squash-merged-and-landed from truly-unpushed, so it keeps both and agent sessions become
uncloseable. This recurs after *every* squash-merge; it is a Claude Code limitation, not config.

`commit-commands:clean_gone` does not catch it either — the `worktree-*`/`agent-*` branches have no
upstream, so there is no `[gone]` signal.

### Stacked PRs adopted via `github/gh-stack` (2026-07-31)

GitHub put stacked PRs into public preview on 2026-07-30 with a first-party CLI extension. That is
what changed the answer: stacking was always the right shape for agent output — many small
reviewable layers instead of one 40-file PR — but every previous implementation was a third-party
tool (Graphite, `git-branchless`, four community `gh-stack` forks) carrying its own metadata model,
its own hosted service, or both. **Native over special** ruled all of them out. A GitHub-shipped
extension that stores its state in `.git/gh-stack` and drives the stock PR API is the stock
behavior, so the principle now argues *for* adoption rather than against it.

It is installed through the boomfile rather than by hand because a workflow preference nobody's
machine can execute is just prose. `gh` has no declarative manifest and boom has no `gh` package
manager, so the `gh extensions` section is an install-if-absent `run` step — the same shape as the
Claude CLI install, and for the same reason. It **must** sit after the `packages` section: `gh`
itself comes from mise, sections run in file order, and a fresh machine has no `gh` on PATH until
packages has run. The grep matches `github/gh-stack` including the owner, because `gh ext search
stack` returns four same-named community extensions and only one of them is GitHub's.

It is install-only, and **that is a weaker guarantee than the Claude CLI step it mirrors.** The
Claude CLI genuinely self-updates after install; `gh` extensions do not — gh "will check for new
versions once every 24 hours and display an upgrade notice", which is a *notice*, not an install.
So `gh stack` stays on whatever version first landed until someone runs `gh extension upgrade`.
For a v0.1.0 public-preview tool that is a real trap, and the daily notice is the only thing that
surfaces it. An upgrade step was not added because "install this extension" was the ask and a
network call on every `boom source` is not free; revisit if the version actually drifts far enough
to bite. The failure mode is documented rather than fixed, deliberately — but it is documented,
because the first draft of this section wrongly claimed gh auto-updates extensions.

Two things fell out of reading the extension's actual contract rather than assuming:

- **The existing checklist was already a precondition, not merely compatible.** `gh stack modify`
  refuses a history with merge commits or diverged branches, and `gh stack merge` states outright
  that bypassing merge requirements is *not supported* for stack merges. So `required_linear_history`
  and `bypass_actors: []` — already in `agent-friendly-repo` on other grounds — are exactly what
  stacks need. A repo whose agent path leans on a bypass actor cannot use stacks at all.
- **The rebase-guard does not see `gh stack`.** It tokenizes for `git push` / `gh pr create`
  specifically, so `gh stack submit`/`push`/`sync` sail past it. That is a gap in coverage, not a
  blessing, and it is deliberately *not* fixed by widening the guard: `gh stack sync` already does
  fetch + cascading rebase + push, so the correct behavior is the rule the guard would have
  enforced. Widening the guard to deny `gh stack submit` would mean re-deriving stack-aware
  behind-ness for N branches — a lot of security-relevant shell to duplicate what the tool does
  natively. The rule lives in `CLAUDE.md` prose instead, with the honest caveat that prose is
  advisory. Revisit if a stale stack actually gets published.

Deliberately **not** adopted in the same change: `gh skill install github/gh-stack --agent
claude-code`, which drops a GitHub-authored skill into `~/.claude/skills/` — the same directory
boom glob-links into. It is a new agent-context surface from outside the repo, and the doctrine is
that those get enumerated before adoption, not installed as a side effect. Our own
`agent-friendly-repo` skill now carries the repo-side guidance; if the CLI ergonomics turn out to
need more, adopt it explicitly then.

---

## Branch protection

### Classic protection — legacy fallback only

For a repo that cannot use rulesets, the equivalent classic form is `enforce_admins: true` (CI green
for everyone), with a one-off emergency bypass via
`gh api -X DELETE .../branches/main/protection/enforce_admins` to disable and `-X POST` to re-enable:

```
gh api -X PUT repos/<owner>/<repo>/branches/main/protection --input - <<'EOF'
{
  "required_status_checks": { "strict": true, "contexts": ["<aggregate-check>"] },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

Prefer a ruleset. GitHub takes the *union* of classic protection and rulesets, so running both is a
footgun: you edit one and the other silently still applies.

### Dependabot auto-merge: a workflow, because there is no switch (2026-08-03)

The agent-friendly checklist already unblocks it — **no required human review** means a Dependabot
PR needs only a green aggregate check — but nothing fires `--auto` on the bot's behalf:
`dependabot.yml` has no automerge key (Renovate does; Dependabot doesn't), and the per-PR
auto-merge button needs a human click. So the mechanism is a one-job workflow calling
`gh pr merge --auto --squash`, gated on `github.actor == 'dependabot[bot]'`. It merges nothing
itself; branch protection stays the gate.

Four constraints, each of which quietly breaks it if ignored:

- **`on: pull_request`, never `pull_request_target`.** Dependabot-triggered runs get a read-only
  `GITHUB_TOKEN` by default but have respected the `permissions:` key since Oct 2021, so
  `pull_request` suffices. `pull_request_target` would hand a write token to a base-branch-context
  run for no benefit — this job never checks out PR code.
- **Actions secrets are unavailable to Dependabot runs** (only *Dependabot* secrets are). A CI job
  that needs a secret fails on every Dependabot PR, and auto-merge silently never fires. `lint.yml`
  here is hermetic, which is why this works on this repo.
- **`GITHUB_TOKEN` cannot add a PR to a merge queue** — so this and the optional merge-queue step
  are mutually exclusive unless the token is swapped for a PAT/App token.
- **Allowlist, not denylist.** The gate is `update-type == minor || == patch`, not `!= major`: if
  `update-type` ever returns empty, a denylist auto-merges the thing it was meant to catch.

Scoped to `github-actions` only — this repo has no npm/bun manifest, so pinned action tags are the
whole dependency surface. Majors are excluded from the group and stay manual: an action major
changes what code runs against a write-scoped token, which is the same supply-chain surface the
*Standing threats* section keeps small.

---

## Secrets

### The Spacebase server was silently down because a vault item had spaces (fixed 2026-07-25)

The `_COMMAND` value is run through `/bin/sh -c`, so an `op://` ref containing spaces word-splits
into separate arguments and the resolve fails. The item used to be titled `Spacebase API Key`, and
that is exactly why the server sat at **✘ Failed to connect** with
`[spacebase-mcp] SPACEBASE_API_KEY_COMMAND failed` and zero calls, silently, for an unknown period —
while `gninety`, whose ref had no spaces, was the one server that kept working.

Fixed at the root: **every `claude-agent` item is now space-free `kebab-case`** (`spacebase-api-key`),
so quoting is defence-in-depth rather than the only thing holding it up. Both halves matter — the
rename protects refs someone forgets to quote, the quoting protects against someone re-introducing a
space. A `boom verify` step now fails when any MCP server is down, so this class of breakage surfaces
instead of reading as disuse.

### Details compressed out of `CLAUDE.md`

Concrete specifics that were carrying the argument in the old prose, kept here so the contract can
stay short without losing them:

- **Plugin installs write themselves in.** `/plugin install` writes `enabledPlugins` directly into
  `~/.claude/settings.json`, which symlinks into boom's clone — which is why installing one dirties
  the tree.
- **The reflexive checkout the worktree guard exists for** is the state-check pattern
  `git checkout main && git status && git log`, which an agent runs to inspect the tree and which
  fails inside a linked worktree.
- **Keep-awake, measured**: on battery this machine has `pmset` `sleep 1` and `displaysleep 2`; on
  AC `sleep 0`, already correct. So an unplugged session ran on a 60-second fuse, and a large share
  of typed `continue`s were resuming a sleep-killed session rather than supervising one.
- **Vault item naming**: titles are space-free — e.g. `claude-git-pat` — because every `op://` ref
  is re-parsed by `sh -c`.
- **Merge queues** carry a `merge_group:`-trigger sequencing hazard; the `agent-friendly-repo` skill
  handles it when it sets one up.
- **`NINETY_API_TOKEN` unset is worse than empty**: Claude Code passes an unset `${VAR}` to the
  server as the literal string `"${NINETY_API_TOKEN}"`, which `auth.ts` treats as a real token and
  sends as `Bearer ${NINETY_API_TOKEN}` — producing a misleading 401 rather than an obvious
  misconfiguration.

### Why the Ninety PAT lives in the `claude-agent` vault

1Password service-account vault access is **immutable after creation** — you cannot grant an SA a
second vault. So the secret comes to the SA, not the reverse: agent secrets are copied into
`claude-agent` rather than the SA being granted access to wherever they already lived.
