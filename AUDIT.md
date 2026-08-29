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

On a second pass the teams delivered the rest. Two earlier gaps are now **closed**:

- **Orphans: there are none.** The reference graph is closed. Exactly four tracked files
  score zero direct references — `dot-claude/agents/drift-triage.md`,
  `dot-claude/hooks/tests/verifygate.sh`, `zsh/20-vi.zsh`, `zsh/70-aliases.zsh` — and all
  four are reached by glob or discovery (`boomfile.toml:307,320,597`, and `all.sh:28`, which
  iterates the directory on purpose). Nothing to cut.
- **Settings are clean.** No deprecated, misspelled, or wrong-scope keys. The empty-string
  `NINETY_*` vars and `skipWorkflowUsageWarning` were each checked and are load-bearing.

One gap remains: the **boom source read is shallow** — I sized it and confirmed its test
surface, but did not audit its internals. The boom verdict below is hedged accordingly.

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
| Two largest skills, loaded in full on trigger | ~5,600 tokens each |
| `DECISIONS.md` headings not in the generated TOC | **80 of 114 (70%)** |
| The mis-stated per-session fact, copies / wrong | **8 / 4** |
| `mise.lock` | 83,268 B, refreshed by nothing |
| CI runners | `ubuntu-latest` only — target OS untested |
| Tracked files referenced by nothing | **0** — graph is closed |
| `CLAUDE.md` files vs Anthropic's 200-line guidance | 37 lines each; ceiling ~5x stricter |
| boom verbs used by its only consumer | **6 of ~21** |
| `boom.lock` vs `mise.lock` | 939 B of versions vs 83,268 B with checksums |

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
- **CI never runs on the target OS.** Both workflows are `ubuntu-latest`; the README's whole
  setup path is executed by nothing. See Finding 17.
- **83 KB of pins nothing refreshes.** `mise.lock`, invisible to Dependabot. See Finding 18.
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

**8 · ~~ADD — a `PreCompact` hook~~ — WITHDRAWN.** I proposed this on the reasoning that
119 commits/30 days implies long sessions. The Claude Code specialist checked the full
event list and disagrees: of the three unused events (`Notification`, `PreCompact`,
`UserPromptSubmit`), `PreCompact` has no actionable event to hook, and even `Notification` —
the highest-value unused one — is audit-only and low velocity value. Two further events
(`SessionEnd`, `PostToolUse`) are unused because their machinery was *deliberately deleted*
on 2026-08-28. **Hook coverage is complete; there is nothing worth adding here.**

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
forcing anything, it is a ratchet at rest. And `decisions-toc.sh` is *not* a maintenance tax
(generated, `--check`-gated, zero manual edits ever) but it indexes `##` only: **80 of 114
headings (70%) are unindexed**, and the two largest sections — ~28% of the file — are one
TOC line each.

**15 · CUT — duplication is the rot generator, and it is countable.** _(team.)_ The fact that
Finding 10 shows is *wrong* appears in **8 places, and 4 of them are already wrong**
(`CLAUDE.md:35-37`, `README.md:92`, `README.md:101-104`, `DECISIONS.md:6-9`,
`SETTINGS.md:3-4`, `REFERENCE.md:3`, plus two script copies). That is the mechanism: a fact
stated 8 times rots in 4. Also duplicated — the principles (twice: `CLAUDE.md:13-19` and a
`README.md:12-17` paraphrase that *then links to the original*), the "Lean A" brew/mise split
(×4), the routing table (×4), and the `code reap` rationale (×5, of which only
`claude-canary.sh` has a runtime check behind the literal).
→ *One-line action:* keep the copies that are error text in a script — those are earned,
because they fire — and reduce the doc copies to links.

**16 · MOVE — two skills are docs wearing skill frontmatter.** _(team.)_ `butter-stack`
(22,675 B / 229 lines) and `agent-friendly-repo` (21,897 B / 283 lines) are each a single
file with no `references/`, so **~5,600 tokens loads in full on any trigger** — and most of
it is inventory or unused branches. `hook-authoring` (5,256 B) and `worktree-triage`
(4,095 B) are correctly sized; none of the four is dead.
→ *One-line action:* split the stack table and the ruleset/optional branches into linked
files, leaving the procedure in `SKILL.md`.

**17 · ADD — CI never executes the path the README documents.** _(team, verified.)_ Both
workflows are `runs-on: ubuntu-latest`; nothing tests macOS. The retired-cask failure
(`zulu17` → `zulu@17`) and the `"1d"` schedule value that failed validation and silently
never ran were **both invisible to an Ubuntu runner**. This is the same class as Finding 11:
a failure that surfaces only on a real machine, at the moment of highest cost — a fresh one.
→ *One-line action:* one `macos-26` job running a dry-run reconcile against a fresh checkout.

**18 · ADD — 83 KB of pins that nothing refreshes.** _(team, verified.)_ `mise.lock` is
83,268 B, and Dependabot structurally cannot see it — it is actions-only here. Most
`mise.toml` entries are `"latest"`, so the lockfile is the only thing pinning ~28 binaries.
→ *One-line action:* add Renovate's `mise` manager to the existing weekly auto-merge lane.
Skip the Brewfile — it has no datasource.

**19 · FIX — refines Finding 7: the wrong installer is unpinned.** _(team.)_ Of the two
`curl | sh` bootstraps, the Claude one is **Anthropic's, self-updating, and already
mitigated** by an `unless` guard — leave it. The one that matters is **boom's own
`install.sh`**, in the README one-liner: he owns both ends and there is no integrity check at
all. `timeout` covers hanging, not tampering.
→ *One-line action:* publish a checksum for `boom/install.sh` and verify it in the one-liner.

**21 · ADD — the context ceiling over-constrains in three ways, and the escape hatch exists.**
_(team, verified against the primary source.)_ `scripts/context-budget.sh` caps
`dot-claude/CLAUDE.md` at 2,500 B and `CLAUDE.md` at 3,000 B, on the stated premise that
"every byte is billed to every request of every session." Three problems, each confirmed
against https://code.claude.com/docs/en/memory:

- **Its scope is wrong.** It caps 2 files; 7 surfaces are billed (Finding 10).
- **It bills what Claude Code doesn't.** *"Block-level HTML comments (`<!-- maintainer
  notes -->`) in CLAUDE.md files are stripped before the content is injected into Claude's
  context."* The script counts raw bytes, so maintainer notes that cost **zero tokens** still
  consume the ceiling and get deleted to fit.
- **The only way under the ceiling is deletion — and it needn't be.** `~/.claude/rules/`
  supports `paths:` frontmatter, and *"path-scoped rules trigger when Claude reads files
  matching the pattern, not on every tool use."* Guidance scoped to
  `dot-claude/hooks/**/*.sh`, `boomfile.toml`, or `Brewfile` would cost **zero context until
  the matching file is read**. (Rules *without* `paths:` load at launch — only the scoped
  ones are free.) User-level `~/.claude/rules/` applies across every project.

For calibration: Anthropic's published guidance is *"target under 200 lines per CLAUDE.md
file."* Both of these files are **37 lines**. The self-imposed ceiling is roughly 5× stricter
than the published one — a legitimate choice, but worth naming, because guidance is currently
being *destroyed* to satisfy a constraint that a free mechanism would have absorbed.
→ *One-line action:* move file-scoped guidance into `~/.claude/rules/` with `paths:`, move
maintainer notes into HTML comments, and have the ceiling measure post-strip bytes.
Related: the **`InstructionsLoaded` hook** exists and *"log[s] exactly which instruction files
are loaded, when they load, and why"* — the right debugging tool for exactly this, and the
answer to "prove what actually landed" across four instruction surfaces. `/doctor` (v2.1.206+)
also proposes CLAUDE.md trims on the same doctrine this repo already follows.

**22 · KEEP, but note — boom's verb surface has one consumer using a quarter of it.**
_(team.)_ Of ~21 verbs, this boomfile uses **six** (`source`, `verify`, `code`, `skill`,
`upgrade`, `lock`). Unused: `adopt`, `init`, `fleet`, `module`, `mcp`, `completions`, `man`,
`doctor`, `status`, `plan`, `where`, `edit`, `rollback`, `checkpoint`, `uninstall`, plus an
undocumented `askpass`. That is boom's business, not this repo's — but it answers the question
this audit left open: **the surface did grow past its one consumer.**
More consequential: boom's **launchd install/load is untested** — the plist *rendering* is
tested, the *effects* never are. That is the same seam as Finding 11, reached independently:
three launchd jobs silently failed on this machine, and the code that installs them has no
effect-level test.
**Correction to a team claim:** it was reported that `boom lock` writes a lockfile "nothing on
this machine ever checks." That is false — `boom verify` runs a PINNING section, and
`boom.lock` pins 7 brew + 30 mise packages. The real observation is narrower: `boom.lock`'s
`[mise]` half records bare versions for tools `mise.lock` already pins **with checksums and
provenance** (83,268 B vs 939 B), and `lockfile = true` means mise enforces its own. The
`[brew]` half is unique and load-bearing — nothing else pins brew versions.

**20 · KEEP — `AGENTS.md` buys nothing here.** _(team.)_ It is a genuine de-facto standard
(60,000+ repos, stewarded by the Agentic AI Foundation under the Linux Foundation), but
**Claude Code does not read it** — the documented bridges are an `@AGENTS.md` import or a
symlink, and an import costs full context at launch. With Claude Code as the only agent, a
rename is context-neutral at best and adds indirection `context-budget.sh` would have to
chase. Revisit only if a second agent lands.

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

1. **Finding 21** — path-scoped rules. This is the one that changes the shape of the repo
   rather than fixing a defect: it converts the context budget from a mechanism that
   *destroys* guidance into one that *relocates* it at zero cost. Everything the byte ceiling
   has cut since it was introduced is a candidate to come back.
2. **Finding 11** — the scheduled-job exit-code check. Closes a *class* where three fixes
   closed three instances, and the open one (`code fetch`) fails as apparent model error.
   Finding 22 shows the same seam from boom's side: the launchd install path has no
   effect-level test.
3. **Finding 17** — a macOS CI job. Same class as 11, and it is the only thing that would
   ever execute the path the README documents.
4. **Finding 1** — move `boom verify` into `[boom].schedule`. Falls out of 11 naturally.
5. **Finding 10** — correct `README.md:92` and teach `context-budget.sh` to notice new
   `~/.claude/` links. Do this *with* 21; they are the same repair.
6. **Findings 12, 9, 19, 18** — all one-line; 9 is on your hottest command path and 19 is
   the only genuinely unpinned installer.
7. **Finding 4** (reclaims 18 s per guard commit), then **15**, **2**, **14**, **16**
   together — they are one problem.
8. Findings 5, 3, 13 when convenient. Finding 8 is withdrawn; Findings 20 and 22 are
   decisions to *not* act.

Findings 2, 3, 14, 15 and 16 matter most long-term and are the easiest to defer, because the
cost they impose is authorship time, which never shows up as a failing check. That is
precisely why they need a mechanical ceiling rather than a resolution.

## Postscript — the audit's own evidence

This file was blocked by the repo's own gate **twice while being written** —
`identity-drift.sh` caught it on the first commit attempt, and `dead-verbs` caught it on the
second, for naming the retired verb inside the sentence describing the check that catches
the retired verb. Neither was a false positive. Add the `~`-in-plist gate (which exists
because of the 28-day outage) and `skill-description-cap.sh` (which is the only reason the
billing error in Finding 10 is provable), and four of this audit's findings exist because a
mechanical check already fired.

Two claims in this audit did not survive checking — one relayed from a subagent (the
`rm`-in-`remove` double-fire, struck) and **one of my own** (Finding 8, withdrawn after the
specialist checked the actual event list against my inference from commit volume). Both were
plausible, specific, and cited. Neither was true.

That is worth recording next to the rest. At 119 commits/30 days most of the input to this
repo is now agent-authored, and the failure mode is not a bad commit — it is a well-argued,
precisely-cited claim nobody checked. Note which of this audit's findings were *mechanically*
produced (the timings, the churn ratios, the 14 symlinks, the 80-of-114 TOC gap) and which
came from reasoning about the repo. Only the first kind was ever wrong by accident. Every
mechanical gate here is, in effect, defense against the second kind. The prose is not —
which is the same finding as 3, 14 and 15, arriving from a different direction.
