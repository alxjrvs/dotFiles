# 2. The nightly upkeep applies a green main

- Status: accepted
- Date: 2026-11-17
- Deciders: the owner

## Context and problem statement

#449 had upkeep apply main every night. #520 cut it, for two reasons: an agent's pull request
could merge itself and have its scripts run that night outside the sandbox, and the unattended
`chezmoi update` stalled on questions nobody was there to answer. Since then main lands only when
the owner runs `chezmoi update`, and the owner does not: this Mac's applied source is 37 pull
requests behind main, so the newer Claude deny rules are in the repo and not in force. A rule that
is merged and not applied protects nothing. The owner wants it safe, but hands off.

## Considered options

1. Keep #520: the owner applies by hand.
2. Restore #449's apply as it was: gate on lint, then `--keep-going` past whatever asks.
3. Apply only when nothing has to be asked, and otherwise skip and say why.

## Decision outcome

Option 3. After its upgrades, upkeep runs `chezmoi update` only when all of these hold:

- the fetch of main succeeds;
- that commit's `lint` check succeeded on GitHub Actions (its pull request's head answers for a
  merge that starts no run), with an error or a run in flight counting as not green;
- a dry run of the apply asks nothing, so no managed file was edited by hand since the last apply.

Otherwise the apply is skipped whole, the rest of upkeep still runs, and the run fails into the
notification it already has, with the reason in the log: main not green, the conflicting files by
name, or offline. Nothing is passed `--force`, so a hand edit is never overwritten.

### Consequences

- Good: a merged rule is live by the next morning, on every machine, with no one remembering.
- Good: #520's stall cannot recur. A question is found by the dry run, or fails the apply at once
  with stdin closed.
- Bad: #520's other reason stands. What merges to main runs unattended, outside the sandbox, so
  this is exactly as safe as the auto-merge floor in `agent-auto-merge.yml`. That floor is a
  pattern of what may not merge itself, and a path it forgets merges and runs. The sibling pull
  request on `claude/floor-allowlist` turns it into a list of what may, so it fails closed. **This
  change should merge after that one.**
- Bad: a hand-edited file blocks every apply, nightly, until the owner settles it.
- Accepted: main can move between the lint check and `chezmoi update`'s own pull. The ruleset
  already requires a green `lint` to merge, so the window admits nothing the gate would refuse.

## Reopen when

- the floor stops failing closed, or an agent-merged change is found to have run a program at
  apply;
- an unattended apply breaks a machine, or leaves one half-applied;
- the skip notification fires often enough to be ignored, as #449's issues were;
- chezmoi's no-terminal behaviour changes, so a question waits instead of failing.
