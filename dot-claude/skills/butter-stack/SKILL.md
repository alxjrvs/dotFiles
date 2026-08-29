---
name: butter-stack
description: The house Bun/TypeScript monorepo shape (Bun, workspaces, TanStack, edge-deployed React) — scaffold a new repo onto it, or audit an existing one and report drift as a diff. Use for "butter", "the butter stack", "scaffold a new repo", "set this repo up like the others", "what's our stack", or a greenfield TypeScript project.
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

Two modes. **Scaffold** a new repo onto it, or **audit** an existing one and report drift. Both read first and print a diff; scaffolding writes only after you approve.

**Audit never touches the repo** — no files, no config, no settings. It may *offer* to file issues once it has reported, since that is how findings become work, but filing is outward-facing and needs an explicit yes first. Reporting is free; everything else is gated.

**What the stack actually specifies — the invariants, the surface layer, the platform, and the deliberate exceptions not to "fix" — is in [`references/stack.md`](references/stack.md).** Read it before auditing or scaffolding. It is separate because it is an inventory rather than a procedure: this file is what you *do*, that one is what the stack *is*, and a skill body loads in full every time the skill fires.

## Procedure — audit

0. **Fetch first. A local checkout is not the repo.**

   ```sh
   cd <repo>
   REM=$(git remote | head -1)                                    # usually origin — don't assume
   git fetch "$REM"
   DEF=$(git ls-remote --symref "$REM" HEAD | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')
   [ -n "$DEF" ] || { echo "cannot resolve default branch — stop and resolve by hand"; exit 1; }
   git rev-list --left-right --count "$REM/$DEF...HEAD"           # left = commits you are BEHIND
   ```

   Ask the remote for the default branch, and **fail loudly if you cannot get it**. Do not fall back to `main`: `refs/remotes/origin/HEAD` is simply absent on a `git init` + `git remote add` clone and on Git before 2.47, so a `master`/`develop` repo would get compared against a nonexistent `origin/main`, and the check would degrade to nothing — the exact failure this step exists to prevent. A staleness check that quietly performs no check is worse than none, because it reads as a clean bill of health.

   If the left number is non-zero the working copy is behind, and **every finding you produce from it may already be fixed**. Read each file from the fetched remote ref:

   ```sh
   git show "$REM/$DEF:<path>"
   ```

   **Do not `git pull` to fix it.** A pull writes the branch ref and the working tree, and on a dirty checkout or a feature branch it can leave a merge commit or unresolved conflicts behind — mutating a repo this skill promises never to touch, as a side effect of a read-only audit. `git fetch` + `git show` reads the true remote state and changes nothing. If the user wants the checkout updated, that is their call to make separately.

   Use `git show` rather than the API — `gh api "repos/<o>/<r>/contents/<path>"` returns JSON with base64-encoded `content`, so reading it literally gets you an unusable blob. (If you do need the API, `-H "Accept: application/vnd.github.raw"` returns the file.)

   > This step exists because skipping it produced a whole sweep of wrong findings. Five of six checkouts were behind — one by 34 commits — and an entire framework migration had landed ten hours before the audit that claimed it was still pending. The audit filed an issue to adopt a tool that was already adopted, and another to gate a workbench that had been deleted. Reading a file off disk *feels* like reading the repo. It is not.

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

## Landing work: stacks, never a merge queue

**Squash-only merges, linear history required, and `gh stack` for anything multi-part. No merge queue on any repo.** A queue looks like the answer to "I do not want to babysit this", and the cost is not obvious until you are inside it:

- It is **mutually exclusive with Dependabot auto-merge** — `GITHUB_TOKEN` cannot enqueue — so adopting one silently gives up unattended dependency updates.
- It carries a `merge_group:` CI sequencing hazard that hangs every PR if the trigger is not on the default branch first.

The accepted cost of not having one is waiting: watch every layer green, then merge. **Do not propose a queue as the fix for having to wait** — the waiting is the trade.

**Multi-part work is a stack** (`gh stack init` → `gh stack add` per layer → `gh stack submit` → `gh stack sync` after a layer lands). Decide the shape *before* writing code; splitting one large commit afterwards is archaeology. A layer earns its place if it could be reviewed and reverted alone — a refactor that enables a feature, a schema change ahead of its consumers, a rename separated from behaviour. Splitting by file or to hit a size target is not layering.

> **A stack whose layers fix each other's gates cannot land.** Checks are enforced per PR against its own base, so if the bottom layer fails a gate the top layer repairs, the bottom can never go green and the stack never merges — reordering only swaps which job is red. When two fixes are mutually entangled like that, they are one PR, not a stack. Catch it when choosing the shape; by submit time the only exits are retargeting the top layer at the default branch or rebuilding.

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

- **Audit never touches the repo.** It may offer to file issues after reporting — that is the one outward-facing thing it does, and it needs an explicit yes.
- **Never file issues without asking**, and never file one issue per file — one per reviewable change.
- **Do not standardize a deviation on the exceptions table.** Check for a comment explaining it before treating anything as drift.
- **`.bun-version`, the catalog, and `overrides` are security surface**, not formatting. Changing them is a real change; call it out.
- Repos with `.claude/settings.json` checked in tighten rules per-repo there — never a machine-local `settings.local.json`.
