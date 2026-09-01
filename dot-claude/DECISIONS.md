# Claude Config — Decisions & Incidents

Why the Claude Code setup is the way it is: the reasoning behind calls that are still in force,
and the settings that are deliberately absent so nobody re-adds them.

**Not auto-loaded.** Not symlinked into `~/.claude/`, so it costs nothing per session. Read it on
demand. It exists so `CLAUDE.md` can stay a short list of things to *obey*.

When you change the config, put the *rule* in `CLAUDE.md` and the *reasoning* here.

## Retention

This file reached 2,913 lines in five weeks under a rule that said an entry is never deleted. That
rule is gone. It produced three failure modes at once: entries describing mechanisms that had been
deleted, entries restating the file they were about, and an archive file whose two entries both
ended by saying their own subject no longer exists.

Two rules:

1. **Delete an entry when its subject is gone.** If the guard, key, hook or tool an entry explains
   no longer exists, the entry is not history — it is a wrong answer to a question nobody asked.
   `git log -S` is the historical record and costs nothing to keep.
2. **Correct in place, append never.** A wrong line with a correction below it reads as two claims
   and the reader has to work out which one won.

An entry earns its place here only if it is still in force, its rationale is non-obvious, and no
test, gate or file header already asserts it. An incident that ended in a regression case belongs
in `dot-claude/hooks/tests/cases.tsv`, not here — the test is the record.
## How to write a number so it cannot rot

A count is a **measurement**, and a measurement is only ever true at a moment. So:

> **A number may state what was observed once, or it may be enforced by a check. It may never
> describe how the system currently is.** In a dated entry below, write any count you like — the
> date is what makes it honest. Anywhere that describes the present tense, name the authority
> instead of the value: *"the cases in `cases.tsv`"*, not *"138 cases"*; *"every entry in the deny
> array"*, not *"all 11 entries"*; *"most cases here assert the hook did nothing"*, not *"9 of 12"*.

That is not pedantry — it is the failure this file exists to record. `CLAUDE.md` said the guard
suite had "127 hermetic cases" when it had 138, and a section here said "33 cases" when it had
138. Both read as precise and authoritative, and both were wrong. **The more exactly a count is
stated, the more confidently it lies later.**

Three corollaries, each mechanical:

- **Never state a threshold that a check already enforces.** Say *"a byte ceiling, enforced by
  `always-loaded context budget`"* and let that check own the number. Two copies of a constant
  desync silently, and both look authoritative.
- **Never annotate a feature with the version it arrived in.** `boom >= 0.14.0` on a feature this
  boomfile actively uses conveys nothing — the feature working is the proof it exists — and it
  only ages. A version belongs in a dated entry, or beside code that must be re-measured, never as
  a decoration on working config.
- **Never cross-reference by position.** *"Seventeen lines above"*, *"the section below"*, *"two
  bullets up"* — all rot on the next edit. Name the thing.

Counts that survive are the ones with an owner: a `jq` assertion, a `wc -c` gate, a test that
fails. If a number matters enough to write down, make something check it; if it does not, describe
the invariant and drop the digit.

---

## 2026-09-01 — CI runs lefthook's roster instead of re-spelling it

`.github/workflows/lint.yml` had fourteen steps, each a re-spelling of a `lefthook.yml` command
with a `git ls-files` expansion swapped in for `{staged_files}`. Nothing asserted the two lists
agreed, and **they had already drifted in both directions**: `brew-drift` existed only in lefthook,
`boomfile-sources` only in CI. A `boomfile.toml` edit that dangled a `src` passed `git commit`
clean and failed only after the push.

CI now runs `lefthook run pre-commit --all-files`. One roster, and the drift class is impossible
rather than merely unlikely.

**`--all-files` is load-bearing, for the same reason it is in `verify-gate.sh`.** A runner has no
index, so bare `lefthook run pre-commit` would hand every `glob:`-scoped command an empty file
list and report success for inspecting nothing. That is the identical vacuous pass this repo had
in its Stop hook, in a different place.

### Three things stay outside the roster, each for a reason

- **gitleaks.** Lefthook runs `protect --staged`, which reads the index; a runner has none, and
  the useful remote question is different anyway — does the CURRENT TREE contain a secret, rather
  than does this commit add one. Same tool, different verb.
- **`boom source --dry-run`.** Not a lint check and not a lefthook command: it is the engine
  asking whether the artifact still applies.
- **`dot-claude/hooks/tests/all.sh`, bare.** This one is the deliberate duplication, and it is
  worth naming because it looks like an oversight. Lefthook's `hook-tests` runs
  `all.sh --changed <files>`, which selects suites by reading each one's `covers:` lines — a
  latency optimisation that TRUSTS those lines. A wrong or missing `covers:` silently narrows what
  ran, and the failure mode is a regression through a green gate. Bare `all.sh` discovers the whole
  roster from the directory and is immune to that. Roughly 16 seconds to stop the selective run's
  one assumption from being load-bearing.

`zsh` moves to the setup step: lefthook's roster runs `zsh -n` over the shell payload and a runner
has no zsh, so installing it inside that command would fail mid-roster with a confusing message
instead of at setup with a clear one.

---

## 2026-09-01 — four of six "replace with native" cuts would have been regressions

An audit costed six `scripts/` gates at roughly −430 lines, on the reading that each was a native
call wrapped in 40–150 lines of framing. Working through them, **only one was.** The line counts
were right; what the lines were doing was not asked.

**Cut, and it was real — `context-budget.sh`, 200 → 139.** Two things went. `strip_comments`, 22
lines of awk plus a fenced-block bail-out, existed because the client strips block-level HTML
comments before billing, so they should not count against the ceiling. True — and neither capped
file has ever contained one, so it stripped nothing. And a `git grep` pass forbidding prose from
restating two counts this repo computes: a real rule, but enforced by a hand-built ERE with a
word-boundary workaround, which then needed its own case in `gates.sh` asserting the regex was not
written with `\b`. Three artifacts to stop a sentence containing a number. `wc -c` is the
measurement now.

**Kept, with the reason, because cutting would have cost more than it saved:**

- **`description-cap.sh`** — the audit called its 28-line awk "hand-rolled YAML for three files".
  Those 28 lines ARE the fix for a shipped bug: a one-line parser scores a folded block
  (`description: >-`) as the single word `>-`, so any skill could carry an unbounded description
  past a gate reporting `ok (1 words)`. Replacing it with a one-liner reintroduces the defect the
  suite has a regression case for.
- **`rules-scoped.sh`** — "83 lines to check that two files contain `paths:`". Six of those lines
  are an awk frontmatter reader that will not mistake a `paths:` in the body for the real one; the
  rest is the empty-input doctrine this repo requires everywhere else (a gate that checked nothing
  must not print `ok`). `grep -c '^paths:'` drops both properties.
- **`brew-resolves.sh`** — already IS the native call. `brew info --json=v2` is the check; the
  other lines are argument extraction and the error prose that tells you a cask was renamed.
- **`plist-validity.sh`** — proposed as "two lines in lefthook.yml, two in lint.yml". It is two
  assertions with a plutil/plistlib fallback, because CI runs on ubuntu where `plutil` does not
  exist. Inlining duplicates that fallback and its rationale across two YAML files — recreating
  the two-roster drift this same pass is closing elsewhere.

The general lesson, worth more than the lines: **a line count is not a measure of whether a line
earns its place.** Four of these six are long because something went wrong once and the fix is
still there. That is what a comment-dense codebase looks like when it is working.

### The one improvement in the bucket that mattered was not a cut

`brew-drift.sh` gains an assertion it was missing: a tool declared in `mise.toml` **and** installed
by brew is not "excluded", it is a double install, and whichever copy sits earlier on PATH wins.
The Brewfile documents eight of these — *"brew's wins on PATH in some shells, so mise's pin is inert
there"* — and every one of them sits in `excluded_formulae()`, so the script could never fail on the
exact state it describes. The exclusion list was a permanent amnesty, not a scope note.

The new check runs ahead of the drift comparison and is **not** subject to the exclusions, because
mise owning the name is the whole point. It reads both spellings mise accepts, bare and quoted
backend-prefixed (`"npm:heroku"`), taking the last path segment — reading only the bare form missed
three of the eight.

---

## 2026-09-01 — boom is installed by Homebrew, and PATH order is why that needed more than a Brewfile line

`brew "boom"` is declared, from the repo that doubles as its own tap. Adding the line alone would
have changed nothing: `install.sh` drops a boom at `~/.local/bin/boom`, and `.zprofile` puts
`~/.local/bin` **ahead of** brew's prefix, so the bootstrap copy keeps winning `command -v boom`
and every `brew upgrade boom` is inert. That is the same double-install shape the Brewfile already
documents for `gh`, `node`, `shellcheck` and five others — the difference is that this one is
closed rather than described.

Three parts, because arranging a property is not the same as it holding:

1. **The Brewfile declares it**, with the tap.
2. **A sync `run` step removes the bootstrap copy** once brew's binary is in place — guarded
   inside the command, so a failed formula install leaves the machine with the only boom it has.
   Removing a running executable is safe: the kernel holds the inode until the process exits.
3. **A verify `run` step asserts `command -v boom` resolves inside `$(brew --prefix)`.** This is
   invisible to every file-reading gate, because it is a property of PATH on a real machine. It
   skips cleanly where brew or boom is absent, so it stays a drift check rather than a
   portability failure.

`install.sh` stays, and stays in the README: you need a boom to apply `boomfile.toml` at all, so
the curl-pipe is a **bootstrap, not a second delivery path**. An audit had proposed deleting it as
one of "three delivery mechanisms for one artifact"; that recommendation is withdrawn. It is now
load-bearing in two places — the fresh-machine bootstrap, and the CI step that installs boom to
validate the boomfile on a runner with no Homebrew.

### What this does retire: `upgrade_on_sync = "auto"`

`"check"` stays and the comment now says why "auto" must not be used. `boom upgrade` rewrites the
binary in place; under a brew-managed prefix that desynchronises brew's manifest from what is on
disk, and the next `brew upgrade` silently reverts it. **The self-upgrade verb and Homebrew
ownership are mutually exclusive, and this repo has now chosen Homebrew.** That is a concrete
argument for deleting `boom upgrade` upstream — 217 lines whose only remaining consumer would be
a boom installed some other way — where before it was only an argument from redundancy.

### Brewfile entries removed

`bash`, `coreutils`, `moreutils`, `mysql`, `cocoapods`, `zulu@17`, `wave` and `cmux` are
undeclared. They were added after drift detection found them installed-but-undeclared; the owner
confirmed none is in use. **Declaring drift was never the same as justifying it** — the earlier
comment "each is here for a reason that mise does not serve" was reasoning about categories, not
about use. `wave` additionally contradicted `ghostty/config`'s claim to be "the sole terminal".

`brew bundle` never uninstalls, so all eight remain on the machine until `brew uninstall` runs by
hand; `brew bundle cleanup` lists them.

An audit had proposed this cut and then retracted it, on the grounds that "unreferenced in this
repo" is not evidence for a profile shared with work. The retraction was right and the answer
still came out the same way — but it came from the owner, not from a grep.

## 2026-09-01 — the agent commits as `alxjrvs+claude@gmail.com` in work orgs, deliberately

`_owned_orgs()` grants write reach into five organisations the owner does not solely own, and
`GIT_AUTHOR_EMAIL` is one global value, so every agent commit in those orgs carries a personal
address. Raised as an open question (CLA/DCO exposure, corp expectations) and **answered: keep
it.** The `+claude` alias is the point — it is identifiably an agent and identifiably him.

Recorded because the alternative had a real cost worth knowing was declined: a per-org address
cannot be one global env var, and the git-native way to do it —
`[includeIf "hasconfig:remote.*.url:**/TheGnarCo/**"]` — is context detection, which is the
nearest thing this config has to a genuine counterexample to "one config, every machine, no host
detection." It stays a counterexample nobody had to take.

---

## 2026-09-01 — a plugin was considered and declined; boom is the delivery mechanism

An audit proposed publishing this config as a Claude Code plugin, on the documented trigger
*"a second repository needs the same setup"* and on this repo's own North Star word
**shareable**. It is declined, and the reasoning is recorded so it is not reopened every audit.

**boom already delivers all of it, and the two paths are mutually exclusive rather than
additive.** `boomfile.toml` links `dot-claude/{hooks,skills,agents,rules}` into `~/.claude/`, and
all ten hook handlers in `settings.json` are absolute `~/.claude/hooks/*.sh` paths. A plugin
supplies hooks through its own manifest instead — so adopting one locally means deleting those
ten handlers, at which point `settings-guardrails.sh` fails, correctly, because `wired_hooks()`
greps `settings.json` for each guard filename and can no longer see them. That is a migration
paid for by the owner to re-solve a solved problem, while breaking the one gate worth keeping.

It is also the exact pattern this audit condemned elsewhere — boom's three delivery mechanisms
for one binary, and the two hand-maintained CI/lefthook rosters that had already drifted.

**If it ever becomes worth doing, the shape is a standalone marketplace repo**, consumed the way
`extraKnownMarketplaces.gnar` → `TheGnarCo/agent-skills` already is, and never inside dotFiles.
The trigger should be a person asking for a specific guard, not a packaging exercise: building it
speculatively is the same move as `ssh/config`'s "so future per-org keys have a place to land",
which this pass deleted for being speculative.

**And only three of the seven guards are publishable at all**, which is worth knowing before
committing to a repo for them. `worktree-remove-guard.sh` and `worktree-port.sh` are pure git and
worktree semantics with nothing personal in them; `rebase-guard.sh` mostly is. The other four
encode this machine: `repo-scope-guard.sh` hardcodes `_owned_orgs()`, `op-guard.sh` assumes
op-agent and the `claude-agent` vault, `verify-gate.sh` assumes lefthook is the repo's gate, and
`worktree-freshness.sh` is a version-pinned workaround that would spread past its expiry. The
shareable surface is smaller, and less interesting, than the guard count suggests.

---

## 2026-09-01 — the retention rule cuts the other way on a removed setting, and this file proved it

This file's Retention section says an entry about code that no longer exists can go. An audit
applied that rule and proposed deleting *the credential scrub was also a permission-mode switch
(2026-08-31)*, 77 lines about a settings key that had been removed the day before.

**Then the same audit recommended re-adding that key**, from vendor documentation, in the very
next pass. The entry is what stopped it: it had already measured that
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` scrubs zero of this machine's variables, misses
`GITHUB_TOKEN`, `GH_TOKEN` and `NPM_TOKEN`, and silently forces the session's permission mode to
`default`. The key was added during implementation and reverted within the hour.

So the rule needs the qualifier it was missing: **an entry about removed code is dead only if
nothing would plausibly re-add it.** An entry recording why something was removed is a control
against re-adoption, and the more reasonable the thing looks in vendor docs, the more that entry
is worth. A recommendation drawn from documentation is not evidence about this machine.

What was cut instead, in the same pass, is the class that genuinely rots: **procedure duplicated
from the `agent-friendly-repo` skill** — the stacks/merge-queue mechanics, the classic
branch-protection payload, the Dependabot workflow steps — where the skill is the copy that gets
used and this one silently diverged (it still carried a claim the skill had withdrawn, and a
strikethrough-plus-correction this file's own rule forbids). Plus one entry restating
`rules/guards.md`. About 100 lines, none of it a measurement, none of it an incident.

---

## 2026-09-01 — three payload settings that had never done anything

Found by reading each config against its tool's own source rather than its comment.

**`starship.toml` — the ahead/behind counters have never rendered.** The `git_status` format
string named `$ahead$behind$diverged`. Starship's `git_status` module exposes **`ahead_behind`**
as the format variable (`src/modules/git_status.rs`); `ahead`, `behind` and `diverged` are
*options* consumed through it, not variables. An unmapped name renders as the empty string with no
warning, so the carefully-reasoned ASCII `^`/`v` markers below the format line fed nothing. Same
shape as the fzf-tab widget that existed and was never reachable, already recorded in
`zsh/60-tools.zsh`.

**fd's global ignore was never global.** The file lived at `~/.fdignore`. fd's README documents
the global ignore file as **`~/.config/fd/ignore`**; `.fdignore` is parent-walked like
`.gitignore` and stops at the enclosing repo root, so inside any project it was not applying. It
moves to the documented path, and `.git/` is now in it on fd's own advice — *"You may wish to
include `.git/` in your fd/ignore file so that `.git` directories … are not included in output if
you use the --hidden option"* — which both fzf commands do. That deletes the duplicated
`--exclude .git` each of them carried.

**ripgrep was walking the object store on every search.** `.ripgreprc` sets `--hidden` with
nothing excluding `.git`, and ripgrep's own flag docs say `--hidden` *"will include files and
folders like .git … you must explicitly ignore them using another flag or ignore file."*
`.fdignore` is fd-only and there was no `~/.ignore`. ripgrep has no auto-loaded global ignore file
— its config is only read via `RIPGREP_CONFIG_PATH`, which `zsh/00-exports.zsh` does set — so the
fix is `--glob=!.git/` in `.ripgreprc` rather than a second shared ignore file.

A shared `~/.ignore` was tried first and reverted: both fd and rg read `.ignore`, but both walk it
from the search directory upward and stop at the repo root, so it is not a global mechanism for
either. Two tools, two documented mechanisms, and neither is the one that looked obvious.

### And the launchd job stopped logging to /tmp

`StandardOutPath` and `StandardErrorPath` both pointed at a predictable filename in
world-writable `/tmp` — a symlink-plant surface, and the same hazard `ssh/config` already avoids
by putting ControlPath sockets under `~/.ssh/cm`. They could not simply move: launchd does not
expand `~` or `$HOME` in plist values, and a `~`-prefixed log path failed this job with
`EX_CONFIG` (78) before it could run hidutil. The answer was not to log at all — `hidutil` prints
its result dict on success, which is noise, and launchd already records the exit status.

---

## 2026-09-01 — the vault audit governed three items, and its one firing was wrong

`op-agent audit` is deleted: 137 lines (plus `_prefixed`) asserting that three declared vault
items exist, in one direction, plus a kebab-case regex over three hand-written strings. The
`boom verify` step that called it goes with it, and `agent-vault.txt` drops from 61 lines to 20 —
three data lines under 57 lines of essay, in a repo whose own routing table sends reasons and
incidents *here*.

The half worth having was already gone. Its own comments recorded why: the reverse check — an
item in the vault that the manifest does not name — *"made the vault effectively read-only,
because adding or retiring a credential failed `boom verify` until this file was edited in the
same breath,"* so it was removed. What remained asserts that three declared items exist, which
every consumer reports on first resolve anyway.

And the orphan-consumer half had exactly one recorded firing, on 2026-08-29, and it was a **false
positive**: it reported `claude-git-pat` unconsumed while git was resolving it on every push.

Three facts the deleted prose carried, kept because they are still load-bearing and are now here
rather than in a file symlinked nowhere:

1. **SA vault access is immutable after creation.** Scope cannot be tightened in place; only the
   vault's contents can change. Membership is therefore the only lever over blast radius, which
   is why keeping the vault small still matters — as a judgement when adding, not a machine gate.
2. **No activity log exists.** Individual/Family accounts get no Activity Log and no
   service-account usage report, so there is no per-item record of what the SA read. Accepted
   deliberately (2026-08-19).
3. **Kebab-case is a real constraint, not tidiness.** Every `op://` ref is re-parsed by `sh -c`,
   so a space word-splits and the resolve fails silently — the bug that took down two MCP servers
   on 2026-07-25.

`_sa_expiry_epoch` is untouched. 1Password exposes no service-account token expiry — no API, no UI
field, no pre-expiry alert — so decoding the JWT `exp` locally is the only way to know, and it is
the best bespoke code in this repo.

### The gate roster rotted again, in the file that warns about it

`dot-claude/agents/guard-tester.md` listed seven gates and omitted `scripts/rules-scoped.sh`,
which has been a lefthook and CI check since 2026-08-29. Its own note records the previous
instance — *"an earlier version… promised 'seven', and was wrong by two before anyone read it
again."*

The roster exists in three places (this agent, `lefthook.yml`, `.github/workflows/lint.yml`) and
nothing asserts they agree, which is the same two-roster class that let `brew-drift` live only in
lefthook and `boomfile-sources` only in CI. Adding the missing line is the fix that was available
today; a single `scripts/check.sh` that all three call is the fix that would stop it recurring,
and it is not taken here because it is machinery added during a pass that is removing machinery.
Recorded so the next person weighing it has the count: three copies, two recorded rots.

### Also in this pass: the tests that tested the test runner

`scripts/tests/gates.sh` loses its last section — four cases and a `mk_all` helper, 51 lines,
asserting that `dot-claude/hooks/tests/all.sh` fails when pointed at an empty directory, reports a
failing suite, and refuses a non-executable one. Tests, for a test runner, for the suites that
test the guards: three levels of indirection from any file that reaches a machine.

The cases that stay are the ones encoding bugs that actually shipped — the folded-scalar
description parser, the unclassified `~/.claude/` link, the `\b` that git grep silently ignores,
the unwired-guard assertion — plus the cheap negative controls for an empty CI glob.

---

## 2026-09-01 — the engine now validates the artifact, because nothing did

`lefthook.yml` stated that `boomfile.toml` was *"validated by `boom source --dry-run`"*. Grepping
CI, lefthook and `scripts/` for that command returned only prose — two comments and an error
string. **Nothing in this repo had ever run it.** `taplo check --no-schema` proved 772 lines of
TOML parse; nothing proved they apply.

Meanwhile `scripts/boomfile-sources.sh` was 63 lines hand-reimplementing one slice of the engine's
own planning pass — src-path existence, with its own glob-expansion branch — which is the exact
shape `CLAUDE.md` calls out: *native over special; deleting custom code for a built-in is the
highest-value change.* It is deleted, along with its fixture and three `gates.sh` cases.

CI now runs `boom source --dry-run` against the checkout. That covers what the shell script did
and everything it could not: link modes, dir modes, the `absent` path, glob fan-outs, hook
resolution, package manifests, and schema validity as the engine actually reads them.

**Why it is safe on a runner**, by construction rather than by hope: `--dry-run` makes `run` steps
no-ops (`run.ts` refuses to spawn a shell under it), `osx_default` and `launchd` are OS-gated to
darwin so they report and change nothing on ubuntu, and both repo hooks honour `api.dryRun`.

It installs boom through the published bootstrap pinned to the tag README documents, so the step
doubles as a check that the documented fresh-machine install path still works — and `install.sh`
verifies the binary against the release's `SHA256SUMS` and refuses to install unverified.

---

## 2026-09-01 — three controls that were describing themselves, and one that was passing on work it never read

An external audit went looking for what this config could delete. The three findings that
mattered were not size at all: they were controls that read as enforcement and enforced nothing.
Each was confirmed by running it, not by reading it.

### The `sandbox` block is deleted, and two of its paths promoted

`sandbox.enabled` was never set, and it defaults to `false`. *The sandbox measured: egress works,
and `credentials.files` would break op-agent (2026-08-18)* already established that
`sandbox.credentials` and `sandbox.filesystem` bind only to sandboxed Bash, and the 2026-08-28
pass changed `mask` to `deny` and left the block standing anyway. So six credential denials and
four `denyRead` paths sat in the file, looked like a posture, and bound to nothing — in the config
whose own `CLAUDE.md` says *already enforced → nowhere; describing a control is not the control.*

Deleting an inert block would have silently dropped the intent behind it, so the two `denyRead`
paths with no live equivalent — `~/.config/gh/hosts.yml` and `~/.netrc` — are now `Read()` entries
in `permissions.deny`, where they are evaluated before `auto` and before bypass. The other two
already were.

**Enabling the sandbox instead remains available and is a separate, larger decision**: it confines
writes and needs a network allowlist, and the 2026-08-18 entry measured that `credentials.files`
breaks op-agent. That is a day of work on a machine shared with employer repositories, and it
should be taken deliberately rather than as a side effect of an audit.

### `verify-gate.sh` was passing vacuously, in its most common case

The Stop hook ran `lefthook run pre-commit`, which inspects the **index**. At the end of an agent
turn the index is empty — the work is written and unstaged. Fourteen of this repo's sixteen
pre-commit commands are `glob:`-scoped against `{staged_files}`, so fourteen received no files and
skipped, and the gate reported success on work it had never opened. Its header claimed *"a pass
here means the commit will pass too."*

Its suite could not see this: the stub `lefthook` returned a canned exit code for any argument
list, so every case passed while the hook was vacuous. The stub now **refuses an invocation
without `--all-files`**, which is the assertion that would have caught it.

Two further corrections in the same file. `stop_hook_active` **is** documented on Stop input, and
the client ends the turn after 8 consecutive blocks; the header said no such field existed and
hand-rolled a session-keyed marker to stand in for it. And that marker armed only *after* a
failure, so a passing session re-ran the full gate every dirty turn while a failing one went quiet
for good. The marker is now keyed by tree state — `status --porcelain` **and** `diff HEAD`, because
porcelain alone prints ` M f.txt` whatever the file now contains, which the suite caught.

### `identity-drift.sh` is deleted, because it had already failed open

Six of its twenty-four allowlist entries named files that still exist and no longer carry the
owner. It compares one way (`comm -23`), so the allowlist rots **permissive** and nothing notices:
those six could re-acquire a hardcoded owner and the gate would still print
`ok identity-drift (18 files name 'alxjrvs', all documented)`. Fixing it means a second comparison
and more machinery, to protect a `git grep -il alxjrvs` that a forker runs once, ever. README now
says the list is unenforced rather than implying a gate stands behind it.

### Also removed

`.claude/settings.json`'s `OTEL_RESOURCE_ATTRIBUTES` labelled metrics that are never emitted —
telemetry needs `CLAUDE_CODE_ENABLE_TELEMETRY` and an exporter, and neither exists anywhere here.
`attribution.pr` carried a `Co-Authored-By:` trailer, but pull request descriptions get **plain
text**; only commits get trailers, so it was prose pretending to be a co-author record.
`env.NINETY_BASE_URL` had no `_COMMAND` sibling and no consumer. And the project-scope
`Bash(git fetch *)` never matched a bare `git fetch` — the trailing space needs text after it,
which is the exact gotcha `rules/claude-settings.md` documents.

### Declined, again: `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`

The audit recommended adopting it from the vendor documentation. It was added to
`dot-claude/settings.json` during this work and then reverted, because *the credential scrub was
also a permission-mode switch (2026-08-31)* — directly above — had already measured that it
scrubs **zero** of this machine's variables, misses `GITHUB_TOKEN`, `GH_TOKEN` and `NPM_TOKEN`,
and silently forces the session's permission mode to `default`.

Worth recording as a pattern rather than a one-off: a recommendation drawn from vendor docs is not
evidence about **this** machine, and this file is what stands between a good general suggestion and
a measured local regression. It earned its keep here.

---

## 2026-08-31 — the credential scrub was also a permission-mode switch

`env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"` is removed. It was added 2026-06-05 as finding BP-3
of the sandbox audit — *"strip cloud creds from sandboxed subprocesses; companion control for the
gh-token-in-env pattern"* — and it survived the 2026-08-28 cleanup that found the rest of the
`sandbox.*` block inert, on the grounds that it was the half that worked without
`sandbox.enabled`. That was true. It was also the wrong question: it worked, on nothing.

### What the flag actually does

Three behaviours hang off the one variable, measured against Claude Code **2.1.251**:

1. Strips a **206-name** credential list from the environment of every spawned subprocess, in
   three spellings each (bare, `INPUT_`-prefixed, lowercased for `NPM_CONFIG_*`), plus a
   connection-string name regex, plus rewriting registry URLs down to bare origin.
2. Blocks reads of the `.env` family. This is the behaviour *The sandbox measured: egress works,
   and `credentials.files` would break op-agent (2026-08-18)* already warned about: it makes
   Claude Code ignore `filesystem.disabled` from every source.
3. **Forces the session's permission mode to `default`** — undocumented, and the reason this
   entry exists.

### Why it went

**It scrubbed nothing.** The 206 names match zero variables in this machine's environment
(`ANTHROPIC_*`, `AWS_*`, `GOOGLE_*`, `GCP_*`: none set). That is not luck, it is the op-agent
design — the SA token is read inline inside op-agent's own process and never enters the parent
env, which *The sandbox measured: egress works, and `credentials.files` would break op-agent
(2026-08-18)* had already concluded when it said not to set this flag alongside an allowlist.

**And it missed the ones that exist.** The BP-3 commit shipped with an explicit open question:
*"Scrubbed-pattern list is undocumented — may not cover `GITHUB_*` vars."* It does not. The list
contains `OVERRIDE_GITHUB_TOKEN` and `GH_CONFIG_DIR`, and neither `GITHUB_TOKEN`, `GH_TOKEN`, nor
`NPM_TOKEN` — precisely the three `sandbox.credentials.envVars` names, and precisely the
"gh-token-in-env pattern" the flag was adopted to cover. The companion control did not cover its
companion.

**What it cost instead.** The permission-mode resolver's first statement is a truthiness test on
this variable; it returns `default` before reading the CLI flag, `permissions.defaultMode`, or
agent frontmatter. Reproduced live:

```
$ CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 claude -p "ok" --permission-mode auto
⚠ Permission mode forced to default — CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set …
```

The same command with `=0` prints the identical warning: `settings.env` re-applies `"1"` into
`process.env` before the mode resolves, so **the shell value loses to the settings value.** While
this key was in `settings.json` there was no per-invocation opt-out.

That warning only renders when a mode was supplied explicitly. A mode arriving from
`permissions.defaultMode` sets no such flag, so the machine's `defaultMode: auto` was downgraded
**silently** — which is why this went unnoticed from 2026-06-05 to 2026-08-31.

### The size of the effect, and the correction it forced

Across the last 80 session transcripts, 19 carry permission-mode records: 15 reached `auto`, 4 did
not, and those 4 had one or two records each — they ended before anything re-resolved. Ten of the
15 were `auto` from their very first record. So this is a **race** between `settings.env` landing
in `process.env` and the mode resolving, not a permanent lock: agents boot manual, prompt for a
few turns, and most then flip. A first pass at this read only the head of each transcript and
concluded three sessions "ran their whole life in manual"; reading the files whole says otherwise,
and the intermittency is the actual signature.

### Declined

The scrub has a second enable path — `GITHUB_ACTIONS` truthy with this variable *absent* — that
turns on the scrubbing without the mode check ever reading it. Setting `GITHUB_ACTIONS=1` locally
would thread the needle and is not worth it: that variable is read by far more than this flag —
every CI branch in the CLI, and in whatever the agent shells out to — and it would be set to buy a
scrub that has nothing to scrub. Which of those branches change was not measured, and the point is
that nobody should have to know.

Nothing replaces it. `permissions.deny` already blocks the Bash path to the tokens that do exist
and is evaluated before `auto` and bypass; `sandbox.credentials.envVars` covers the env-at-rest
case and stays inert until `sandbox.enabled`, which remains a separate decision. This entry pairs
with the 2026-08-20 removal of `skipAutoPermissionPrompt`: that one restored a prompt that was
being suppressed, this one restores the mode that was being overridden.

---

## 2026-08-29 — the byte ceiling was destroying guidance a free mechanism holds

`scripts/context-budget.sh` caps the two symlinked `CLAUDE.md` files, and the cap works: it
is the only thing that ever made a cut permanent. But it had exactly one lever — deletion —
and that turned out to be a choice, not a constraint.

Claude Code supports `~/.claude/rules/`, where a rule carrying `paths:` frontmatter loads
**only when Claude reads a file matching one of its globs**. Guidance that is only true while
editing one kind of file can therefore be written at any length and still cost a session
nothing until that file is opened. A rule *without* `paths:` loads at launch with the same
priority as `CLAUDE.md` — so the frontmatter is the whole difference between free and billed,
and `scripts/rules-scoped.sh` gates it.

Two rules moved out of the always-loaded file immediately: the Bash-pattern gotcha (`Bash(ls *)`
misses `lsof`) and the empty-string env vars, both useful only while editing a `settings.json`.
That is 325 bytes off a 1,800-byte file — but the size is the smaller half. Always-on guidance
is *worse targeted*: it was paid for on every request and read at the moment it mattered only
by luck. Scoped, it fires exactly when it applies.

Two calibrations worth recording, because both cut against how strict this repo had been:

- Anthropic's published guidance is *"target under 200 lines per CLAUDE.md file."* Both files
  here are under 40. The self-imposed ceiling is roughly 5× stricter than the published one.
  That is a defensible choice and it stays — but it was being paid for in deleted guidance,
  which is a real cost that nobody had priced.
- Block-level HTML comments are stripped before injection, so a maintainer note costs zero
  tokens. The ceiling had been counting them, which meant free content was competing for a
  scarce budget and losing. Fixed in the same pass.

What this does NOT change: the routing table still sends a procedure to a skill and a reason
here. A rule is the fourth destination, for the narrow case of "true only while touching these
files". The failure mode to watch is a rule becoming a second CLAUDE.md by accumulation, which
is why the directory is exempt from the ceiling only on the condition `rules-scoped.sh` asserts.

## 2026-08-29 — `AGENTS.md` considered, and declined

`AGENTS.md` is a real de-facto standard: 60,000+ repos, stewarded by the Agentic AI
Foundation under the Linux Foundation, and read by Codex, Jules, Cursor, Factory and Amp.
It is recorded here as **declined**, not overlooked, so the next person to notice its absence
finds a reason instead of a gap.

Claude Code does not read it. The docs are flat about this — *"Claude Code reads `CLAUDE.md`,
not `AGENTS.md`"* — and offer two bridges: an `@AGENTS.md` import line, or
`ln -s AGENTS.md CLAUDE.md`.

Neither buys anything here, and the import actively costs. Imported files *"are expanded and
loaded into context at launch"*, so an import is context-neutral at best while adding a hop
that `context-budget.sh` would have to follow to keep measuring the right bytes. A symlink
avoids the cost but only works when there is no Claude-specific content, and there is.

The condition that would reverse this is narrow and worth naming: **a second agent on this
machine.** Until then the standard is solving a problem this setup does not have — one agent,
one instruction file.

## 2026-08-29 — the protected-branch rule is enforced twice, and both stay

`autoMode.hard_deny` carries *"Never push directly to a repository's default branch, and never
merge into it locally"*. `rebase-guard.sh` blocks the same push by tokenizing the command. The
two overlap completely on that one shape, and an audit flagged it as redundancy.

It is not. They fail differently, which is the whole reason to keep both:

- `hard_deny` is a **natural-language rule read by a classifier**. It covers shapes nobody
  enumerated — a novel git alias, an unfamiliar porcelain — and it applies unconditionally,
  ahead of user intent and `allow` exceptions. What it cannot promise is determinism.
- `rebase-guard.sh` is **deterministic tokenization**. It resolves `origin/HEAD`, walks the
  argument list, and is immune to phrasing. What it cannot do is generalize: a shape its
  tokenizer does not model passes.

A classifier miss and a tokenizer gap are uncorrelated failures, so the pair is defense in
depth rather than duplication. `rebase-guard.sh` also owns a second job that `hard_deny` does
not touch at all — refusing a push when the branch is *behind* its target.

Recorded because the overlap looks like waste from either side alone, and the next cleanup
that notices it should remove neither.

## 2026-08-28 — the sandbox block was inert, and `mask` would have broken auth if it were not

`sandbox.enabled` is opt-in and unset in every settings file on this machine, and both
`sandbox.credentials` and `sandbox.filesystem` affect **sandboxed Bash commands only**. So the
six masked credentials and the `denyRead` list enforced nothing. This file called that block
"the countermeasure for the transcript leak" — the repo's own routing table has a row for this:
*already enforced → nowhere. Describing a control is not the control.* This was a control that
described itself.

**And enabling it as written would have been worse than leaving it off.** All six entries used
`mode: "mask"`, which does not block a credential — it shows the command a sentinel and has the
sandbox proxy swap the real value back in on outbound requests to hosts named in `injectHosts`.
That requires `network.tlsTerminate` and the destination in `network.allowedDomains`. Neither is
set, and there is no `injectHosts` anywhere. The documented result: *"masking fails without
exposing anything: the command still sees only the sentinel, but the sentinel reaches the server
unchanged and authentication fails."* Every `gh` and `npm` call inside the sandbox would have
authenticated with a sentinel.

So the modes are now `deny`, which unsets the variable before each sandboxed command — the mode
that is correct for a configuration with no network block. `mask` is the right answer only
alongside a full network policy, and that is a different change.

Two claims from the audit were checked and **not** acted on:

- *"Move `~/.config/gh/hosts.yml` out of `filesystem.denyRead` into `credentials.files`."* The
  docs say a `credentials.files` entry with `mode: "deny"` applies *"the same restriction that
  `filesystem.denyRead` applies"*. The two are equivalent for reads, so the move buys nothing and
  the churn was declined.
- *"There is no `unset` mode."* The audit recommended `mode: "unset"`. The documented values are
  `deny` and `mask`; `deny` is the one that unsets. Writing `unset` would have produced invalid
  config.

`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is the part that works without any of this: it strips
Anthropic and cloud-provider credentials from **all** subprocesses regardless of sandboxing. It
is set now, because it needed nothing else to be true first.

> Superseded by [2026-08-31 — the credential scrub was also a permission-mode switch](#2026-08-31--the-credential-scrub-was-also-a-permission-mode-switch)

Turning `sandbox.enabled` on is deliberately not part of this change. Go-based CLIs — `gh`,
`gcloud`, `terraform` — are documented to fail TLS verification under macOS Seatbelt and need
`excludedCommands`; `open` and `osascript` are blocked by default; and `.gitconfig` routes git
credentials through the keychain and `op-agent`. Each is a way for "the sandbox is on" to present
as "git is broken". It needs a live `/sandbox` session and a real push, which is a human test.

## 2026-08-26 — heroku: the Brewfile was the obvious home and the wrong one

The `.gitconfig` landed a credential helper for `git.heroku.com` (`helper = !heroku
git:credentials`) — appended by the heroku CLI itself, and committed so it would stop
re-dirtying boom's config cache on every use. That left a stanza naming a binary the Brewfile
did not install, so the obvious fix was to declare `brew "heroku"`.

It does not work. There is no homebrew-core formula for heroku. The only source is the
third-party tap `heroku/brew`, and brew now classifies that tap as **Untrusted** and refuses to
load the formula at all:

> Refusing to load formula heroku/brew/heroku from untrusted tap heroku/brew.
> Run `brew trust --formula heroku/brew/heroku` or `brew trust heroku/brew` to trust it.

`brew trust` is interactive, and `boom source` runs unattended. A Brewfile line that requires a
human is a fresh machine that stops halfway through its first converge — which is the one thing
the Brewfile exists to prevent. **A declaration that cannot run unattended is not a
declaration.** That, not the Lean A policy, is the reason it went to `mise.toml`; the policy
merely agreed.

Two things found while checking, both arguing the same way:

- The installed brew copy had **self-updated past its own Cellar version**: the symlink pointed
  at `Cellar/heroku/11.3.0`, and the binary it resolved to reported `11.9.0`. The heroku CLI
  updates itself in place, so brew's record of its version was already false, and any
  `boom.lock` pin for it would have been recording a number nothing controlled.
- `mise registry heroku` resolves to `npm:heroku`, which installs clean and lands *ahead* of
  both (11.10.0). The repo already runs `npm:` backends for two language servers, so this adds
  a package, not a mechanism.

The brew copy is now shadowed, not competing. This was worth checking rather than assuming,
because the Brewfile's `gh` note describes the opposite outcome — two installs, brew's winning on
PATH, mise's pin inert — and the obvious inference was that heroku would repeat it. It does not:
`.zshenv` prepends the mise shims and `.zprofile` re-prepends them *last*, specifically because
everything above that line demotes them, so `command -v heroku` resolves to the shim and mise's
pin is live. The `gh` collision is what that PATH work exists to prevent; quoting it as a present
danger would have been describing a failure the config already fixed.

So removing the brew copy is hygiene, not a correctness fix: it reclaims the Cellar, and it drops
an Untrusted tap from the machine, which is worth doing on its own. Nothing breaks while it sits
there.

## 2026-08-22 — a `headersHelper` can point at a deleted vault item and still pass `boom verify`

Asked whether frequently-used keys could be moved into the agent vault. The answer was **nothing
to move**: this machine resolves exactly the items `agent-vault.txt` declares, each with a live
consumer, and `op item list --vault claude-agent` agreed with the file. The vault was already
reduced to its consumers on 2026-08-19 and had not drifted. Recording it because "we checked and
there was no work" is the finding, and without a note the same audit gets redone.

**What the audit did turn up, running the other way.** The `render` MCP server (project-scoped to
`~/Code/SU-SRD`) carried a local-scope `headersHelper` resolving
`op://claude-agent/render-api-key/credential` — an item that is not in the vault. `claude mcp list`
reported `render ✘ Failed to connect — Incompatible auth server: does not support dynamic client
registration`, while `github`, on the identical `op-agent header` mechanism, connected. So the
service-account path was healthy and only the missing item was broken.

**The blind spot, and why it stays open.** The `~/.claude.json` assertion in `boomfile.toml` proves
each helper's BINARY is executable. `op-agent` is executable, so the check was green the whole
time; a helper whose `op://` ref no longer resolves exits 0 and emits `{}`, which is
indistinguishable from success at that layer. Closing it means resolving a secret at verify time,
and `boom verify` runs unattended from launchd — a timer that resolves credentials is a standing
exfiltration surface pointed at the one vault the SA can read. Worse than the blind spot, so it is
left open and named in the boomfile comment instead. `claude mcp list` is the control that catches
this class, which `SU-SRD/docs/architecture/agent-tooling.md` already prescribes.

**A comment that was wrong in the direction that hides the bug.** The same boomfile block claimed
`render-api-key` was dropped "because no `render` server exists in any scope". A server did exist,
in two scopes. That framing is what made the gap above read as already-handled, so it was replaced
rather than deleted — per this file's rule that a wrong line is corrected in place.

**Three guardrails refused this work in a row, and each refusal was right.** op-guard denied
`op item move --destination-vault claude-agent` (inbound moves are self-escalation — an agent
granting itself a credential); the auto-mode classifier denied `claude mcp remove`, which is the
restored human gate from removing `skipAutoPermissionPrompt` doing its job on a mutating config
change; and SU-SRD's own cutover plan denied deleting `render` from `.mcp.json`, because that is a
**P8** step and P8 is gated behind a P7 that is still red. The pull each time was to route around
a control that was correctly saying no — including one temptation to reach the blocked edit with
`jq` instead, which would have been the same mutation evading the same gate. The near-miss worth
recording: deleting a documented server over a misleading auth error is precisely how the GitHub
MCP was once removed instead of repaired, and the error string here was character-for-character
the one in that incident.

### The rule that survives

Keep a sentence in an always-loaded file only if a session must believe it **before its first
tool call**, and no hook, permission rule, verify step, test suite, or on-demand skill will tell
it in time. Then write it as a bare imperative — no date, no version, no "measured", no past
incident. **If the rewrite comes out empty, it was a postmortem.** Two corollaries need no
judgment: if the reader is necessarily already looking at one file, it belongs in that file's
header comment; and a sentence naming a version of fast-moving software is expiring by
construction, so it becomes an assertion something re-runs, or it comes here.

Applied strictly, six rules survived — the ones that are irreversible on first attempt or land in
an unattended session with nobody to ask. Two of them (foreign-repo writes, force-removing a
worktree whose lock PID is alive) should become guards, after which their bullets delete.

## Permissions & security

### `op` became usable by agents by inverting the list, not by loosening it (2026-08-18)

The ask was "I want op to be usable by the bots, according to 1Password best practices." The
starting state was `permissions.deny` → `Bash(op:*)`, scoped to the whole binary, which is the
control the 2026-08-05 entry below argues for. Measured first, from a live session: **`op --version`
was denied.** So was `op run -- npm publish`. `CLAUDE.md` had already conceded that second one as
"the one real cost" with the advice "run it from your own terminal" — an honest note that had
quietly become the whole story, because the *only* things left were the ones that print secrets.

**`op run` is the shape the vendor recommends, and it is safe for a different reason than the
allow-list usually relies on.** 1Password: *"If a subprocess used with `op run` prints a secret to
`stdout`, the secret will be concealed by default"* — a PTY wrapper, with `--no-masking` as an
explicit opt-out. So `op run` is not merely "doesn't print a secret"; it actively defends the
stdout channel that the 2026-07-25 incident leaked through. `op read` and `op inject` carry no such
guarantee (`op read` prints by contract; bare `op inject` renders the whole template to stdout).
That asymmetry, not taste, is where the line got drawn.

**The real argument is direction, and it is the generalisable part.** The 2026-08-05 entry is
right that enumerating verbs failed — but it failed *as a deny-list*, and a deny-list fails **open**
on the verb nobody thought of. That is precisely how `op-agent header`, the one command with a
confirmed leak, stayed reachable while `op-agent secret`, which never leaked, was blocked twice.
The fix is not a better-curated deny-list; it is an **allow-list**, which fails **closed**. So
`op-guard.sh` (a third `PreToolUse` guard, ordered first) permits a named set of non-printing
shapes and denies everything else `op`-shaped. `op read`, `op document get`, `op item delete`, a
verb 1Password ships next year, and a typo now fail the same closed way.

Consequences worth keeping:

- **The deny entries stopped being the control and became the residue.** They now cover the three
  printing `op` verbs and the whole `op-agent` binary — the paths with a confirmed incident — and
  exist for the case where the guard is unreachable. `op-agent` stays binary-scoped because it is
  plumbing: MCP resolvers and git exec it themselves, so nothing is lost.
- **A hook that only ever denies.** `op-guard.sh` never emits `permissionDecision: "allow"`,
  because a hook `allow` bypasses the permission system and would put the guard *above*
  `permissions.deny`. Denying-or-silent means it can subtract permission and never add it, so the
  two layers compose instead of racing. Worth copying to any future security hook.
- **Allow-listing `op run` opened a hole in a *different* guard, and it was closed in the same
  commit.** `op run -- git push origin main` presents `op` as the program, so `rebase-guard.sh` —
  which tokenizes for a `git`/`gh` program — never sees the push. op-guard denies a `git`/`gh`
  child for that reason alone; neither gets credentials from `op run` anyway. The general lesson:
  when you permit a *wrapper*, check what every other guard's tokenizer now fails to see.
- **The interpreter residue is closed for `op`.** `CLAUDE.md` records that deny "cannot cover an
  arbitrary interpreter — `sh -c 'op read …'` still walks past". A hook that tokenizes can: op-guard
  takes a basename (every path spelling) and scans an interpreter's payload for an `op`
  subcommand, anchored on the subcommand so `xargs grep op foo` and `bash -c 'echo loop'` do not
  trip it. Still open for everything else deny covers.
- **Scope creep was declined explicitly.** `op vault list` / `op item list` print no secret value
  and would pass a naive "does it print a secret" test, but this file's own 2026-08-05 measurement
  is that `op vault list` enumerates every vault in the account through the desktop integration,
  well outside `claude-agent`. They were denied before and stay denied. **An allow-list is where
  scope creep is cheapest to add and hardest to notice** — every future addition should have to
  name the consumer that needs it.
- **The pairing is asserted, not trusted.** `permissions.allow` carries `Bash(op run:*)` so the
  recommended shape is deterministic rather than left to the probabilistic classifier — which this
  file already records deciding identically-shaped commands differently. That pre-approval is only
  safe with the guard in front of it, so every enforcement point (`boomfile.toml`,
  `lefthook.yml`, `lint.yml`) now also asserts `op-guard.sh` is wired. Un-wiring the hook while
  leaving the allow entry is the single edit that would turn this change from narrower into wider.
- **53 regression cases written before the deny list was relaxed**, and a negative control run
  afterwards (inverting two expectations produced exactly two failures), because a new block that
  passes first try is indistinguishable from a harness that defaults to `allow`.

What was researched and **not** adopted: 1Password ships an Environments MCP Server, but it runs
inside the desktop app and gates on interactive approval prompts, so it cannot serve a headless or
unattended session; 1Password for Claude is Desktop/Chrome autofill only; and the Claude Code shell
plugin manages `ANTHROPIC_API_KEY`, not vault access. Their documented recommendation for
unattended agents is still service account + `op://` at runtime — which is what `op-agent` already
is. 1Password's own position also argues against routing secrets through MCP at all: *"No strong
revocation model exists once secrets are passed into context."* So the architecture needed no
change; only the control in front of it did.

### A diagnostic printed a live PAT into a transcript (2026-07-25)

A command ran `op-agent header` without redirecting stdout, so a live PAT landed in a session
transcript. The token was rotated.

This is the origin of the "never echo a secret — always `>/dev/null` and test the exit code" rule.
The `op-agent` design keeps secrets out of the model's context *by default*; that guarantee only
holds if callers don't defeat it by printing the result.

**The remediation went to the wrong layer, and it took a year to notice (fixed 2026-08-05).** The
commit that responded to this incident added four deny entries — `op-agent secret` (twice),
`op read`, `op item get` — and **not** `op-agent header`, the command that actually leaked. So the
one verb with a confirmed incident, a rotated token and a written postmortem stayed reachable,
while the verb that never leaked was blocked twice over. The control shipped as prose in a file
this same document elsewhere disclaims as "advisory context, never enforcement". Deny is now scoped
to the binary (`Bash(op-agent:*)`), which covers every verb including ones not yet written.

**Superseded in direction on 2026-08-18 (entry above), and only in direction.** Binary scope was
the right response *given a deny-list*, and the diagnosis here — that verb enumeration left the one
leaking command reachable — is still exactly right. What it missed is that the failure was
structural to deny-*listing*, not to enumeration: a deny-list fails open on the verb nobody listed.
Flipping to an allow-list keeps "every verb including ones not yet written" covered while restoring
the shapes that never printed anything. `Bash(op-agent:*)` itself did not loosen — the binary this
incident actually involved is still denied whole.

The generalisable lesson is not about 1Password: **when an incident postmortem produces a rule,
check that the rule landed in the layer that can enforce it.** A prose rule written in response to
an accidental leak does nothing about the deliberate case, which is strictly easier to trigger.

### The sandbox measured: egress works, and `credentials.files` would break op-agent (2026-08-18)

The sandbox had never been evaluated as a control. The word appeared exactly once across 83 KB of
`CLAUDE.md` + this file — at `CLAUDE.md:499`, explaining why a sandbox feature does *not* protect
something — and `settings.json` had no sandbox keys at all. Config knowledge topped out around
v2.1.208 while the client was on 2.1.234; `sandbox.filesystem.disabled` (2.1.216),
`network.strictAllowlist` (2.1.219) and credential masking (2.1.224) all landed in that gap.

Four measurements, using `security list-keychains` as the probe — same securityd Mach IPC as a
keychain read, no secret touched, and outside the `find-generic-password` deny:

1. **Egress enforcement is real.** With `strictAllowlist` and `allowedDomains: [api.github.com]`,
   a sandboxed Bash `curl` returned `200` for the allowlisted host and `000 / rc=56` (transport
   failure) for a non-allowlisted one. This is the thing `permissions.deny` structurally cannot
   do: deny matches command *spelling*, this blocks the destination.
2. **The sandbox does not break Claude's own auth**, even with the Anthropic API absent from the
   allowlist — the allowlist governs sandboxed commands, not the client's control-plane traffic.
   (An earlier "Not logged in" result was `--bare` stripping auth, caught by a control run. Worth
   recording as a near-miss: without the control it would have read as the sandbox breaking login.)
3. **The keychain survives the recommended config.** Sandbox on, network allowlisted, no
   `credentials.files` deny → `login.keychain-db` still in the search list, so `op-agent` works.
4. **`credentials.files: deny` breaks it.** With keychain file reads denied, `list-keychains`
   returns only `System.keychain` — `login.keychain-db` vanishes. `CLAUDE.md` claimed the resolve
   "survives" this because it goes through securityd rather than a file read. The premise is true
   and the conclusion is false: the file deny removes the keychain from scope before the IPC is
   reached. Corrected in place.

So the useful shape is **egress, not credential-at-rest**: blocking the keychain read is not the
goal — op-agent needs it — and the 2026-07-25 harm was a resolved credential *leaving the machine*,
which is exactly what an allowlist addresses and a deny list cannot.

Not enabled in the same change. What remains unmeasured is not whether it works but **what the
allowlist must contain** for this machine to keep functioning day to day (brew, mise, GitHub, npm,
1Password), and that is empirical over days rather than one run. `allowUnsandboxedCommands: false`
matters if it is adopted, or the retry path re-opens everything. Do **not** set
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` alongside it: it buys nothing here (the SA token is read inline
inside op-agent's own process and never enters the parent env) and it makes Claude Code ignore
`filesystem.disabled` from every source.

### What `permissions.deny` actually buys

It blocks the Bash path to secret resolution and raw credential files, and it survives `auto` and
bypass because deny is evaluated before everything else. But it is **defense-in-depth, not a
boundary** — `git push` authenticates with the same PAT, so an attacker who can run git can still
use the credential. Two further limits, measured 2026-08-05:

- Deny matches command **spelling**. An absolute path (`/opt/homebrew/bin/op …`) is not covered by
  `Bash(op:*)`, and nothing in the permission model can express "this binary however spelled".
- Everything unmatched falls through to the auto-mode classifier, which is **probabilistic**: two
  commands identical in binary, verb and shape, differing only in a vault name, were decided
  differently (one allowed, one denied). A control that decides identical shapes differently is a
  filter, not a floor.

Least privilege genuinely rests on the PAT's scopes and the SA-scoped vault, not on the deny list.
Stated plainly here so the deny list is never mistaken for a security boundary.

**It is nonetheless now tested.** Until 2026-08-05 the entire `deny` array could be deleted and
lefthook, CI and `boom verify` all stayed green — the "deterministic floor" had no regression test
at all, while the four cosmetic-by-comparison settings guardrails did. A floor with no test is not
a floor, so every secret-path entry is asserted in every enforcement point.

## Settings that cannot be removed

### `skipWorkflowUsageWarning` stays, and it is the exception to the divergences-only rule

It is undocumented, marked `@internal`, and absent from the published JSON schema, so by the usual
test it should go. But the app WRITES IT BACK when the warning is accepted, and `settings.json` is
tracked and symlinked into `~/.claude/`. `boomfile.toml` carries a `verify` step asserting
`dot-claude/` is clean, so removing the key buys one clean commit and then a permanently red
`boom verify` the next time the app rewrites it. A key you cannot keep out is not a key you can
delete.

## Settings removed deliberately

### `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` and `ENABLE_PROMPT_CACHING_1H=1` (removed 2026-07-25)

Both were inert. An 80% autocompact threshold on a 1M-token window is essentially never
reached, and the 1-hour prompt-cache TTL is requested by default on a subscription.

Two enumerated divergences that did nothing. Principle 2 says they go.

---

## Hooks

### v2.1.211 removed the classifier's default-branch backstop, silently (recorded 2026-08-18)

Not a decision — a change that happened *underneath* the setup and was never written down, which
makes it the more important kind of entry.

Claude Code's auto-mode docs, on common boundaries: *"Auto mode allows pushes to any branch of the
repository you're working in, including the default branch… Before v2.1.211, the classifier
allowed pushes only to your working branch, branches Claude created, and routine pushes to the
default branch."* And: *"Before v2.1.211, the context slots also included a Default / protected
branches entry that treated `main` and `master` as protected until you named others. v2.1.211
removed it."*

So `rebase-guard.sh`'s default-branch arm went from belt-and-braces to **sole enforcement**, in a
client update, with no signal. Everything still worked, which is exactly why it needed noticing:
the guard has been carrying that rule alone for some number of releases.

This is the strongest available argument for keeping that guard, and it had been sitting outside
the record. If a second layer is ever wanted back, `permissions.ask: ["Bash(git push *)"]` is the
documented mechanism — content-scoped ask rules are evaluated before the classifier and force a
prompt even in auto mode. Not adopted here: this machine pushes constantly and the prompt fatigue
would be the greater cost. Noted so the option is a choice rather than a rediscovery.

## UI

### `outputStyle: "Proactive"` was pinned because `/config` does not persist it (2026-08-19)

`/config` reported *"Set output style to Proactive"*, and the natural assumption — the same one the
`tui`/`theme` note above records as the normal path — was that the client had rewritten
`settings.json` and left the config-repo clone dirty for enumeration. **It had not.** Measured
straight after: `outputStyle` was in neither `dot-claude/settings.json` nor `~/.claude.json`, no
`~/.claude/output-styles/` directory existed, and *both* clones (`~/Code/DevEnv/dotFiles` and
boom's `~/.local/state/boom/config-repo`) reported a clean tree. The style was live in the running
session and nowhere else — it would have died with the session.

That is the whole reason this is a hand-written entry rather than a reconciliation. The UI section
above says the discipline for a self-rewriting file is "reconcile after the client edits, not
prevent it"; this is the **complementary** failure, where the client edits nothing and there is
nothing to reconcile, so a setting silently never persists. **Don't infer persistence from a
`/config` confirmation** — check the file, and check *which* clone the `~/.claude/settings.json`
symlink resolves into (it points at boom's state-dir clone, not the `~/Code` checkout, so a
`git status` in the obvious place answers the wrong question).

The value is a built-in style name, confirmed against the settings schema rather than guessed:
`outputStyle` is a plain string whose documented built-ins are `default`, `Proactive`,
`Explanatory`, `Learning`. Capitalisation is load-bearing and there is no validation at the file
level, so a typo degrades to "no style" silently.

On the substance: it is the behavioral counterpart to `defaultMode: auto` +
`skipAutoPermissionPrompt`. Those remove the per-tool-call human gate; this removes the
per-decision one. The accepted-risk-and-re-evaluate note on the permissions entry now covers a
strictly wider surface, and the two should be reconsidered together rather than separately. It
buys nothing enforcement-wise — the style's own prose about confirming destructive actions is a
prompt, not a control, and the real floor is unchanged: `permissions.deny`, the three `PreToolUse`
guards, and the no-direct-push-to-`main` rule.

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

### Stacks become the default shape, and the merge queue is declined (2026-08-04)

Stacks, because a queue serialises what a stack parallelises and this repo's PRs build on each
other. The merge queue is declined: `gh pr merge` calls the legacy endpoint and cannot merge a
stack at all, and enabling a queue before every layer is green hangs every PR permanently.

The mechanics — required checks, the aggregate job, `merge_group:` sequencing, why a per-path
required check strands a PR pending forever — are in the `agent-friendly-repo` skill, which is
where a procedure goes. They were duplicated here in full, including a claim the skill had since
withdrawn, and a strikethrough-plus-correction that this file's own rule forbids.

## Branch protection

### Classic protection — legacy fallback only

Rulesets are the mechanism; classic branch protection stays only as the fallback for a repo that
has none. The JSON payload for configuring either lives in the `agent-friendly-repo` skill with
the rest of the setup procedure, not here.

### Dependabot auto-merge: a workflow, because there is no switch (2026-08-03)

GitHub has no setting for "auto-merge Dependabot minor/patch", so it is a workflow. Two
properties matter and are asserted by the workflow itself: `on: pull_request` rather than
`pull_request_target` (which would run untrusted code with a writable token), and an explicit
minor/patch ALLOWLIST rather than `!= major`, so a metadata failure falls back to a manual PR
instead of merging something unreviewed. The step-by-step is in the `agent-friendly-repo` skill.

**Branch protection is the gate this rests on, and nothing in this repo asserts it exists.** If
the required check is ever dropped, `gh pr merge --auto` merges immediately.

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

### Why the Ninety PAT lives in the `claude-agent` vault

1Password service-account vault access is **immutable after creation** — you cannot grant an SA a
second vault. So the secret comes to the SA, not the reverse: agent secrets are copied into
`claude-agent` rather than the SA being granted access to wherever they already lived.
