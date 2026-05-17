# dotctl

Hot-path utility binary for [alxjrvs/dotFiles](https://github.com/alxjrvs/dotFiles). Consolidates bash scripts that fire on every prompt redraw / Claude Code tool call / statusline refresh into a single static Rust binary.

## Why

The dotfiles repo's bash hot-path runs *constantly*:

| Bash file | Forks per |
|-----------|----------|
| `scripts/git-data.sh` (187 lines) | every prompt redraw + every Claude UserPromptSubmit |
| `dot-claude/statusline-command.sh` (302 lines) | every Claude statusline refresh (~every 10s) |
| `dot-claude/hooks/*.sh` (9 files) | every Claude tool call (PreToolUse/PostToolUse fire many per turn) |

Per-fork bash cold start is ~30-80ms on macOS. At Claude's tool-call rate that compounds visibly. Rust binary: ~5ms cold start, single allocator, no `sed`/`grep`/`jq` subprocesses inside hot loops.

Other wins:
- Kills the bash 3.2 portability gotchas (macOS `/bin/sh` is bash 3.2) that already bit `scripts/git-data.sh` once.
- Testable. `cargo test` instead of "looks fine."
- Removes the "Write/Edit tool strips unicode" hazard from prompt code — Rust string literals don't care about powerline glyphs (U+E0B0 etc.).

## Status

| Subcommand | Replaces | Status |
|------------|----------|--------|
| `dotctl git-data` | `scripts/git-data.sh` | **✓ implemented** (this PR) |
| `dotctl prompt-render` | inline render in `zsh/50-prompt.zsh` | TODO |
| `dotctl statusline` | `dot-claude/statusline-command.sh` | TODO |
| `dotctl hook <event>` | `dot-claude/hooks/*.sh` (9 hooks) | TODO |

Output format for `dotctl git-data` matches the bash script byte-for-byte so existing consumers (`source $cache_file` in zsh) work unchanged.

## Roadmap

**Phase 1 — `git-data` (this PR).**
Scaffold the crate + port the highest-frequency call. No integration yet: `scripts/git-data.sh` stays in place; nothing in zsh/Claude switches over. The Rust binary sits alongside, callable but unused. Lets you review the design before commitment.

**Phase 2 — wire `git-data` in.**
Update `zsh/50-prompt.zsh` to call `dotctl git-data` instead of `bash $DOTFILES_DIR/scripts/git-data.sh`. Add `install/15-dotctl.sh` to build + install the binary via `cargo install --path dotctl`. `scripts/git-data.sh` deleted.

**Phase 3 — `hook` dispatcher.**
Single binary handles all 9 hook events. `dot-claude/settings.json` hook commands change from `bash ~/.claude/hooks/X.sh` to `dotctl hook X`. Bash hook files deleted.

**Phase 4 — `statusline` + `prompt-render`.**
Port the powerline rendering. These are the trickiest — lots of ANSI escape coordination, OSC8 hyperlinks, Nord theme color triplets. Once done, `dot-claude/statusline-command.sh` and most of `zsh/50-prompt.zsh` collapse to glue.

## Install

When phase 2 lands, `sync.sh` builds and installs `dotctl` automatically:

```bash
cd dotctl && cargo install --path .
```

Until then: `cargo build --release -p dotctl` from `~/dotFiles/` for manual testing.

## Design

- **Shell out to `git`** rather than link `libgit2`. Slightly slower per call but always matches the user's installed git version and config.
- **No `tokio`.** All subcommands are synchronous; the bash they replace is synchronous too.
- **`anyhow` for errors.** This is a binary, not a library; structured error types aren't worth their weight.
- **`clap` derive.** CLI shape lives in `src/main.rs` next to the dispatcher.
- **Per-subcommand module.** `src/git_data.rs`, eventually `src/hook.rs`, `src/statusline.rs`, `src/prompt.rs`.

## Test

```bash
cargo build --release
./target/release/dotctl git-data
cat ~/.cache/git-data/*.sh  # confirm output matches scripts/git-data.sh
```

Diff against the bash script to confirm format parity:

```bash
bash ~/dotFiles/scripts/git-data.sh
mv ~/.cache/git-data/*.sh /tmp/bash-output
./target/release/dotctl git-data
diff /tmp/bash-output ~/.cache/git-data/*.sh  # should differ only in the `Generated: <date>` line and the cache header comment
```
