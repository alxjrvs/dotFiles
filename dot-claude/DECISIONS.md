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

### Why the guards have a regression suite

`dot-claude/hooks/tests/` — cases against throwaway git fixtures in `$TMPDIR`; hermetic, no
network, seconds. Every case came from a real transcript or a reproduction, and the suite is
written so that a meaningful subset fails against the pre-fix guards — which is what makes a green
run evidence rather than decoration. `cases.tsv` is the count; this file is not.

200+ lines of load-bearing, security-relevant shell had no tests, which is exactly how the
`--dry-run` hole shipped and survived. Add a case before changing a guard.

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

Owner's call, and it reverses the conclusion of the entry above. That entry argued the queue
"stopped being optional" because `--auto` cannot land a stack and `gh stack merge` doesn't wait
for green — so without a queue there was no fire-and-forget path. The facts are unchanged; the
**decision** is that fire-and-forget was never worth its price here.

What the queue actually costs on these repos:

- ~~**It is mutually exclusive with Dependabot auto-merge.** `GITHUB_TOKEN` cannot add a PR to a
  merge queue, so enabling one silently breaks the workflow adopted in #97.~~
  **Withdrawn 2026-08-18 — unsupported, and it was the leg this entry led with.** No GitHub doc
  carves `GITHUB_TOKEN` out of enqueueing; the merge-queue docs say plainly that `gh pr merge`
  "automatically adds the pull request to the queue if required checks have passed". The one
  primary source found reports the *inverse* and is still open — [cli/cli#8352](https://github.com/cli/cli/issues/8352):
  "running the same command in Github Actions with a `GITHUB_TOKEN`, the command succeeds as
  expected and the PR gets added to the merge queue" — it is the **PAT** that fails there. The
  likely origin of the belief is a different mechanism entirely: a `GITHUB_TOKEN` *push* does not
  re-trigger workflows, so automerge stalls. Same error shape this file already catalogues for
  `gh stack unstack`: inferring a capability from adjacent behavior instead of reading the
  feature's contract.
  **The decision does not change** — the two legs below are untouched and still carry it. But it
  now rests on two verified reasons rather than three, one of which was wrong.
- **It carries the `merge_group:` sequencing hazard.** Enable it before CI reports on the queue's
  temp branches and every PR hangs forever. That is a real foot-gun standing between the repo and
  a merge, permanently, in exchange for convenience on multi-layer changes.
- **It weakens the guarantee stacks exist for.** Behind a queue a stack may be split across
  consecutive merge groups, so the all-or-nothing property degrades to per-group.

What "no queue" costs instead: the agent has to watch every layer to green before running
`gh stack merge`. The earlier entry called that "a babysitting loop, not a completion path" —
that framing was wrong, or at least overstated. `gh pr checks --watch` is a supported, bounded
wait; the loop only becomes pathological if `main` moves faster than the stack can settle, which
is a two-repo-contributor problem this repo does not have. The rule is therefore: sync, retry
once, then report — never loop indefinitely.

So the doctrine now reads: **stacks are the default shape for multi-part work; they land by
watching green and merging directly; no queue.** `agent-friendly-repo` still knows how to build a
queue, gated behind an explicit ask *and* a repo with no Dependabot auto-merge to lose.

The other half of "lean in" is the part tooling can't do: **deciding the layers before writing
the code.** Once work is one large commit, splitting it is archaeology, so `CLAUDE.md` now carries
the decomposition test — a layer is something that could be reviewed and reverted on its own
(an enabling refactor, a schema change ahead of its consumers, a mechanical rename, docs) and
explicitly *not* a split by file, by commit count, or to hit a size target. With the honest
counterweight attached: don't stack a single reviewable change, and don't manufacture layers to
satisfy the rule. A one-layer stack is a PR with extra ceremony.

Worth recording as evidence rather than principle: this doctrine was written across PRs #102 and
#103, which were *themselves* stack-shaped — #103 built directly on #102's conclusions — and were
shipped serially anyway, each waiting for the other to merge. The tooling wasn't live yet, which
is a reason but not a good one. It is the clearest available measure of the gap between having
the preference written down and actually reaching for it.

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

### Why the Ninety PAT lives in the `claude-agent` vault

1Password service-account vault access is **immutable after creation** — you cannot grant an SA a
second vault. So the secret comes to the SA, not the reverse: agent secrets are copied into
`claude-agent` rather than the SA being granted access to wherever they already lived.
