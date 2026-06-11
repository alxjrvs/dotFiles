# Golden Test Harness

Byte-exact reference outputs that snapshot the current shell renderers
(`prompt/prompt-render`, `share/claude-statusline/statusline.sh`,
`share/claude-statusline/subagent-statusline.sh`). The shell scripts are
the source of truth; goldens must match their output (modulo documented
time-dependent fields).

Re-baseline after any intentional rendering change:

```bash
tests/verify-golden.sh --update      # regenerate all golden fixtures
tests/verify-statusline.sh --update  # regenerate statusline fixtures only
```

Then commit the fixture diff for review.

## Directory layout

```
tests/golden/
  HARNESS.md          ← this file
  run-golden.sh       ← parametrized capture/compare driver

  cache/*.sh          ← hand-written git-data cache fixtures (KEY='value')
  json/*.json         ← Claude Code statusline stdin JSON fixtures
  subagent/*.json     ← subagent-statusline stdin JSON fixtures

  out/
    prompt-*.txt      ← captured prompt-render outputs (raw bytes with escapes)
    statusline-*.txt  ← captured statusline outputs
    subagent-*.txt    ← captured subagent-statusline outputs
```

## Fixture inventory

### cache/ — git-data cache files

| Fixture | Description |
|---------|-------------|
| `clean-main.sh` | Clean repo on default branch `main`. No changes, no PR, no worktree. |
| `dirty-feature.sh` | Feature branch `feat/shell-rewrite`. 1 staged, 1 unstaged, 1 untracked, 2 stashes, 3 ahead 1 behind. |
| `worktree.sh` | Git worktree: `GIT_IS_WORKTREE=1`, `GIT_WORKTREE_NAME=dedotctl`, branch `worktree-dedotctl`. |
| `pr-pass.sh` | Feature branch with `GIT_PR_STATUS=pass`, PR #42, 2 ahead. |

Key format: `KEY='value'` (bash single-quoted). Same format as `dot git-data` writes.

### json/ — statusline stdin fixtures

| Fixture | columns | ctx% | Key feature tested |
|---------|---------|------|--------------------|
| `low-ctx.json` | 120 | 15% | Low ctx, rate limits below clock, cost <60s (no burn rate) |
| `high-ctx-near-ac.json` | 120 | 82% | Above autocompact threshold (80%) → AC tag shown; burn rate active (1h session) |
| `rate-limits-high.json` | 120 | 35% | High rate-limit usage (78% 5h, 65% 7d), large cost, long session |
| `with-pr.json` | 120 | 28% | PR `approved` state + worktree name from JSON, lines +87/-12 |
| `narrow-60.json` | 60 | 55% | Narrow terminal → 15-pip bar (columns < 60 breakpoint) |
| `wide-200.json` | 200 | 42% | Wide terminal → 50-pip bar (columns >= 160 breakpoint) |

`resets_at` timestamps in all fixtures are set to a fixed future time relative
to capture: 5h window resets in ~3h, 7d window resets in ~4d 6h. The exact
"Xh Ym left" strings will drift over time; see time-dependency table below.

### subagent/ — subagent-statusline stdin fixtures

| Fixture | columns | Description |
|---------|---------|-------------|
| `active-tasks.json` | 168 | Two tasks: one `running` (12.5k tokens), one `complete` (45k tokens). Normal (non-compact) format. |
| `error-state.json` | 168 | Two tasks: one `failed` (error state, 3.2k tokens), one `inactive` (0 tokens). |
| `narrow-compact.json` | 80 | One `running` task with 1.5M tokens in compact mode (columns < 100). |

`startTime` values are set to within a few minutes of the capture time so
elapsed values are small and meaningful. The `elapsed` field is time-dependent
(see below).

## Capture procedure

All outputs were captured using:

```bash
tests/golden/run-golden.sh capture dot
```

Which sets the following pinned environment per run:

| Env var | Value | Purpose |
|---------|-------|---------|
| `HOME` | `$TMPDIR/golden-capture-$$` | Isolated home; clean cost state; fake settings.json with `advisorModel: "claude-haiku-4-5"` |
| `XDG_CACHE_HOME` | `$TMPDIR/golden-capture-$$/`.cache` | Isolated git-data cache |
| `COLUMNS` | Fixture-specific (60/120/200 etc.) | Controls bar pip count |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `80` | Pins autocompact threshold |
| `PATH` | `$(dirname dot):$(dirname jq):/usr/bin:/bin:/usr/local/bin` | Excludes `gh` so PR refresh is neutralized |
| `PWD` | Repo worktree toplevel (prompt-render only) | Ensures correct cache-hash lookup |

**prompt-render**: runs with `PWD=$REPO_TOPLEVEL` (the git repo) so
`git rev-parse --show-toplevel` succeeds and `load_cache()` finds the right hash.
The pre-seeded cache file overrides live git state for the duration of the run.

**statusline**: runs from a scratch non-repo directory (`$TMPDIR/.../nonrepo`)
so `git_data::run()` finds no repo and writes an empty cache. Line 1 shows only
the `project_dir` from the JSON (no live git counters). The cost line is
rendered purely from the stdin JSON — the statusline writes nothing to disk.

**subagent-statusline**: pure JSON transform; no git or filesystem access. Runs
from the same non-repo scratch dir.

## Cache-hash derivation

The cache filename is `$(sha256(toplevel_path)[:12]).sh`. Rust uses `sha2::Sha256`;
the shell port uses `shasum -a 256` (macOS) / `sha256sum` (Linux) on the same byte
sequence. The harness computes the hash at runtime so it adapts to the actual
repo location without hardcoding.

When the shell port changes the hash function: the cache FILENAMES change but the
behavior is invisible (cache is regenerated on next `git-data` run). Both
`prompt-render` and `statusline` must use the same hash function as `git-data`
(they all source `shared/git-cache.sh`).

## Time-dependency table

| Output | Field(s) | Strictly comparable? | How harness handles |
|--------|----------|---------------------|---------------------|
| `prompt-*.txt` | ALL | YES | byte-for-byte diff |
| `statusline-*.txt` line 1 | repo name, branch, counters | YES (pinned via cache) | byte-for-byte diff |
| `statusline-*.txt` line 2 | model, advisor, effort | YES | byte-for-byte diff |
| `statusline-*.txt` line 3 | CTX bar, %, AC/200k+ | YES | byte-for-byte diff |
| `statusline-*.txt` line 3 | autocompact marker pos | YES (pinned CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80) | byte-for-byte diff |
| `statusline-*.txt` lines 4-5 | bar fill, %, delta | YES | byte-for-byte diff (after strip) |
| `statusline-*.txt` lines 4-5 | `[Xh Ym left]` time label | **NO** — depends on `now - resets_at` | `strip_time_labels()` strips before diff |
| `statusline-*.txt` line 6 | `$cost` | YES (rendered from stdin JSON) | byte-for-byte diff |
| `subagent-*.txt` | `state`, `tokenText`, `tokenSamples` | YES | byte-for-byte diff (after strip) |
| `subagent-*.txt` | `elapsed` | **NO** — depends on `now - startTime` | `strip_elapsed()` replaces value with `"ELAPSED"` before diff |

## Verifying fixtures

Run the verify scripts to diff current script output against the stored goldens:

```bash
# Verify all fixtures (prompt, statusline, subagent)
tests/verify-golden.sh

# Verify statusline fixtures only
tests/verify-statusline.sh
```

Both scripts exit 0 when all checked fixtures pass, 1 on any mismatch.

## Re-baselining after intentional rendering changes

When a rendering change is deliberate (e.g. you modified prompt-render or
statusline.sh), regenerate the fixtures and commit the diff:

```bash
tests/verify-golden.sh --update      # overwrite all goldens from current scripts
tests/verify-statusline.sh --update  # overwrite statusline goldens only
git diff tests/golden/out/           # review what changed
git add tests/golden/out/
```

`--update` prints each file it rewrites. The subsequent `verify-golden.sh` run
(without `--update`) must exit 0 before pushing.
