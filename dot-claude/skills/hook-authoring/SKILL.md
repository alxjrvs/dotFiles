---
name: hook-authoring
description: Write or change a Claude Code guard hook in the dotFiles repo - the house shape, the fail-open contract, the tokenizer helpers in guard-lib.sh, and the four places a new hook has to be wired or it silently does nothing. Use when adding a guard, editing one, or debugging one that is not firing.
---

# hook-authoring

The house shape for the guards in `dot-claude/hooks/`. This exists because it was
re-derived from scratch every time, and each rediscovery cost the same mistakes.

## The contract

**Fail open, always.** A missing `jq`, a non-repo cwd, an unparseable payload, a
missing `guard-lib.sh` — every one of them exits 0 and lets the command through.
A guard that wedges the agent is worse than one that misses, because the miss is
a risk and the wedge is a certainty. Every `exit 0` on an error path is
deliberate; none of them is a bug.

**Deny is the only verdict you emit.** Never emit `allow` — a hook that can
approve is a hook that can widen. Emitting nothing IS the pass.

```sh
deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
```

**Tokenize; never substring-match.** `echo git push origin main` is not a push,
and a commit message mentioning `op read` is prose. This is not hypothetical:
writing about these guards became impossible to commit, twice, before the
tokenizer existed.

## Use guard-lib.sh; do not re-implement it

Source it, fail open if absent:

```sh
# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow
```

| helper | what it does |
|---|---|
| `_split` | one simple command per line, quote-aware. Splits on `;`, `&`, `\|`, newline, and on `(`, `)` and a backtick so a substitution body is judged as a command |
| `_norm` | normalizes a segment to real argv: strips shell keywords, `env`/`command`/`exec`, `sudo`/`doas` and their flags, and leading assignments |
| `_unquote` | strips quotes and parens so a ref compares by name |
| `_skip_global` | walks past git's global options to reach the subcommand |
| `_is_interpreter` | shells plus scripting runtimes plus `find`/`ssh` |
| `_scan_text` | flattens punctuation to spaces — use this, never `_unquote`, before a pattern scan |
| `_expand_interpreters` | expands `bash -c "..."` payloads into extra segments, and pulls quoted runs out of a pipe-into-interpreter |
| `_owned_orgs` | the GitHub owners this machine may write to |

`_scan_text` exists because `_unquote` DELETES punctuation, which glued
`os.system('op read` into `os.systemop read` and made every `python3 -c` payload
invisible to an anchored pattern. If you are scanning text, use `_scan_text`.

## The three-way choice for an interpreter payload

Not the same answer for every guard, and getting it wrong is how you either
leak or wedge:

- **Refuse it** when you cannot know what the payload does — `op-guard` cannot
  know what an `op` command will print, so `sh -c '...'` containing one is denied
  outright.
- **Expand and judge it** when the payload is a command your guard already
  understands — `rebase-guard` expands `bash -c "git push origin main"` and
  applies the ordinary refspec logic, so `bash -c "git push origin feature"`
  still works.
- **Ignore it** when your guard's subject cannot appear in a payload at all.

## Wire it in FOUR places or it does nothing

This is the step that gets missed, and the failure is silent — the script sits
on disk, passes its suite, and enforces nothing.

1. `dot-claude/settings.json` — a handler under the right event. Put an `"if"`
   on the HANDLER, never on the matcher group: it is silently dropped there.
2. `boomfile.toml` — a `[[section.link]]` with `mode = "755"`, or it is never
   symlinked into `~/.claude/hooks/`.
3. `scripts/settings-guardrails.sh` — add the filename to `wired_hooks`. This is
   what makes un-wiring it fail lefthook, CI and `boom verify` instead of passing
   all three.
4. `lefthook.yml` and `.github/workflows/lint.yml` — a suite entry.

## Tests

A guard whose cases live in a fixture table goes in `dot-claude/hooks/tests/cases.tsv`
(columns: guard, fixture, command, expected). A guard whose verdict depends on
machine state — a live PID, an origin remote — needs its own harness; copy the
shape of `wtremove.sh` or `reposcope.sh`.

**Write the failing case first.** Every guard in this repo was fixed that way,
and one of those fixes broke two existing allow-cases that only the suite caught.

**Record the negative control, measured.** When most of your cases assert the
guard did NOT fire, a hook that does nothing passes them all. Run a stub
(`exit 0`) and an inverted variant, and write the resulting failure counts into
the suite header. Do not reason them out — the counts were wrong both times
someone tried, in this repo, in the same week.

## Portability

bash 3.2. Not because bash is undeclared — the Brewfile declares bash 5 — but
because a hook cannot assume its PATH: launchd and a mid-provision machine can
each hand it the system bash. No arrays, no `${arr[@]}` on a possibly-empty
array, no `declare -g`. `shellcheck -x` and `shfmt -d -i 2 -ci -sr` both gate.
