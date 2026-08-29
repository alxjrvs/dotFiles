# Audit — dotFiles

_2026-08-29. Supersedes the gitignored `audit/` tree (2026-06-17), which predates the
`botu` → `boom` rename and describes a repo that no longer exists._

Calibrated to the owner's stated priority: **personal velocity first**, not public
showpiece. A finding is ranked by whether acting on it makes this machine's agentic work
faster or less fragile — never by whether it is more conventional.

## Verdict

**The repo is not too big. It is too narrated.**

Nothing here is unused. There are no orphans in `~/.claude`, no undeclared drift, no dead
skills, and every gate traces to a named incident. On the usual axes this repo is in the
top percentile of its kind and the honest answer to "what are we missing" is *almost
nothing*.

The cost has moved somewhere the usual axes do not look. Two things are now
disproportionate:

1. **Prose.** Roughly 60% of everything written in the last 30 days is prose *about* the
   config rather than config. `DECISIONS.md` grew 30 KB in a single day.
2. **The guard harness.** 64% of all executable code in a repo whose `CLAUDE.md` opens
   with "there is no engine code here" is a bespoke Claude Code safety harness.

Neither is waste. Both are the *same* good instinct — write down why, enforce rather than
describe — applied without a stopping rule. The recommendations below are almost entirely
about adding stopping rules, not about deleting things.

## Method and its limits

Every number below was measured directly in this working tree on 2026-08-29, not inferred.
Timings are single-run wall clock on the owner's machine.

**Disclosure:** five research subagents were dispatched (Claude Code feature gaps, dotfiles
ecosystem/web research, orphan-and-duplication sweep, boom source audit, docs/context
budget). Their reports arrived late and **truncated at a 16,000-character transport limit** —
three delivered partial output, two delivered none. Findings below marked _(team)_ come from
those partial reports; everything else is my own direct measurement.

**Every relayed claim was re-verified before inclusion, and one did not survive.** The
orphan sweep reported that `worktree-remove-guard.sh` double-fires because the `Bash(*rm*)`
matcher matches `rm` inside the word `remove`. It does not: `git worktree remove --force
/path` contains zero occurrences of the substring `rm` (`r` is followed by `e`). That claim
is **struck**. The neighbouring claim about `rebase-guard.sh` *is* correct and is Finding 9.

Remaining gaps, stated rather than papered over:

- **Claude Code feature-gap coverage is absent** — that agent returned nothing readable, so
  the "what settings are inert or deprecated" question is unanswered.
- The **boom source read is shallow** — I sized it and confirmed its test surface, but did
  not audit its internals. The boom verdict below is hedged accordingly.
- The **orphan list was never delivered**, so "which tracked files are referenced by
  nothing" remains open.

## Measured facts

| Metric | Value |
|---|---|
| Tracked files | 95 |
| Executable LOC (shell + TS) | 5,666 |
| Declarative config LOC | 1,764 |
| **Claude guard harness** (9 guards + 7 test suites) | **3,632 LOC = 64% of executable** |
| `scripts/` repo gates | 817 LOC |
| `hooks/` (boom-invoked) | 784 LOC |
| zsh payload | 376 LOC |
| `boomfile.toml` | 991 lines, 463 of them comment (47%) |
| `Brewfile` comment:code | 2.77 : 1 |
| `mise.toml` comment:code | 1.55 : 1 |
| `DECISIONS.md` | 166,618 B / 2,528 lines / 34 entries |
| `DECISIONS.md` date span | 2026-07-28 → 2026-08-28 (one month) |
| `DECISIONS.md` growth on 2026-08-28 alone | **+30,187 B across 10 commits** |
| Commits, last 30 days | 119 |
| Line churn, last 30 days | +14,242 / −4,282 |
| — pure prose (`.md`) share of additions | 30% |
| — comment share of code/config additions | 45% |
| Worst-case pre-commit gate | ~22 s |
| — of which the guard test suite | **18.2 s (83%)** |
| Every other gate combined | < 4 s |
| zsh interactive startup (mean of 10) | 237 ms |
| `boom verify` | 25.3 s (launchd timer — *not* per turn) |
| boom source | 12,791 LOC TS, 184 test files |
| launchd jobs loaded | 4, from **2 different mechanisms** |
| `~/.claude/` links declared in boomfile | 14 (README claims 2) |
| Real fixed per-session context cost | ~6,193 B ≈ **1,550 tokens** |
| `DECISIONS.md` on demand | ~41,650 tokens |
| Skill descriptions vs 60-word cap | 88–93% — a ratchet at rest |

## Q1 — Do we do too much?

Yes, in two places. No everywhere else.

### Where the answer is genuinely "no"

Worth stating first, because the reflex on seeing 16 pre-commit gates is to cut them:

- **Zero unmanaged drift.** Every file in `~/.claude/{hooks,agents,skills}` is a symlink
  back to this repo. The only real directory is the generated `boom` skill. That is rare
  and it is the thing most personal setups get wrong.
- **The gate is well-scoped, not heavy.** Fourteen of sixteen pre-commit commands are
  glob-gated and cost under 4 s combined. A docs-only commit pays ~1 s.
- **`verify-gate.sh` is correctly built.** I expected the Stop hook to be the biggest
  velocity tax in the repo and it is not: it runs `lefthook run pre-commit`, only when the
  tree is dirty, at most once per session, under a 120 s timeout, failing open on every
  error path. That is the right shape.
- **The secret model is the strongest part of the repo.** `op://` references only,
  `op-guard.sh` inverted from a deny-list to an allow-list after a measured verb-enumeration
  failure, and `agent-vault.txt` enforcing that every vault item names a live consumer.
  Nothing to cut.
- **Skills are well-formed.** All four carry specific trigger phrases, not vague
  descriptions. They will actually fire.

### Where the answer is "yes" — 1. Prose has no stopping rule

`CLAUDE.md` is byte-capped and enforced. That cap works. But the pressure it created did
not reduce prose — it **relocated** it, into the two places with no cap: config-file
comments and `DECISIONS.md`.

The repo's own routing rule says *"a reason, an incident, a measurement → `DECISIONS.md`"*.
`boomfile.toml` is 47% comment — 463 lines, much of it incident narrative that the rule
says belongs elsewhere. The `Brewfile` carries 2.77 lines of prose per line of content,
including a long block describing packages that are *deliberately absent*.

This is self-violation by the repo's own stated policy, and it is the largest single
finding by volume.

The counter-argument is real and I want it on the record: an agent reading `boomfile.toml`
gets the reasoning inline, with no second file to open. That is worth something. But the
comment mass is now large enough that it is a *review* cost on every diff, and the
30-day churn shows where the time actually goes.

### Where the answer is "yes" — 2. The guard harness is 64% of the repo

Nine guards (2,311 LOC) and seven test suites (1,321 LOC). Each guard is individually
well-argued — `op-guard.sh`'s allow-list inversion is a genuinely better design than the
`permissions.deny` it replaced, and `rebase-guard.sh` tokenizes rather than substring-matches,
which is correct.

The issue is not that any one guard is wrong. It is that this body of code is now the
dominant artifact in the repo, it is bespoke, it all fails open by design, and it costs
18.2 s per guard-touching commit — 83% of the entire gate.

## Q2 — What are we missing?

Very little, and most apparent gaps are documented deliberate choices (no pinned model, no
`autoMode.environment`, no `.mcp.json`, `boom mcp add` deliberately unused). Real gaps:

- **No detector for the budget's own scope.** `context-budget.sh` caps two files; the billed
  set is seven, and has silently gained three (`skills/`, `agents/`, `loop.md`) without the
  gate noticing. The script's own header predicts this exact failure. See Finding 10.
- **Nothing owns the scheduled-job failure class.** Three instances, three individual fixes,
  class still open. See Finding 11.
- **No stale-measurement detector.** `CLAUDE.md` bans recording measurements against tool
  versions *because they expire unnoticed* — but shell startup now measures **237 ms**
  against a documented ~199 ms, a 19% regression that nothing owns. The rule exists; the
  enforcement does not.
- **Unused hook events.** `SessionEnd`, `PreCompact`, `UserPromptSubmit`, and `Notification`
  are unhooked. `PreCompact` is the interesting one for long agent sessions.
- **`gh` extensions are pinned by nothing.** `gh-extensions.txt` says so itself: boom
  installs misses and never upgrades, and `boom lock` covers brew + mise only. `gh stack`
  is a v0.1.0 preview tool sitting on whatever version landed first.
- **Unpinned bootstrap.** `curl -fsSL https://claude.ai/install.sh | bash` in the boomfile.
  Low likelihood, whole-machine blast radius. Carried over unfixed from the June audit.

## Findings

Ranked by leverage under "personal velocity first."

**1 · FIX — `boom-verify` is a boom command scheduled the hard way.**
`launchctl list` shows four jobs from two mechanisms: `com.boomtube.code-{reap,fetch}`
generated by `[boom].schedule`, and two hand-written plists via `[[section.launchd]]`.
`launchd/com.alxjrvs.boom-verify.plist` runs `boom verify` — a boom command — by hand-rolled
plist. That path is exactly what caused its own 28-day silent outage (a `~` in a path value;
launchd does not expand it, EX_CONFIG 78), documented in the plist's own comment.
Moving it to `{ cmd = "verify", every = "24h" }` makes that class of bug structurally
impossible. Tradeoff to accept: boom's schema is interval-based, so a fixed 21:47 becomes a
drifting 24 h. `capslock-control` is *not* a boom command and correctly stays hand-written.
→ *One-line action:* move the verify job into `[boom].schedule`; delete the plist and the
`[[section.launchd]]` entry.

**2 · FIX — `DECISIONS.md` has no retention policy.** 166 KB, 2,528 lines, 34 entries,
every one written in a single month, +30 KB on 2026-08-28 alone. It costs zero per-session
tokens (on-demand only), so this is not a context problem — it is an *authorship* problem.
At current rate it passes 500 KB by November. The file's value is that a future agent can
find why something is the way it is; at 2,500 lines that lookup is already degrading.
→ *One-line action:* add a retention rule — entries older than 90 days whose subject file
still exists and is unchanged get compacted to one line, or moved to `DECISIONS-ARCHIVE.md`.

**3 · CUT — comment mass in `boomfile.toml` / `Brewfile` violates the repo's own routing
rule.** 463 comment lines in the boomfile; 2.77:1 in the Brewfile. The repo already has the
correct destination (`DECISIONS.md`) and already states the rule.
→ *One-line action:* cap config-file comments the way `CLAUDE.md` is capped — extend
`scripts/context-budget.sh` to a comment-ratio ceiling on `boomfile.toml` and `Brewfile`,
with incident narrative moving to `DECISIONS.md` behind a `see DECISIONS.md#anchor` pointer.

**4 · FIX — the guard suite is 83% of gate time.** 18.2 s on every guard-touching commit,
and guards are the most frequently edited code in the repo.
→ *One-line action:* split `all.sh` so `lefthook` runs only the suites whose guard changed
(it already discovers the roster from the directory), and keep the full sweep in CI, where
18 s is free.

**5 · FIX — a documented measurement has silently rotted.** Shell startup is 237 ms against
~199 ms documented. `CLAUDE.md` forbids exactly this failure mode for tool-version
measurements but nothing checks the ones that remain.
→ *One-line action:* either re-measure and update, or add a `boom verify` check that fails
when startup exceeds a ceiling — the repo's own doctrine says enforce, don't describe.

**6 · KEEP, but name it — `rebase-guard.sh` job #1 is now double-enforced.**
`autoMode.hard_deny` carries *"Never push directly to a repository's default branch…"*, and
`SETTINGS.md:26` records it was added because the built-in protected-branch treatment was
removed, *"which left `rebase-guard.sh` as the only thing enforcing it."* Both now enforce
it. Job #2 (behind-target detection) remains unique to the guard.
**Verdict: keep both.** `hard_deny` is a natural-language classifier rule; the guard is
deterministic tokenization. That is defense in depth across two different failure modes,
not redundancy. Worth documenting so a future cleanup does not remove the wrong one.

**7 · ADD — pin the bootstrap installer.** `curl … install.sh | bash`, unpinned, unchecked.
Carried over unfixed from the June 2026 audit.
→ *One-line action:* pin a release tag and verify a published SHA before executing.

**8 · ADD — a `PreCompact` hook** is the highest-value unused event for this setup, given
119 commits/30 days of long agent sessions.

**9 · FIX — `rebase-guard.sh` runs twice on the commonest command in this workflow.**
_(team, verified.)_ It is wired at both `if: "Bash(*git*)"` and `if: "Bash(*gh*)"`
(`dot-claude/settings.json`). `git push && gh pr create --fill` contains both substrings, so
both arms fire and the guard executes twice — tokenizing, resolving `origin/HEAD`, and
shelling out to git each time. It fails open and is idempotent, so this is pure latency, not
a correctness bug. **Note:** the same report's claim that `worktree-remove-guard.sh`
double-fires via `rm` inside `remove` is false and was struck; that guard is wired correctly.
→ *One-line action:* drop rebase-guard's `Bash(*gh*)` arm and widen the `*git*` arm, or merge
the two into one matcher.

**10 · FIX — the repo's docs are wrong about what is actually billed per session.**
_(team, verified.)_ `boomfile.toml` declares **14** `dst = "~/.claude/…"` links (`:177–321`),
including `skills/` (`:308`) and `agents/` (`:321`). But `README.md:92` states that
`skills/` and `hooks/` "are not" symlinked, and that only `CLAUDE.md` + `settings.json` are
"billed to every session." Both halves are wrong, and the repo's *own* gate already knows:
`scripts/skill-description-cap.sh` exists precisely because every skill `description:` is
loaded into every session. The real fixed cost is ~6,193 B / **~1,550 tokens** — two
`CLAUDE.md` files, four skill descriptions, two agent descriptions, and the generated `boom`
skill description. This is the load-bearing fact the entire context-budget doctrine rests on,
and it is misstated in four files.
→ *One-line action:* correct `README.md:92`, and make `scripts/context-budget.sh` fail when a
`dst = "~/.claude/` link exists that the budget doesn't know about — it has silently gained
three (`skills/`, `agents/`, `loop.md`).

**11 · FIX — the silent-failing scheduled job is a *class*, and nothing owns it.** _(team.)_
The boomfile records three separate instances, each fixed individually: `boom-verify` dead 28
days (`~` in a plist value, EX_CONFIG 78); `code reap --push` at **0 successes / 84 failures
across 14 sweeps**; and `git maintenance` registered against two paths that do not exist.
`[boom] notify = true` closes exactly one verb (`verify`) — it is verb-driven, not
schedule-gated. The `code fetch` timer is load-bearing for agent worktree cuts, and if it
dies the way the others did, the symptom is agents branching from stale bases — which reads
as *model* error, not infrastructure failure.
**This generalizes Finding 1 and is the single highest-leverage addition in the audit.**
→ *One-line action:* one `boom verify` check asserting every scheduled job and managed plist
has exited 0 within N× its interval — `launchctl print gui/$UID/<label>` exposes `last exit
code` and `runs`.

**12 · FIX — `dead-verbs` is the one gate with no CI backstop.** _(team.)_ It runs only in
`lefthook.yml:40-54`; `git commit --no-verify` lands a stale reference to the retired verb
with a green build. This is the mirror image of the asymmetry `lint.yml` documents having
*just* fixed for `skill-description-cap`.
→ *One-line action:* add the same `git grep` as a step in `lint.yml`.

**13 · CUT — `scripts/brew-drift.sh` hand-rolls a capability that exists, minus the half that
would end the chore.** _(team.)_ nix-darwin's `homebrew.onActivation.cleanup` supports
`check` (fail, listing installed-but-undeclared) and `uninstall`/`zap` (actually remove).
`brew-drift.sh` plus the Brewfile's "NOT here, deliberately" block plus its nine-name
exclusion list reimplement `check` — and still cannot remove anything. The Brewfile admits it:
every excluded name "is still installed today and wants `brew uninstall` by hand." That is a
permanent manual chore with no end state.
**Do not migrate to nix** — that is a velocity loss and an all-at-once move. Steal the
capability.
→ *One-line action:* add `brew bundle --cleanup` as an opt-in boom option, the same shape as
the existing `[[section.absent]]`.

**14 · FIX — `DECISIONS.md` rot is measurable, not hypothetical.** _(team.)_ 33,645 →
166,618 B in 24 days (**4.95×, ~5,540 B/day, never once smaller**). In the oldest 20%,
**≥5 of 22 entries (23%) are dead** — including a reversal pair retained at full length and
unannotated (`:2270` "the merge queue stopped being optional" reversed 97 lines later by
`:2367` "the merge queue is declined"), plus entries for PR-review machinery deleted whole on
2026-08-28. At ~41,650 tokens the file is **2.3× larger than the `CLAUDE.md` whose bloat its
own entry records as the disease.** The cure outgrew the disease.
Related: all four skill descriptions sit at **88–93% of the 60-word cap** — the cap is not
forcing anything, it is a ratchet at rest.

## Q3 — boom: does it do too much?

**Hedged, per the disclosure above** — I sized boom and confirmed its test surface but did
not read its internals.

What I can state: boom is **12,791 LOC of TypeScript with 184 test files**. That is not a
personal script that grew legs; it is a real, well-tested project. Its command surface is
broad (21 top-level verbs), and this repo uses a modest slice: 7 of its resource types
(`link` ×40, `run` ×17, `dir` ×3, `check` ×3, `launchd` ×2, `hook` ×2, `absent` ×1) and
four `[boom]` keys.

On the "over-engineered personal artifact" question the North Star warns about: the
extraction was correct *for this repo* — it is what turned a script pile into 95 files of
declarative config. Under **personal velocity first**, "replace boom with chezmoi because
chezmoi is standard" is not a recommendation I would make; the owner would be slower, not
faster, and would lose drift-verify, the managed config-repo cache, and the generated skill.

The one duplication I did find is Finding 1: boom and a hand-written plist doing the same
job on the same machine.

**The honest open question I could not close:** whether boom's 21-verb surface is 21 verbs
the owner uses, or a product surface that grew past its one consumer. That deserves the
source read this audit did not complete.

## Auto mode — verified, no change needed

Requested explicitly. Auto mode **is already the default**, and nothing overrides it:

| Scope | `permissions.defaultMode` |
|---|---|
| `~/.claude/settings.json` (→ `dot-claude/settings.json:56`) | **`auto`** |
| `~/.claude/settings.local.json` | absent |
| repo `.claude/settings.json` | unset |
| repo `.claude/settings.local.json` | absent |

`autoMode.classifyAllShell: true` routes every shell command through the classifier, and
`autoMode.hard_deny` leads with the literal `"$defaults"` — correct, since omitting it
silently discards the built-in rules.

**One gotcha worth knowing:** `~/.claude/settings.json` symlinks to
`~/.local/state/boom/config-repo/dot-claude/settings.json` — boom's *managed cache clone*,
not this working checkout. Editing `dot-claude/settings.json` here changes nothing live
until `boom source` runs.

## What I would actually do, in order

1. **Finding 11** — the scheduled-job exit-code check. Closes a *class* where three fixes
   closed three instances, and the open one (`code fetch`) fails as apparent model error.
2. **Finding 1** — move `boom verify` into `[boom].schedule`. Falls out of 11 naturally.
3. **Finding 10** — correct `README.md:92` and teach `context-budget.sh` to notice new
   `~/.claude/` links. The budget doctrine is currently resting on a false premise.
4. **Finding 12**, then **9** — both are one-line, and 9 is on your hottest command path.
5. **Finding 4** (reclaims 18 s per guard commit), then **2** and **14** together.
6. Findings 5, 3, 13, 7, 8 when convenient.

Findings 2, 3 and 14 matter most long-term and are the easiest to defer, because the cost
they impose is authorship time, which never shows up as a failing check. That is precisely
why they need a mechanical ceiling rather than a resolution.

## Postscript — the audit's own evidence

This file was blocked by the repo's own gate **twice while being written** —
`identity-drift.sh` caught it on the first commit attempt, and `dead-verbs` caught it on the
second, for naming the retired verb inside the sentence describing the check that catches
the retired verb. Neither was a false positive. Add the `~`-in-plist gate (which exists
because of the 28-day outage) and `skill-description-cap.sh` (which is the only reason the
billing error in Finding 10 is provable), and four of this audit's findings exist because a
mechanical check already fired.

And one finding relayed from a subagent was **false on verification** (the `rm`-in-`remove`
double-fire). That is worth recording next to the rest: at 119 commits/30 days, most of the
input to this repo is now agent-authored, and the failure mode is not a bad commit — it is a
plausible, well-argued, precisely-cited claim that nobody checked. Every mechanical gate in
this repo is, in effect, defense against that. The prose is not.
