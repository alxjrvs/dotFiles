# The butter stack — the shape itself

Reference for the `butter-stack` skill. Split out of SKILL.md because this is an
INVENTORY, not a procedure: the skill body is what you do, this is what the stack
is. A skill's body loads in full whenever the skill triggers, so keeping a
~14 KB table in it charged every scaffold and every audit for a description of
layers most invocations never touch.

Read this when the procedure in SKILL.md tells you to, or when you need to know
what the stack actually specifies.

## The invariants

**Two tiers, and the difference matters when auditing.**

- **Unanimous (4/4)** — Bun, the workspace shape, the internal graph, *having* a shared base tsconfig, and the CI gate. A deviation here is a finding. Note the tsconfig entry covers the file and the core flag set only: the three flags marked *(standard)* inside that block keep the weaker status — do not inherit unanimous-tier severity for them from the section heading.
- **Standard (not yet universal)** — Biome, Lefthook, knip, catalogs, `.bun-version`, `bun run check`. Adoption is uneven and moves. **Check the repo rather than trusting this list** — it was already wrong once, claiming optfall lacked Biome after Biome had landed there. A deviation is a finding unless an open issue already tracks it, in which case link that issue instead of re-reporting.

Items below are tagged *(standard)* where they belong to the second tier. Never report a *(standard)* item at unanimous severity, and never infer adoption from this page — the tier says what the item is, the repo says whether it is there.

**Bun is everything, not just the installer.** Runtime, package manager, workspace host, test runner, script runner. Cross-package work goes through `bun run --filter '<pkg>' <script>` — never Turbo, never Nx. Every repo carries a `bunfig.toml`, and it is where operational knowledge lives (linker choice, test preloads, install policy), so it is never empty boilerplate.

**Exactly two workspace directories.** `packages/*` is libraries, `apps/*` is deployables. The root `package.json` is `private`, holds no source, and exists to declare workspaces, the catalog, security `overrides`, and the script surface. No third directory — no `tools/*` workspace, no `libs/*`.

**The internal graph has one shape.** Zero-dependency domain core at the bottom → data/reference layer → shared component library → apps. Apps consume and never re-export. Siblings at the same level never depend on each other. In practice: `@randsum/roller`, `optfall-legality`, `salvageunion-reference`, `@binfinite/core` are all the same slot in four different repos.

**One base tsconfig, extended everywhere.** Beyond `strict` — the first block is unanimous, the tagged block is not:

```jsonc
"noUncheckedIndexedAccess": true,
"noUnusedLocals": true,
"noFallthroughCasesInSwitch": true,
"moduleResolution": "Bundler",
"moduleDetection": "force",
"resolveJsonModule": true,
"skipLibCheck": true,
"forceConsistentCasingInFileNames": true,
// (standard) — not yet everywhere, and worth having:
"exactOptionalPropertyTypes": true,
"noImplicitOverride": true,
"verbatimModuleSyntax": true
```

**CI is filter → fan out → one gate.** A `changes` job (`dorny/paths-filter`) computes affected workspaces; per-concern jobs run in parallel gated on it; and **one job with `if: always()` that `needs:` every other job** is the sole required status check. Name it **`CI Success`**. Add `concurrency` with `cancel-in-progress`.

```yaml
  CI-Success:
    name: CI Success
    if: always()
    needs: [changes, lint, typecheck, test, build]   # EVERY other job
    runs-on: ubuntu-latest
    steps:
      - name: Fail if any dependency failed
        if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')
        run: exit 1
```

> ⚠️ **That last step is the whole job — do not omit it.** `if: always()` makes the job *run* regardless of its dependencies; it does not make it *fail* with them. A job whose steps never inspect `needs.*.result` **succeeds when everything it needs failed**, so the sole required status check goes permanently green and red-CI PRs merge clean through the ruleset. Testing `failure`/`cancelled` (not `success`) is deliberate: a path-filtered job reports `skipped`, which must stay passing.

> The `needs:` list is also hand-maintained, and **a job missing from it can never fail the required check** — the gate silently stops gating with no symptom. Ship `check:ci-aggregator` at the same time as the gate itself, not later: parse the workflow, collect job keys, and diff them against the aggregate job's `needs:`.
>
> Two things that implementation must get right, or the check that guards the gate fails on its own repo and gets weakened away:
> - **Exclude the aggregate job from its own diff.** A job cannot `needs:` itself, so a naive key-set comparison always reports it as missing.
> - **Scope it per workflow.** `needs:` reaches only inside one file, so a repo with several workflows needs the check run per workflow — and any status context required from a *different* workflow (CodeQL, for example) is outside what this check can see. Say so in its output rather than implying full coverage.

These are two *different* failure modes with the same symptom — a green gate that gates nothing. The first is a broken job, the second an incomplete `needs:` list. Check for both.

**Biome is the single lint + format tool.** *(standard)* Prettier is removed, not merely unused. `biome.json` carries **only divergences from Biome's defaults** — in practice `vcs.useIgnoreFile: true` (Biome ignores `.gitignore` by default, and without this it descends into `.claude/worktrees/`) and `formatter.indentStyle: "space"` (Biome defaults to tab, and `useEditorconfig` is false). Accept that Biome parses neither Markdown nor YAML; do not reintroduce a second formatter to cover it.

**Lefthook, two tiers.** *(standard)* Pre-commit is staged-files-only (`biome check --write {staged_files}` with `stage_fixed: true`, and `--no-errors-on-unmatched`, which is required — Biome exits 1 rather than skipping when every staged file is out of scope). Pre-push is the expensive tier: typecheck, tests, build. Guard `prepare` with `[ -n "$CI" ] || lefthook install`.

*(standard)* **Knip**, with per-workspace `entry`/`project` globs. **Bun catalogs** for shared versions. **`.bun-version`** pinned and read by CI. **`bun run check`** as the one full-check entry point.

## The signature habit

**Promote conventions from prose into executable `check:*` gates wired into the aggregate job.** This is the most distinctive thing in the stack and the highest-leverage thing to copy. Real examples: `check:tokens`, `check:hub`, `check:stories`, `check:native-exports`, `validate:architecture`, `check:doc-drift`, `check:ci-aggregator`.

The rule: if you find yourself writing a convention into `CLAUDE.md` and hoping it holds, write the check instead. A rule nothing enforces is a rule that has already drifted.

Coverage is uneven, which is the point of auditing: most of those exist in one or two repos, not all four. `check:ci-aggregator` in particular lives only in `binfinite-app` (`scripts/check-ci-aggregator.ts`, wired into `verify`) — it is a real precedent to copy from, *and* the thing the other three still need to ship.

## Surface layer — chosen per app, not per repo

- **Stateful application** → React 19 + **TanStack Router** (file-based routes, generated `routeTree.gen.ts`) on Vite. Add **Query** when there is a server. **Lean on TanStack wherever it applies** — this is the default reach, not a per-app deliberation.
- **Content / marketing site** → **TanStack Start**. Astro is being retired across the portfolio — but this is a *direction*, not a completed migration, and it has **one recorded blocker**: `binfinite-app`'s `apps/marketing` ships zero JavaScript, machine-asserted against built HTML by `check:marketing-zero-js` with Lighthouse gating per-PR. TanStack Start is SSR-plus-hydration by design, so following this rule there breaks an existing check. Until that is settled, marketing stays on Astro. Do not propose the migration for an app with a zero-JS gate without naming the conflict.
- **Headless service, bot, CLI** → no framework. Discord work is built directly on `discord.js` v14 with nothing in between. **Note the runtime caveat in the platform section — the bots run on Node today, and that is the current state everywhere, not drift.**

**Component workbench lives inside the component library package**, never in an app. Ladle or Storybook — the tool is not the standard, the rule is: *one public component = one co-located story = one nav leaf, with a title matching a closed taxonomy*, enforced by a checked-in test or script. Start the allowlist empty and assert that no entry in it is stale.

**Styling** → a framework-agnostic tokens package as the single brand source, style objects for static values, and **one package-level stylesheet** for everything objects cannot express (`:hover`, `@media`, `:focus-visible`, `:disabled`, pseudo-elements). Both halves are required — a style-object-only approach silently drops interaction and responsive state. No Tailwind. No CSS Modules.

> ⚠️ **Split per PROPERTY, never per component.** An inline `style=` declaration outranks any author stylesheet rule regardless of selector specificity or state, because it sits higher in the cascade origin order. So if a property's resting value goes inline and its `:hover` goes to a class, **the hover never fires** — and nothing errors. Measured, not inferred: an element with `style="background-color: green"` and a `:hover` class setting red computes `rgb(0,128,0)` while hovered; move the resting value into the class and the hover applies.
>
> The rule therefore reads: **a property with any stateful or responsive variant goes wholly to the stylesheet, resting value included. A property with none stays inline.** One component routinely splits down the middle of its own style — padding and font inline, `background-color` and `border-color` in a class — and that is correct, not a smell.
>
> Two consequences to expect rather than discover:
> - **The stylesheet is much larger than "the bits objects cannot express"** — it also carries every *resting* value those rules override.
> - **A `filter: brightness()` hover is a warning sign.** It appears to work only because `filter` is a different property from the one it is imitating, so it dodges the collision instead of resolving it. It cannot express a specific hover colour, and approximating one is a re-tone.

> ⚠️ **Verify a real consumer actually loads the stylesheet, and check the built bundle — not the workbench.** Creating the package stylesheet is not the same as shipping it, and the gap between them is invisible to every ordinary check.
>
> Ladle and Storybook wire their own CSS entry, so the workbench renders perfectly whether or not an app imports the file. Tests, typecheck and lint all pass, because none of them load CSS at all. A library can therefore migrate fully onto a stylesheet **no app has ever loaded**, and every surface you would think to check reports success — the workbench does not merely stay silent, it actively reassures. This happened: both SU-SRD apps had migrated components pointed at `--su-*` rules that production never fetched, and it was found by grepping the entry sheets rather than by any gate.
>
> Two things follow:
> - **Add a check that the entry sheets import it, and that the import is layered.** An unlayered `@import` is the *tidier-looking* spelling and it flattens every utility, so both failure modes need catching. Prove the check fires by breaking it each way — a guard nobody has seen fail is indistinguishable from no guard.
> - **Confirm the layer order in the built output and in dev.** Vite serves CSS differently from the production build; correct in one and wrong in the other is the same trap, found later by whoever runs the dev server.

## Platform

- **Netlify** — every web surface.
- **Render** — workers and bots (`region: oregon`, `plan: starter`).
- **Convex** — the backend, where there is one. Schema is the source of truth; check the generated API into git behind a CI freshness gate.
- **Expo / EAS** — mobile only. `BinfiniteLLC/binfinite-app` → `apps/platform` is the reference implementation; copy its conventions rather than re-deriving them. Note it is a single-vendor dependency spanning build, hosting, updates and store submission — treat as concentration risk.

> **Bun does not reach the Discord bots, and that is the measured current state.** All three (`RANDSUM/randsum`, `SalvageUnion-io/SU-SRD`, `alxjrvs/Hermuz` — the last is a fifth repo, older than the four the stack was derived from) build for Node and start with it — `bunup` or `bun build --target node`, then `node dist/index.js` — and their Render services declare `runtime: node`. **Do not report this as drift**, and do not set `BUN_VERSION` on an existing bot as a "fix": it changes the production runtime of a working service. Hermuz's `render.yaml` documents the lever (Render uses Bun when `BUN_VERSION` is set and a `bun.lock` is present) if this is ever taken on deliberately, as its own change with its own testing.

## Deliberate exceptions — do not "fix" these

A deviation is only drift if nothing requires it. These are required:

| Repo | Deviation | Why |
|---|---|---|
| `binfinite-app` | vitest, not `bun:test` | Convex + edge-runtime + happy-dom |
| `binfinite-app` | TypeScript ~6.0.3 | Expo/Convex toolchain |
| `binfinite-app` | `linker = "hoisted"` | Expo single-instancing; isolated duplicates the tree and trips `expo-doctor` |
| `binfinite-app` | `expo lint` for `apps/platform` | Biome ignores that app by design |
| `randsum` | `apps/site`, `apps/rdn` pin TS 6.0.3 off-catalog | `@astrojs/check` needs the TS6 compiler API, which TS7 does not ship |
| `optfall` | No component workbench in the usual sense | It has no Storybook or Ladle. Its workbench is the generated `design-system/` HTML bundle, so apply the story rule against that rather than reporting a missing workbench. |
| `RANDSUM/randsum`, `SalvageUnion-io/SU-SRD`, `alxjrvs/Hermuz` | Discord bots build for and run on **Node**, not Bun | See the platform section — this is the current state everywhere, so it is not a per-repo finding |

Before flagging a deviation, check whether it is on this list or has a comment explaining itself. Removing a load-bearing pin because it looks untidy is the failure mode this table exists to prevent.

