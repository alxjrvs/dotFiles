---
name: butter-stack
description: The Butter Stack — the house Bun/TypeScript monorepo shape (Bun · Unified workspace · TypeScript · TanStack · Edge-deployed · React) and how to scaffold a new repo onto it or audit an existing one against it. Use when the user says "butter", "the butter stack", "scaffold a new repo", "set this repo up like the others", "what's our stack", "audit this against the house stack", or when starting a greenfield TypeScript project. Reports drift as a diff and asks before changing anything.
---

# butter-stack

**Butter, because it goes on the Bun.** The recurring shape across `RANDSUM/randsum`, `SalvageUnion-io/SU-SRD`, `alxjrvs/optfall` and `BinfiniteLLC/binfinite-app` — four monorepos that converged on it independently, never templated from one another. That convergence is the evidence: these are the choices that got re-made under pressure, not a wishlist.

> Repo names below are the **GitHub** names, which differ from the local checkout directories under `~/Code` (`@RANDSUM`, `SU-SRD`, `OptFall`, `BinfiniteLLC/BinfiniteApp`). `BinfiniteLLC/BinfiniteApp` is a directory name and **does not resolve on GitHub** — use `BinfiniteLLC/binfinite-app` for anything that hits the API.

| | | |
|---|---|---|
| **B** | Bun | runtime · pm · workspaces · tests · scripts |
| **U** | Unified workspace | `apps/*` + `packages/*`, nothing else |
| **T** | TypeScript | 7.0.2, strict-plus |
| **T** | TanStack | router · query · start |
| **E** | Edge-deployed | Netlify · Render · Convex |
| **R** | React | 19, behind a shared component library |

Two modes. **Scaffold** a new repo onto it, or **audit** an existing one and report drift. Both read first and print a diff; scaffolding writes only after you approve. Auditing never writes.

## The invariants

These are unanimous across all four repos. Treat a deviation as a finding, not a preference.

**Bun is everything, not just the installer.** Runtime, package manager, workspace host, test runner, script runner. Cross-package work goes through `bun run --filter '<pkg>' <script>` — never Turbo, never Nx. Every repo carries a `bunfig.toml`, and it is where operational knowledge lives (linker choice, test preloads, install policy), so it is never empty boilerplate.

**Exactly two workspace directories.** `packages/*` is libraries, `apps/*` is deployables. The root `package.json` is `private`, holds no source, and exists to declare workspaces, the catalog, security `overrides`, and the script surface. No third directory — no `tools/*` workspace, no `libs/*`.

**The internal graph has one shape.** Zero-dependency domain core at the bottom → data/reference layer → shared component library → apps. Apps consume and never re-export. Siblings at the same level never depend on each other. In practice: `@randsum/roller`, `optfall-legality`, `salvageunion-reference`, `@binfinite/core` are all the same slot in four different repos.

**One base tsconfig, extended everywhere.** Beyond `strict`, the set that appears in all four:

```jsonc
"noUncheckedIndexedAccess": true,
"noUnusedLocals": true,
"noFallthroughCasesInSwitch": true,
"moduleResolution": "Bundler",
"moduleDetection": "force",
"resolveJsonModule": true,
"skipLibCheck": true,
"forceConsistentCasingInFileNames": true,
// three of four, and worth having:
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

> The `needs:` list is also hand-maintained, and **a job missing from it can never fail the required check** — the gate silently stops gating with no symptom. Ship `check:ci-aggregator` (parse `ci.yml`, diff job keys against `needs:`) at the same time as the gate itself, not later.

These are two *different* failure modes with the same symptom — a green gate that gates nothing. The first is a broken job, the second an incomplete `needs:` list. Check for both.

**Biome is the single lint + format tool.** Prettier is removed, not merely unused. `biome.json` carries **only divergences from Biome's defaults** — in practice `vcs.useIgnoreFile: true` (Biome ignores `.gitignore` by default, and without this it descends into `.claude/worktrees/`) and `formatter.indentStyle: "space"` (Biome defaults to tab, and `useEditorconfig` is false). Accept that Biome parses neither Markdown nor YAML; do not reintroduce a second formatter to cover it.

**Lefthook, two tiers.** Pre-commit is staged-files-only (`biome check --write {staged_files}` with `stage_fixed: true`, and `--no-errors-on-unmatched`, which is required — Biome exits 1 rather than skipping when every staged file is out of scope). Pre-push is the expensive tier: typecheck, tests, build. Guard `prepare` with `[ -n "$CI" ] || lefthook install`.

**Knip**, with per-workspace `entry`/`project` globs. **Bun catalogs** for shared versions. **`.bun-version`** pinned and read by CI. **`bun run check`** as the one full-check entry point.

## The signature habit

**Promote conventions from prose into executable `check:*` gates wired into the aggregate job.** This is the most distinctive thing in the stack and the highest-leverage thing to copy. Real examples: `check:tokens`, `check:hub`, `check:stories`, `check:native-exports`, `validate:architecture`, `check:doc-drift`, `check:ci-aggregator`.

The rule: if you find yourself writing a convention into `CLAUDE.md` and hoping it holds, write the check instead. A rule nothing enforces is a rule that has already drifted.

## Surface layer — chosen per app, not per repo

- **Stateful application** → React 19 + **TanStack Router** (file-based routes, generated `routeTree.gen.ts`) on Vite. Add **Query** when there is a server. **Lean on TanStack wherever it applies** — this is the default reach, not a per-app deliberation.
- **Content / marketing site** → **TanStack Start**. Astro is being retired across the portfolio — but this is a *direction*, not a completed migration, and it has **one recorded blocker**: `binfinite-app`'s `apps/marketing` ships zero JavaScript, machine-asserted against built HTML by `check:marketing-zero-js` with Lighthouse gating per-PR. TanStack Start is SSR-plus-hydration by design, so following this rule there breaks an existing check. Until that is settled, marketing stays on Astro. Do not propose the migration for an app with a zero-JS gate without naming the conflict.
- **Headless service, bot, CLI** → no framework. Discord work is built directly on `discord.js` v14 with nothing in between. **Note the runtime caveat in the platform section — the bots run on Node today, and that is the current state everywhere, not drift.**

**Component workbench lives inside the component library package**, never in an app. Ladle or Storybook — the tool is not the standard, the rule is: *one public component = one co-located story = one nav leaf, with a title matching a closed taxonomy*, enforced by a checked-in test or script. Start the allowlist empty and assert that no entry in it is stale.

**Styling** → a framework-agnostic tokens package as the single brand source, style objects for static values, and **one package-level stylesheet** for everything objects cannot express (`:hover`, `@media`, `:focus-visible`, `:disabled`, pseudo-elements). Both halves are required — a style-object-only approach silently drops interaction and responsive state. No Tailwind. No CSS Modules.

## Platform

- **Netlify** — every web surface.
- **Render** — workers and bots (`region: oregon`, `plan: starter`).
- **Convex** — the backend, where there is one. Schema is the source of truth; check the generated API into git behind a CI freshness gate.
- **Expo / EAS** — mobile only. `BinfiniteLLC/binfinite-app` → `apps/platform` is the reference implementation; copy its conventions rather than re-deriving them. Note it is a single-vendor dependency spanning build, hosting, updates and store submission — treat as concentration risk.

> **Bun does not reach the Discord bots, and that is the measured current state.** All three (`randsum`, `SU-SRD`, `Hermuz`) build for Node and start with it — `bunup` or `bun build --target node`, then `node dist/index.js` — and their Render services declare `runtime: node`. **Do not report this as drift**, and do not set `BUN_VERSION` on an existing bot as a "fix": it changes the production runtime of a working service. Hermuz's `render.yaml` documents the lever (Render uses Bun when `BUN_VERSION` is set and a `bun.lock` is present) if this is ever taken on deliberately, as its own change with its own testing.

## Deliberate exceptions — do not "fix" these

A deviation is only drift if nothing requires it. These are required:

| Repo | Deviation | Why |
|---|---|---|
| `binfinite-app` | vitest, not `bun:test` | Convex + edge-runtime + happy-dom |
| `binfinite-app` | TypeScript ~6.0.3 | Expo/Convex toolchain |
| `binfinite-app` | `linker = "hoisted"` | Expo single-instancing; isolated duplicates the tree and trips `expo-doctor` |
| `binfinite-app` | `expo lint` for `apps/platform` | Biome ignores that app by design |
| `randsum` | `apps/site`, `apps/rdn` pin TS 6.0.3 off-catalog | `@astrojs/check` needs the TS6 compiler API, which TS7 does not ship |
| `optfall` | **Svelte, not React** | A deliberate choice, not drift. It also means Biome cannot parse `.svelte` — `svelte-check` covers those, and Prettier is still not reintroduced. Do not propose a React migration off the back of the `R` invariant. |
| `randsum`, `SU-SRD`, `Hermuz` | Discord bots build for and run on **Node**, not Bun | See the platform section — this is the current state everywhere, so it is not a per-repo finding |

Before flagging a deviation, check whether it is on this list or has a comment explaining itself. Removing a load-bearing pin because it looks untidy is the failure mode this table exists to prevent.

## Procedure — audit

1. Read `package.json`, `bunfig.toml`, `tsconfig*.json`, `biome.json`, `lefthook.yml`, `knip.json`, `.github/workflows/ci.yml`.
2. Diff against the invariants above. Classify each gap: **missing**, **drifted**, or **deliberate exception**.
3. Report as a table. Do not write anything.
4. Offer to file issues — one per coherent change, never one mega-issue. Ask first; filing issues is outward-facing.

## Procedure — scaffold

1. Confirm the repo is empty or greenfield. If not, run the audit path instead.
2. Ask two questions: what surfaces does it need (app / site / bot), and is there a backend (Convex or none)?
3. Write the skeleton below.
4. Run `bun install && bun run check` and confirm green before handing back.
5. Run the `agent-friendly-repo` skill to set merge settings and the ruleset — the `CI Success` gate is only real once it is the required check.

```
package.json          private · workspaces · catalog · overrides
bunfig.toml           linker · test preload · install policy
.bun-version
tsconfig.base.json    strict-plus, extended by every workspace
biome.json            divergences from biome defaults ONLY
lefthook.yml          pre-commit staged · pre-push full
knip.json             per-workspace entry/project globs
CLAUDE.md             architecture + gotchas, not the what
.github/workflows/ci.yml   changes → fan-out → CI Success

packages/
  core/               zero-dependency domain logic
  tokens/             framework-agnostic brand source
  component-lib/      the only place visual elements live
    .ladle/ | .storybook/     workbench lives IN the package
    story-coverage.test.ts    1 component = 1 story, taxonomy-checked

apps/
  app/                react 19 + tanstack router/query + vite
  site/               tanstack start
  bot/                discord.js v14 → render worker
```

## Guardrails

- **Audit never writes.** Scaffold writes only after an explicit go-ahead.
- **Never file issues without asking**, and never file one issue per file — one per reviewable change.
- **Do not standardize a deviation on the exceptions table.** Check for a comment explaining it before treating anything as drift.
- **`.bun-version`, the catalog, and `overrides` are security surface**, not formatting. Changing them is a real change; call it out.
- Repos with `.claude/settings.json` checked in tighten rules per-repo there — never a machine-local `settings.local.json`.
