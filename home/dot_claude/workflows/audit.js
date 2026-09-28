export const meta = {
  name: 'audit',
  description: 'Deep audit of a repo: an advocate and an adversary per lens, an evidence judge each, then a critic',
  whenToUse: 'A fresh, evidence-backed audit of one repo. args: { repo?, focus?, profile?, lenses? }',
  phases: [
    { title: 'Review', detail: 'an advocate and an adversary per lens, in parallel' },
    { title: 'Judge', detail: 'one judge per lens re-runs the evidence and refutes what it cannot' },
    { title: 'Critic', detail: 'conflicts, duplicates, gaps, and the ordering' },
  ],
}

// args: repo (a path; defaults to the session's), focus (what the owner wants weighted), profile (a
// path to what is known about the owner), lenses ([{ key, name, brief }] to replace the defaults).
const A = args ?? {}
const REPO = A.repo ?? 'the current working directory'

const SHARED = `
You are one member of a team auditing the repository at ${REPO}. Read-only: never edit, commit or
push, never change a setting, and never print a secret.${A.focus ? `\nThe owner's weighting: ${A.focus}` : ''}${A.profile ? `\nWhat is known about the owner: read ${A.profile} first.` : ''}
Already litigated: read CLAUDE.md or AGENTS.md and \`git log --oneline -300\` first. A finding that re-proposes something the history added and then removed must name the new evidence that overturns the recorded reason, or it is dropped.
Evidence: every finding cites a checkable source (a path:line, a command you ran and what it printed, or a primary doc or changelog URL). Prefer results over files: run the thing when you can. No source, no finding.
Style: titles under 10 words, claims under 3 sentences, proposals concrete enough to become a PR.`

const LENSES = A.lenses ?? [
  { key: 'architecture', name: 'Architecture', brief: 'Structure, dependencies and dead weight: hand-rolled code where a native built-in exists, abstractions that do not earn their keep, what can be deleted.' },
  { key: 'correctness', name: 'Correctness', brief: 'Bugs, broken invariants, and claims in docs, comments or names that are false today. Reproduce each one.' },
  { key: 'security', name: 'Security', brief: 'Secrets, supply chain (pins, cooldowns, install scripts), token and workflow permissions, and what a prompt-injected agent could reach.' },
  { key: 'delivery', name: 'Delivery', brief: 'CI, tests, releases and the required check: can a PR land unattended, and does anything strand it (strict up-to-date, path-filtered checks, a red main)?' },
  { key: 'agents', name: 'Agent readiness', brief: 'CLAUDE.md or AGENTS.md, .claude settings, skills and hooks, and cloud-session bootstrap: what an agent trips on, waits for, or cannot run.' },
  { key: 'dx', name: 'Developer experience', brief: 'What a newcomer or a fresh clone trips on: setup, scripts, docs that are wrong or missing, slow feedback.' },
]

const LENS = {
  advocate: 'You are the ADVOCATE. Name what is exemplary and must be kept (kind "keep"), then hunt for capability left on the table: native features of tools already in use and proven tools that delete manual work or waiting. 4 to 10 findings.',
  adversary: 'You are the ADVERSARY. Break it: things that are wrong or silently do not work, fragility, dead weight, hand-rolled code with a native replacement, security holes, false claims. Be harsh. 4 to 10 findings, each reproduced or doc-cited.',
}

const FINDING = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    title: { type: 'string' },
    kind: { type: 'string', enum: ['add', 'cut', 'fix', 'replace', 'keep'] },
    impact: { type: 'string', enum: ['high', 'medium', 'low'] },
    effort: { type: 'string', enum: ['S', 'M', 'L'] },
    claim: { type: 'string' },
    proposal: { type: 'string' },
    evidence: {
      type: 'array',
      items: { type: 'object', properties: { source: { type: 'string' }, shows: { type: 'string' } }, required: ['source', 'shows'] },
    },
  },
  required: ['id', 'title', 'kind', 'impact', 'effort', 'claim', 'proposal', 'evidence'],
}
const REVIEW = { type: 'object', properties: { take: { type: 'string' }, findings: { type: 'array', items: FINDING } }, required: ['take', 'findings'] }
const JUDGED = {
  type: 'object',
  properties: {
    lens: { type: 'string' },
    grade: { type: 'string', enum: ['A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F'] },
    summary: { type: 'string' },
    survivors: {
      type: 'array',
      items: {
        type: 'object',
        properties: { ...FINDING.properties, verdict: { type: 'string', enum: ['CONFIRMED', 'PLAUSIBLE'] }, judgeNote: { type: 'string' } },
        required: [...FINDING.required, 'verdict', 'judgeNote'],
      },
    },
    refuted: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] } },
  },
  required: ['lens', 'grade', 'summary', 'survivors', 'refuted'],
}
const CRITIC = {
  type: 'object',
  properties: {
    now: { type: 'array', items: { type: 'string' } },
    next: { type: 'array', items: { type: 'string' } },
    consider: { type: 'array', items: { type: 'string' } },
    drop: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, why: { type: 'string' } }, required: ['title', 'why'] } },
    conflicts: { type: 'array', items: { type: 'string' } },
    gaps: { type: 'array', items: { type: 'string' } },
    bigIdea: { type: 'string' },
  },
  required: ['now', 'next', 'consider', 'drop', 'conflicts', 'gaps', 'bigIdea'],
}

const judged = await pipeline(
  LENSES,
  (l) =>
    parallel(
      ['advocate', 'adversary'].map((side) => () =>
        agent(`${SHARED}\nLENS: ${l.name}. ${l.brief}\n\n${LENS[side]} Stay inside your lens.`, { label: `${l.key}:${side}`, phase: 'Review', schema: REVIEW }),
      ),
    ),
  ([adv, opp], l) =>
    agent(
      `${SHARED}\nLENS: ${l.name}. ${l.brief}\n\nYou are the JUDGE. Re-run each finding's evidence yourself. CONFIRMED means you reproduced it, PLAUSIBLE means partial but credible evidence, and anything you cannot verify is refuted. Merge duplicates, decide explicitly where the advocate and the adversary collide, and grade the lens.\n\nADVOCATE:\n${JSON.stringify(adv)}\n\nADVERSARY:\n${JSON.stringify(opp)}`,
      { label: `${l.key}:judge`, phase: 'Judge', schema: JUDGED, effort: 'high' },
    ),
)

phase('Critic')
const lenses = judged.filter(Boolean)
const critic = await agent(
  `${SHARED}\nYou are the CRITIC over every lens's judged findings. Resolve conflicts, merge duplicates, check any cheap gap now, re-verify the evidence behind what you put in NOW, and order everything: NOW (at most 8, confirmed, cheap), NEXT (at most 8), CONSIDER, and DROP (with why, so it is not re-pitched). bigIdea: the one structural idea the repo is missing, or "none".\n\n${JSON.stringify(lenses)}`,
  { label: 'critic', phase: 'Critic', schema: CRITIC, effort: 'high' },
)
return { lenses, critic }
