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
  (Agent teams, experimental). `in-process` is currently also the *default*, so it is the one
  entry here kept deliberately as a **defensive pin** rather than a divergence: that default was
  `auto` before v2.1.179, and a silent flip back would start opening split panes. Agent view is left on (no `disableAgentView`) so `claude agents`,
  the `←` entry, `/background`, `claude --bg`, and `boom code claude` work with no idle fleet.
  **Re-evaluate with auto mode** — a standing fleet widens the confused-deputy surface;
  dispatch-on-demand keeps it minimal.
- **Permissions** — `defaultMode: auto` + `skipAutoPermissionPrompt` auto-approve tool calls: a
  productivity tradeoff that removes the per-call human gate. Accepted risk, **re-evaluate
  periodically.** `autoMode.classifyAllShell` routes *every* Bash/PowerShell command through the
  auto-mode classifier, not just arbitrary-code-exec patterns — the classifier still runs and can
  deny under `skipAutoPermissionPrompt`, which suppresses only the interactive prompt, not
  classification.
  - `autoMode.environment` / `allow` / `soft_deny` are the classifier's own prose-rule surface,
    and they exist here for the reason `DECISIONS.md` recorded and then left unfixed: *"two
    commands identical in binary, verb and shape, differing only in a vault name, were decided
    differently. A control that decides identical shapes differently is a filter, not a floor."*
    The docs name that exact cause — the classifier "trusts only the working directory and the
    current repo's configured remotes", and *"repeated denials for the same destination usually
    mean the classifier is missing context. Add that destination to `autoMode.environment`."*
    So `environment` names the orgs and cloud surfaces this machine legitimately touches, and
    `allow` the routine verify commands. Both make auto mode *smoother* — the classifier stops
    second-guessing destinations it should already trust. A custom `soft_deny` was deliberately
    NOT added: the built-in defaults already cover force push, `curl | bash`, production deploys
    and data exfiltration, and auto mode is valued here for not interrupting.
    **This improves the filter; it does not create a floor** — `permissions.deny` below is still
    the only deterministic layer. Every array leads with the literal `"$defaults"`, which is
    load-bearing: omitting it silently discards the built-in rules for that section, including
    force-push, `curl | bash`, production deploys and data exfiltration.
    User-scope only — `autoMode` is *ignored* in project `.claude/settings.json` and
    `settings.local.json`, so this cannot be pushed down into a repo that would rather own it.
  - `askUserQuestionTimeout: "10m"` — the default is *never*. With `defaultMode: auto`,
    background jobs and `/loop`, an unattended run that hits a dialog otherwise blocks forever
    with nobody there to answer it.
  - `permissions.deny` is the deterministic floor that survives `auto`/bypass (deny is evaluated
    first): keychain reads of the agent token (`security find-generic-password`), raw private-key
    and cloud-credential files, and the Bash path to secret resolution: `Bash(op read:*)`,
    `Bash(op item get:*)`, `Bash(op document get:*)`, `Bash(op-agent:*)`,
    `Bash(~/.local/bin/op-agent:*)`, `Bash(*/op *)`, `Bash(*/op-agent *)`,
    `Bash(git credential:*)`. Denying those breaks nothing — the `*_COMMAND` resolvers and `credential.helper` are exec'd by the MCP
    client and by git, and boom's `run` steps spawn `op-agent` as a child of boom, none of which
    go through the Bash tool.
  - **`op` itself is usable by agents again (changed 2026-08-18); `op-agent` is not.** The rule
    used to be `Bash(op:*)`, scoped to the whole binary, and the cost was not "one real cost" as
    this file claimed — it was everything. `op --version` was denied. So was
    `op run -- npm publish`, which is **1Password's own documented shape** and prints no secret at
    all: *"If a subprocess used with `op run` prints a secret to `stdout`, the secret will be
    concealed by default"* ([`op run` reference](https://www.1password.dev/cli/reference/commands/run)),
    with `--no-masking` as the opt-out. A control that blocks the vendor's recommended pattern is
    not a floor, it is an outage, and the advice it forced ("run it from your own terminal") took
    the agent out of the loop for the one task the vault exists to serve.
    - The deny entries are now the three `op` verbs that put a secret VALUE on stdout, and the
      *whole* `op-agent` binary. That split is deliberate: `op` is a tool an agent has legitimate
      non-printing uses for, while `op-agent` is plumbing — MCP resolvers and git exec it
      themselves, so nothing is lost by keeping it binary-scoped, and it is the one with a
      confirmed leak.
    - **`op-agent status` is NOT reachable, and this file claimed for a day that it was**
      (corrected 2026-08-19). The old sentence read "Only `op-agent status` (a verdict, no
      secret) is reachable, via the guard." Measured: **denied.** `Bash(op-agent:*)` is
      binary-scoped, `permissions.deny` is evaluated *first*, and `op-guard.sh` by design never
      emits `allow` — so the guard's allow-list entry for `status` can never be reached. The
      other statement in this file, *"it can subtract permission and never add it"*, is the
      correct one; these two were in direct contradiction.
    - **But the capability was never lost, and the first draft of this correction got the
      remedy wrong** (re-measured 2026-08-19). `op-agent status` is reachable through its
      *designed* consumer: `boom verify --only op-agent` runs it and prints
      `SA token in keychain` / `git PAT live`. Boom spawns `op-agent` as a child of the boom
      process, so it is not a Bash **tool** call — neither `permissions.deny` nor any
      `PreToolUse` hook is consulted. The same is true of `op-agent provision` on sync.
      **So do not narrow the deny.** An earlier revision of this file proposed narrowing it to
      the three printing verbs; that would weaken a security control to enable a shape nothing
      needs, and it would re-open the 2026-08-05 fail-open hole for every verb 1Password adds
      later. Binary scope stays.
    - What is actually true: **direct `op-agent` invocation from a Bash tool call is denied by
      design, and every real consumer reaches it another way** — boom `run` steps, git's
      `credential.helper`, and MCP `*_COMMAND`/`headersHelper` resolvers all exec the binary
      themselves. `boom verify` is the agent's supported path to a health check, and it works
      today.
  - **Why a verb list is safe NOW when it failed before** (this is the whole argument — do not
    re-broaden the rule without it). Enumerating verbs failed in 2026-08-05 because a **deny-list
    fails open**: the list blocked `op-agent secret`, `op read` and `op item get` but not
    `op-agent header` or `op-agent git-credential get`, both of which print a live credential to
    stdout. `op-agent header` is the command that leaked a PAT into a transcript on 2026-07-25
    (`DECISIONS.md`), so the one verb with a confirmed incident was the one left reachable, while
    `op-agent secret`, which never leaked, was blocked twice. `git credential fill` reached the
    same PAT with no `op` command at all.
    - What changed is not the diligence of the list, it is the **direction**. `op-guard.sh`
      (below) is an **allow-list**: it permits a named set of shapes proven not to print a value
      and denies everything else `op`-shaped. A forgotten verb, a verb 1Password ships next year,
      a destructive `op item delete`, and a typo now all fail the *same closed way*. The deny
      entries are no longer the control — they are the **residue that survives the guard being
      unreachable**, and they cover exactly the paths with a confirmed incident.
    - Read that pairing as load-bearing in both directions. `permissions.allow` carries
      `Bash(op run:*)`; without the guard in front of it, that pre-approves `--no-masking` and an
      env-dumping child. All three gates (`boomfile.toml`, `lefthook.yml`, `lint.yml`) assert the
      hook is wired for that reason. **Never add `Bash(op run:*)` to `allow` anywhere `op-guard.sh`
      is not also installed.**
  - **Matching is token-aware, not raw string prefix** — verified: `op readx` runs despite a
    `Bash(op read:*)` rule, because `readx` is a different token than `read`. Two consequences,
    and they pull opposite ways. Good: `Bash(op:*)` matches the `op` binary only and does **not**
    catch `open`. Bad: it does not catch a *differently spelled path* to the same binary either,
    which is why `~/.local/bin/op-agent` is enumerated separately — that is the spelling this very
    file uses in its `*_COMMAND` values, so it is the one most likely to be copied.
    **Correction (2026-08-18): absolute paths ARE coverable, and are now covered.** Wildcards may
    appear at any position in a rule, so `Bash(*/op *)` and `Bash(*/op-agent *)` match any path
    spelling of those binaries; both are in the array. Measured with a control rather than read
    off the docs — `deny Bash(*/touch *)` blocks `/usr/bin/touch`, while a negative control
    (`Bash(*/zzznotacommand *)`) does not, which is what proves the deny came from the rule and
    not from ambient policy. The honest residue is narrower than the old claim: deny cannot cover
    an arbitrary *interpreter* — `sh -c 'op read …'` still walks past — which is an argument for
    the sandbox, not for spelling more rules.
    **That residue is now closed for `op` specifically (2026-08-18)**, not by spelling more rules
    but by moving the decision into a hook that tokenizes: `op-guard.sh` takes a basename (so
    every path spelling resolves) and scans an interpreter's payload for an `op` subcommand (so
    `sh -c 'op read …'`, `bash -c "op item get …"` and `xargs op read` are denied). Both are
    regression cases. It remains true for everything else deny covers, and it remains an argument
    for the sandbox — `sh -c 'security find-generic-password …'` is still unspelled.
  - The floor has a **regression check** in all three enforcement points (`boomfile.toml`,
    `lefthook.yml`, `lint.yml`). Before that it had none: the whole `deny` array could be deleted
    and every gate stayed green. All three now assert **array membership** via
    `jq -e --arg d … '.permissions.deny | index($d)'` — a `[[section.check]]`/`grep` matches file
    *content*, so moving an entry from `deny` into `allow` inverted the control while every gate
    stayed green, and `--arg` passes each value as data rather than as a pattern (which is what
    the old regex-escaping was working around). Each also asserts `op-guard.sh` is wired, since
    `permissions.allow` pre-approves `Bash(op run:*)` on the strength of that guard.
  - Be honest about what that buys: **defense-in-depth, not a boundary.** `git push` still
    authenticates with the same PAT; deny matches command *spelling*, so an unspelled path or
    interpreter slips it — though for `op` specifically both are now covered, the first by the
    `Bash(*/op *)` wildcards and the second by `op-guard.sh`'s tokenizer, which is why the
    stale "nothing in the permission model can cover it" was struck here on 2026-08-18: the
    correction two bullets up had measured the opposite and this sentence was never updated to
    match. It remains true for the rest of the array;
    and everything unmatched falls to the auto-mode classifier, which is probabilistic and was
    observed deciding two identically-shaped commands differently. Least privilege rests on the
    PAT's scopes and the SA-scoped vault (see *Agent secret access*).
- **Models** — no `model` or `advisorModel` pinned: sessions use Claude Code's built-in default
  and run no server-side advisor. Fable/Opus/Sonnet stay freely selectable per-session (`/model`)
  and per-subagent. **Fable must never be pinned as the default** — a drift check fails if it is
  (e.g. via `/model`'s "set as default", which rewrites this file).
- **MCP (user scope)** — exactly one entry in `~/.claude.json` `.mcpServers`: **`1password`** →
  `/Applications/1Password.app/Contents/MacOS/1password-mcp` (added 2026-08-18). A stdio server
  shipped inside the desktop app; **no token, no `op://` ref, no `headersHelper`** — the only
  server here whose config contains no secret, because it structurally cannot return one
  (*"The server cannot return secret values stored in 1Password to the client, even if an agent
  requests them"*). It manages **Environments**, not vaults, so it replaces nothing `op-agent`
  does. Measured before adopting: it reports `✔ Connected` unattended (the approval gate is at
  tool-call time, per Environment), so it does **not** trip the `claude mcp list | grep ✘` check
  on the nightly `boom verify`; but a tool call really does block on a desktop prompt, so build
  nothing unattended on it. Beta, zero consumers today — on the same "earn its place by use"
  clock as the plugins below, and it should move to a specific repo's checked-in
  `.claude/settings.json` once one project owns an Environment. Rationale in the repo-root
  `CLAUDE.md`; registration is reproduced by a boomfile `sync` step and asserted by a `verify`
  step, since `~/.claude.json` is tracked by nothing.
- **Plugins** — `enabledPlugins` runs **one** marketplace, at `autoUpdate: false` (changed
  2026-08-05): with `autoUpdate` on, a merge to the upstream's main was unattended code
  execution here — new skills, new MCP servers, arbitrary code from a marketplace — reaching a
  session that runs `defaultMode: auto` with credentials available. The cost is updating by hand;
  that is the trade, and it is the same argument the *Standing threats* section already makes for
  keeping the plugin surface minimal.
  - `extraKnownMarketplaces.gnar` → `TheGnarCo/agent-skills`: `ignite`, `gninety`; plus
    `typescript-lsp`, `commit-commands`, `frontend-design` from `claude-plugins-official`. No
    "must-install" set exists — each entry earns its place by use (`ideate`/`toolkit` deliberately
    off). `ignite` is greenfield-kickoff and therefore **cannot** be narrowed to a project by
    nature; it is user-scoped or nothing.
  - **User scope is the exception, not the default** (audited 2026-08-06). A user-scoped plugin
    injects its skill list into *every* session, including repos it can never serve, so anything
    that belongs to one project is declared in **that repo's checked-in
    `.claude/settings.json`** — which also carries the marketplace, so no user-level
    `extraKnownMarketplaces` entry is needed. `BinfiniteLLC/BinfiniteApp` is the worked example:
    it declares `expo@expo-plugins`, `binfinite-context@binfinite`, `stripe`, `convex`, `posthog`
    and both marketplaces itself. **Measure before keeping**: count real invocations
    (`"skill": "<name>:` and `"name":"mcp__plugin_<name>` in `~/.claude/projects/**/*.jsonl`), not
    bare name matches — a user-scoped plugin's own prompt injection makes it look ubiquitous.
  - Four user-scoped plugins were dropped on 2026-08-06 after that audit (`audit@gnar`, `expo@claude-plugins-official`, `binfinite-context@binfinite`, `spacebase@gnar`) — the per-plugin reasoning, and the one "don't re-add it here" caveat, are in `DECISIONS.md`.
- **UI / QoL** — custom `statusLine` + `subagentStatusLine` (`~/.local/bin/claude-*statusline`,
  from [`TheGnarCo/claude-statusline`](https://github.com/TheGnarCo/claude-statusline));
  `editorMode: vim` with `vimInsertModeRemaps: {"jj": "<Esc>"}` (`"<Esc>"` is the only supported
  target, added in 2.1.208); `verbose: true`; quieter UI (`showTurnDuration` and
  `terminalProgressBarEnabled` off); `tui: "fullscreen"` +
  `theme: "auto"`; `skipWorkflowUsageWarning`; `inputNeededNotifEnabled` + the
  `attribution.commit` trailer.
- **Voice** — `voice: { enabled: true, mode: "hold" }` (push-to-talk). `voiceEnabled` was set
  alongside it and is gone: the settings schema calls it a *"Legacy alias for voice.enabled;
  prefer the voice object"*, so the pair was one setting written twice.
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
- **op guard** — `PreToolUse` hook (matcher `Bash` → `~/.claude/hooks/op-guard.sh`, ordered
  **first**, ahead of both workflow guards because it is the only one enforcing a security
  boundary rather than an ergonomic one). It is what makes `op` usable by agents: an **allow-list**
  of shapes that provably do not put a secret value on stdout — `op run [--env-file=F] -- CMD`,
  `op inject -i TPL -o OUT`, `op whoami`, `op --version`, `op service-account ratelimit`, and
  `op-agent status`. Everything else `op`-shaped is denied by default. **The `op-agent status`
  entry is unreachable in practice** — `permissions.deny` carries binary-scoped
  `Bash(op-agent:*)` and is evaluated before any hook, so that shape is denied before this guard
  is consulted. That is deliberate and is not being changed: run `boom verify --only op-agent`
  instead, which reaches `op-agent status` as a boom child process rather than a Bash tool call.
  The entry stays so the allow-list remains internally correct; do not read its presence as
  evidence the bare command works.
  - **`op vault list` / `op item list` are deliberately NOT on it**, though they print no secret
    value. This file records separately that `op vault list` "enumerates every vault in the
    account (verified 2026-08-05, no prompt)" through the desktop integration, far outside
    `claude-agent`. They were denied before this change and stay denied: the change is scoped to
    *using* a secret without reading it, and inventory browsing is a different capability that
    nobody asked for. An allow-list is where scope creep is cheapest to add and hardest to see.
  - The specific denials worth knowing, each a regression case: `--no-masking` (the flag that
    removes the property making `op run` safe); `op run` with no `--` (the guard will not guess
    which words are the child); an env-dumping child (`env`, `printenv`, `set`) or an interpreter
    child; bare `op inject` (renders the template **to stdout**, secrets and all); and
    `op run -- git push` / `-- gh pr create`, which would otherwise hide the push from
    rebase-guard, since that guard tokenizes for a `git` *program* and sees `op` here. That last
    one is a hole this change would have opened had it not been closed in the same commit.
  - **`op run -- op …` was the same hole, and it stayed open for a day** (found and closed
    2026-08-19). The child list blocked interpreters, env-dumpers and `git`/`gh` — but not `op`
    or `op-agent` themselves, so `op run` was a **trampoline back into the very binary this guard
    exists to gate**. Measured, all three allowed before the fix:
    `op run -- op read op://…`, `op run -- op-agent secret op://…`, `op run -- op item edit`.
    - It defeated **both** layers at once. The guard saw an unremarkable child program and
      allowed it; `permissions.deny` never matched because every rule there anchors on `op read`
      / `op item get` / `op-agent` as the **first token**, and here the first token is `op run`.
      And `permissions.allow` carries `Bash(op run:*)`, so the shape was not merely permitted, it
      was *pre-approved*.
    - **Masking does not rescue it**, which is the part worth remembering: `op run` conceals
      values it *injected* into the child's environment, and a child that reads a secret itself
      injected nothing — there is no value to match, so the credential lands on stdout. That is
      the 2026-07-25 leak reached by a different road.
    - The lesson generalises past `op`: the `git`/`gh` entry existed because `op run --` can
      launder a command past *another* guard. Nobody applied it to *this* guard. **When adding a
      child to the allow path, ask what guard the child would bypass — including this one.**
      Ten regression cases cover it, with `op run -- npm publish` and `-- node build.js` as
      controls so the fix cannot become an outage.
  - **Known residue, deliberately not closed:** `op inject -i TPL -o FILE` is on the allow-list
    and writes *resolved secrets to a file*, which an ordinary `cat` then reads into context. The
    guard denies **bare** `op inject` precisely because it renders to stdout — but `-o FILE`
    plus a read reaches the same place in two steps, so that distinction is thinner than it
    looks. It is left allowed because `op inject` is a legitimate rendering shape and closing it
    means gating arbitrary file reads, which the permission model does not do today (only
    `Read(~/.ssh/id_*)` and `Read(~/.aws/credentials)` are denied). **Do not cite `op inject` as
    proof secrets cannot reach context** — it is an accepted gap, not a covered one.
  - **It never emits `permissionDecision: "allow"`.** A hook `allow` bypasses the permission
    system entirely, which would put the guard *above* `permissions.deny`. It only denies or stays
    silent, so it can subtract permission and never add it, and the deny floor still applies
    underneath. The two compose instead of racing.
  - Fails **open** on missing `jq`/`guard-lib.sh`, like its siblings — defensible here only
    because the residual deny entries still cover the confirmed-incident paths, so fail-open
    degrades to roughly the old floor minus binary scope on `op`, not to nothing. The link is
    declared in the boomfile so an absent guard is drift `boom verify` reports.
- **Worktree-checkout guard** — `PreToolUse` hook (matcher `Bash` →
  `~/.claude/hooks/worktree-checkout-guard.sh`, ordered after op-guard and *before* rebase-guard). Denies a
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
  - **All three guards share one regression suite** (`dot-claude/hooks/tests/`, wired into
    `lint.yml` and pre-commit): 127 hermetic cases against throwaway git fixtures, ~6s wall.
    **Add a case before changing a guard.** The 2026-08-08 audit is why the count
    doubled: the suite had grown from two past incidents, so it tested *the fixes* rather than
    *the rule*, and 26 new cases — every one of them a reproduction through this same harness —
    failed on the guards as shipped. `git push origin HEAD` was the highest-value miss. The 53
    `op` cases arrived with op-guard on 2026-08-18, written *before* the deny list was relaxed —
    the point of the suite is that widening a control is only safe when the narrowing is measured.
    Run a **negative control** when a new block passes first try: inverting two expectations
    (`op read` → allow, `op run -- npm publish` → deny) must produce exactly two failures, which
    is what proves the harness discriminates rather than defaulting to `allow`.
  - **All three guards share `guard-lib.sh`** (quote-aware command splitting, token
    normalization), sourced as `$(dirname "$0")/guard-lib.sh`. They each carried their own copy
    until 2026-08-08 and had already drifted three ways, so a fix landed in one and not the other.
    It is **load-bearing**: if that file is missing all three fail open, which is why it has its
    own boomfile link beside theirs.
- **Recorded PR review (`PostToolUse`)** — `~/.claude/hooks/pr-review.sh` fires after
  `gh pr create` / `git push` / **`gh stack submit`**; when the repo is in `PR_REVIEW_REPOS` (a bare **owner**, covering
  every repo under it, or a fully-qualified `owner/repo`; defaults to `TheGnarCo BinfiniteLLC
  SalvageUnion-io RANDSUM alxjrvs`) it runs the adversarial review locally and posts it as a real
  PR review — **and nothing else. There is no commit status, so it never appears as a check**
  (removed 2026-08-17). It was required by no ruleset in any repo, and an advisory check that can
  never fail a merge costs attention without buying enforcement: one permanently-irrelevant entry
  teaches people to skim the whole checks list. It backgrounds itself immediately so it can
  never block a turn, and **every failure path posts a short "did not complete … this is not a
  verdict" comment** rather than exiting silently — the whole block is `> /dev/null 2>&1 &`, so
  without that a dead reviewer would be indistinguishable from a clean one. `if` is a field on an individual
  hook handler, never on the matcher group — one rule per handler, so three commands means three
  handlers. The `gh stack submit` arm exists because that command matches *neither* of the other
  two — it creates PRs via the Stacks API and pushes inside the gh process, so no `git push` Bash
  call ever reaches PostToolUse — which meant stacking silently routed the largest changes around
  the reviewer. It reviews the **checked-out layer only**, not the whole stack, so a review on one
  layer is not a verdict on the others. **Advisory until a day-30 finding rate justifies
  promoting it: above ~1 finding per 10 PRs that changed code, keep and consider requiring; below,
  delete it and close the question.** That clock restarts 2026-08-08, because until then the
  numerator was a lie: the count came from `grep -ciE '^[-*] **(blocking|critical)'` over review
  prose, the reviewer writes ``- `file:line` — description``, and so all 15 reviews on this repo
  reported "no blocking findings" while carrying real ones — 9 on #111 alone, several of which
  this audit then re-found independently. The count now comes from a machine-readable trailer the
  reviewer must emit, and an empty or unparseable body posts a not-a-verdict comment instead of a
  clean bill of health. **Do not judge this hook on pre-2026-08-08 data.** Dropping the status did
  not cost the numerator: the trailer is still parsed and now leads the review body, so findings
  stay countable by reading reviews.
  - **The reviewer is confined by `permissions.deny`, not by `--allowedTools`** (corrected
    2026-08-08). It reads attacker-controlled text — a diff, a README, a fixture, from any
    contributor to a `PR_REVIEW_REPOS` repo — while running detached under the *user-scope*
    `settings.json`, so it inherits `defaultMode: auto` + `skipAutoPermissionPrompt`, and it
    publishes its output to GitHub. With a shell that is a complete exfil path, and because the
    block is `> /dev/null 2>&1 &` none of it appears in the parent transcript.
    - This file claimed for two days that `--allowedTools` closed that. **It does not.** It is an
      additive pre-approval list, not a ceiling: anything unlisted falls through to the auto-mode
      classifier. Measured with the exact flag string the hook shipped — `printf AUDITPROBE-OK`,
      listed nowhere — and it ran. `--permission-mode plan` did not stop it either.
    - What does: a bare tool name in `permissions.deny`, via `--settings
      ~/.claude/hooks/pr-review-settings.json`. Deny is evaluated first, survives `auto`, and
      removes the tool from the model's context entirely — same probe, and the reviewer reports it
      has no shell tool and refuses to fabricate output.
    - Because Bash is denied, the reviewer cannot fetch its own diff, so the hook hands it one.
      That is better on a second axis: `gh pr diff <pr>` is the PR's diff against **its own base**,
      where the old `/code-review` invocation got no base and resolved `main...HEAD` — so every
      stacked layer re-reviewed every layer beneath it.
    - **Re-run the probe if either file changes.** The last comment here was an argument, not a
      measurement, and it was wrong.
  - **`pr-review.sh` is not covered by the regression suite.** That harness asserts on a
    `PreToolUse` `permissionDecision`, which a `PostToolUse` hook never emits, and testing this one
    would need `gh`/`claude` stubs on `PATH`. `lefthook.yml`'s `guard-tests` globs
    `dot-claude/hooks/*.sh`, so editing this file *runs* the suite without *testing* it — don't
    read a green run as coverage. The "add a case before changing a guard" rule is scoped to the
    two guards.
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

- **Never post an issue to a foreign repository without express permission.** Foreign means
  anything outside `alxjrvs/*` and the orgs this machine works in (`TheGnarCo`, `BinfiniteLLC`,
  `SalvageUnion-io`, `RANDSUM`) — i.e. an upstream, a dependency, a repo hit while debugging.
  Filing there is outward-facing publishing under alxjrvs's name and is not covered by any
  standing authorization: draft the body, show it, wait for a yes. Same for every other write to
  a foreign repo — PR, comment, review. This is prose, not a permission rule; `gh` is not denied.
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
  - Stack state lives in `.git/worktrees/<name>/gh-stack` for a linked worktree — untracked and
    **per worktree, not per clone**, so two worktrees of one clone share none of it and a fresh
    agent worktree inherits nothing. `gh stack checkout <stack#|pr#|url|branch>` re-attaches. Run
    `gh stack view` before shipping: a branch that is stacked on GitHub can look unstacked locally.
    Two further gotchas, both measured on 2026-08-15: `gh stack init` **requires** a branch
    argument (the bare form dies on "interactive input required", which strands an unattended
    agent), and it anchors the trunk to the **local** `main` ref rather than `origin/main` — so on
    a machine where nobody checks out `main`, the persisted `trunk.head` can sit tens of commits
    behind. `gh stack sync` cannot advance it either (git refuses to force-update a branch checked
    out in another worktree, which it reports as a `fatal:` nested inside a warning on an
    otherwise successful command). **Do not read `trunk.head` as truth, and do not "fix" that
    warning** by removing the worktree or forcing the local ref — the tool falls back to
    `origin/main`, which is the ref you wanted, and exits 0.
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

- **Scope = one vault — by our choice, not by platform limit** (clarified 2026-08-19). The
  service account can read only the dedicated `claude-agent` vault. Two of the three constraints
  here are real, one was our own framing:
  - **Real:** 1Password forbids granting an SA access to Personal/Private/Employee **or your
    default Shared vault**, and an SA's vault and Environment access is **immutable after
    creation** — *"If you want to grant a service account access to additional vaults or
    Environments … you'll need to create a new service account."*
  - **Not a limit:** an SA **can** be granted **multiple vaults at creation**. This file used to
    read as though one-vault were imposed by 1Password; it is not. It is a good default (it is
    1Password's own "dedicated vault, permissioned for the task at hand"), but it means the right
    response to a second concern is **a second SA + vault pair**, not piling unrelated items into
    `claude-agent`.
  - Consequence for hygiene: because access is immutable, a vault cannot be narrowed later — only
    replaced. So **the vault's contents are the only lever you have**, and every item in it that
    no live consumer resolves is standing exposure bought for nothing. Audit membership, not just
    permissions.
  - It is **not** the blast radius of *the agent*, and the difference matters. The agent runs as
    you, on your machine, so your desktop `op` integration is reachable from an ordinary Bash tool
    call: `op vault list` enumerates every vault in the account (verified 2026-08-05, no prompt,
    while `op whoami` reported "not signed in" — the CLI *session* is signed out; the desktop
    integration answered). Item reads outside `claude-agent` do raise an approval prompt, so an
    unattended job cannot satisfy one; the exposure is an *attended* session where a prompt is
    approved reflexively. The gate's scope was not characterized — desktop integration typically
    authorizes per-session, not per-item — so treat it as zero-to-one approvals, not one per read.
    `op-guard.sh` is what removes the Bash path to this: `op vault list` is not on its allow-list,
    so it is denied by default. (Until 2026-08-18 the binary-scoped `Bash(op:*)` did this job;
    when that rule was narrowed so agents could use `op run`, enumeration was deliberately left
    denied rather than allowed to ride along.)
- **Token lives in the macOS login keychain** (`security … -s op-claude-agent`), never on disk in
  plaintext, never in git. `boom source` runs `op-agent provision`, which creates the vault +
  service account and stores the token on first run, with `--expires-in` (90d default).
- **The SA token never enters the model's context.** It is read from keychain *inline* inside the
  `op-agent` CLI, confined to that one `op` process — so the SA token itself reaches neither a Bash
  subprocess, the transcript, nor OTEL tool spans.
  - **Resolved secrets are a different story, and the deny list is what covers them.** `op-agent`
    prints its results to stdout by design — that is how a resolver returns a value — so `header`
    and `git-credential get` each emit a live credential, and Bash stdout *is* model context.
    Nothing structural prevents that; `Bash(op-agent:*)` does. `op-agent` is one verb-dispatched
    script: `secret` / `header` / `git-credential` / `provision` / `status`.
  - "No wrapper, no exported env var" holds for Claude Code, not everywhere: `gh-mcp-stdio` does
    `export GITHUB_PERSONAL_ACCESS_TOKEN` into a long-lived server process, because Claude Desktop
    supports neither `headersHelper` nor a `*_COMMAND` resolver. It is the best available there and
    still beats a literal PAT in `claude_desktop_config.json` — just don't read the general claim
    as covering it.
- **Zero measured calls on an MCP server means "broken or unused", and the two are
  indistinguishable from usage data alone.** Check `claude mcp list` before concluding either;
  `boom verify` fails when a server reports `✘` or `! Needs authentication` — but it only
  sees servers visible from its CWD, and the launchd job sets none, so the project-scoped
  `github`/`render` servers are invisible to it.
- **MCP secrets follow one canonical pattern.** For servers we install:
  `op run --env-file=.env -- <server>` (`boom mcp add`) with `op://` references in a committable
  `.env`, resolved in-process and off disk. **This is 1Password's own published recommendation for
  MCP servers** (their Nov 2025 guidance prescribes exactly it), so it is vendor-endorsed rather
  than invented here — but note **it currently has zero instances in this repo**: every live
  consumer is one of the native-hook paths below, which the framing calls the exception. Treat it
  as the pattern for the next server we install, not as a description of what runs today.
  Surfaces we don't control use the tool's own native hook fed by `op` — plugin-bundled stdio
  servers via a `*_COMMAND` resolver var; the GitHub MCP
  (an `http` server at `api.githubcopilot.com/mcp/`) via
  Claude Code's `headersHelper` → `op-agent header op://…`. That server is **project-scoped** to
  `~/Code/SU-SRD` in `~/.claude.json`, not user-scoped — so outside that directory, including this
  repo, there is no GitHub MCP. A second `headersHelper` consumer lives beside it, the **`render`**
  server on `op://claude-agent/render-api-key/credential`. **Neither is declared in the boomfile**,
  so a fresh machine reproduces neither, and `boom verify`'s `claude mcp list | grep ✘` check
  cannot see an *absent* server — only a configured-and-failing one. Claude Desktop supports neither, so
  it runs a *local* stdio `github-mcp-server` via `~/.local/bin/gh-mcp-stdio`, which resolves the
  same vault item in-process — never an `env` block with a literal PAT. A resolved secret never
  enters git, and never write a `${VAR}` into a git-tracked `.mcp.json` (`claude mcp add` can
  expand it back into the tracked file).
- **Agent git auth resolves the PAT through `op`, like every other secret.** A **classic**
  `repo`+`workflow` PAT (SSO-authorized for the orgs it pushes to), stored in the `claude-agent`
  vault. Classic, not fine-grained — but **the stated reason was wrong (corrected 2026-08-18)**.
  It read: "fine-grained PATs need org-owner enablement and approval you don't have for those
  orgs." Both halves are off. GitHub: "By default, both Personal access tokens (classic) and
  fine-grained personal access tokens are enabled", and "fine-grained personal access tokens
  created by organization owners will not need approval" — while personal repos (`alxjrvs/*`,
  where dotFiles and boom live) need no approval at all. So the classic PAT is a *status quo*,
  not a necessity, and least privilege currently rests on the SA-scoped vault + token expiry
  rather than on per-repo scoping because nothing has narrowed it, not because nothing could.
  - **This is the unresolved half of the `workflow`-scope note below.** That note says to drop
    `workflow` "unless something actually needs it" — something does (the agent edits
    `.github/workflows` in this very repo), so dropping is unavailable and it was left alone.
    *Scoping* is available even though dropping isn't: fine-grained PATs carry a **per-repo**
    Workflows permission, replacing an account-wide grant that today spans every repo the agent
    can push to. Deliberately not migrated in the same change — that is a credential rotation
    across every repo the agent touches, and wants its own window. Git's `credential.helper` points at
  `op-agent git-credential`, so the PAT is stored only in 1Password — no keychain cache, no second
  mechanism. ~~Because the resolve path is `securityd` + network rather than a keychain *file*
  read, it survives a sandbox `credentials.files` deny.~~ **Measured false, 2026-08-18 — it does
  not survive, and this is the one sandbox setting to keep OFF.** Under a Seatbelt profile denying
  reads of the keychain files, `security list-keychains` returns only
  `/Library/Keychains/System.keychain`: `~/Library/Keychains/login.keychain-db`, where
  `op-claude-agent` lives, **drops out of the search list entirely**, and an item lookup cannot
  succeed against a keychain that is not in the search list. The reasoning was sound — the resolve
  really does go through securityd — but the file deny takes the keychain out of scope before the
  IPC is reached. Rotating the PAT is just updating the
  vault item (rotating the **SA token** is not — that is web-UI only, see below).
  - **"Lives only in 1Password" is about storage, not residency.** `credential.helper` is fronted
    by git's `cache --timeout=900`, so for 15 minutes after any agent git operation the plaintext
    PAT is held in `git-credential-cache--daemon`'s memory behind a socket in `~/.cache/git`. The
    socket dir is `0700` so it is not a cross-user hole, but any *same-user* process — which the
    agent is — can read it back with `git credential fill`, reaching the PAT with no `op` command
    at all. `Bash(git credential:*)` in `permissions.deny` narrows that path but — **correction
    (2026-08-18)** — does not *close* it, which is what this used to claim. Two ways past it,
    neither matching the rule: `git credential-cache exit` is a different token (the same
    word-boundary mechanism this file already documents for `op readx`), and the cache is a plain
    Unix socket, so any same-user process can speak the helper protocol straight to it with
    `nc -U` and no `git` token in the command line at all. Defense-in-depth, like the rest of the
    array; the thing that would actually close it is egress control, not spelling. The cache is
    still worth keeping: 1Password's daily rate limit is **per account** (1,000 combined reads on
    Individual/Family), so it is doing quota work, not just latency work.
  - **`repo` + `workflow` is the scope to keep an eye on.** `workflow` permits writing
    `.github/workflows/*`, and a merged workflow runs with that repo's `secrets.*` and its OIDC
    identity — so repo write converts to the org's CI secret set. Combined with no required human
    review (necessary, since agents can't approve their own PRs) and `gh pr merge` in
    `permissions.allow`, that loop closes with no human in it. Drop `workflow` unless something
    actually needs it.
- **SA token rotation is web-UI only, and unscriptable.** `op service-account` has exactly two
  subcommands — `create` and `ratelimit` — and nothing has been added in over two years. Rotate at
  1Password.com → Service accounts → Token → Rotate Token, which issues a new token, keeps the same
  permissions, and lets you expire the old one Now / 1 hour / 3 days. It does **not** let you add an
  expiry to an existing token, so an open-ended SA can only gain one by being replaced. None of this
  can be a boom step or a cron job; `op-agent status` warns ahead of time precisely because the fix
  is manual.
- **There may be no audit trail at all — check the plan tier.** The audit log, usage reports, and
  the Events API are **1Password Business** features. On Individual/Family a service account's
  `op read` leaves *no retrievable per-item, per-timestamp record*; the only signal is an aggregate
  counter via `op service-account ratelimit`. So if this account is personal, "auditability" is not
  part of the security story here and scope + expiry are the whole of it. Don't cite 1Password's
  marketing claim about Activity Log visibility without checking which tier it applies to.
- **Docs moved**: `developer.1password.com/docs/*` now redirects to `www.1password.dev/*`. Old
  links still resolve but are no longer canonical.
- **Your own dev work** still uses desktop biometric + `op run`/`op://`/Environments — the
  service account is the agent's path, not yours. **An in-session Claude can now run
  `op run -- npm publish` for you** (changed 2026-08-18) — it is on `op-guard.sh`'s allow-list and
  pre-approved in `permissions.allow`, because `op run` injects into the child's environment and
  masks any secret the child prints. It still cannot `op read` the token, which is the point.
