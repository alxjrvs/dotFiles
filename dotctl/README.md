# dotctl

The one-stop dotfiles manager for [alxjrvs/dotFiles](https://github.com/alxjrvs/dotFiles). Single Rust binary that:

- installs base dependencies (Homebrew, mise, sheldon, lefthook, gh, fzf, claude CLI)
- creates symlinks (with interactive conflict resolution)
- applies macOS defaults
- powers the zsh prompt + Claude Code statusline + 9 Claude Code hooks

## Why one binary

The shell hot path runs constantly:

| Bash file (now deleted) | Forks per |
|-------------------------|-----------|
| `scripts/git-data.sh` | every prompt redraw + every UserPromptSubmit |
| `dot-claude/statusline-command.sh` | every Claude statusline refresh (~every 10s) |
| `dot-claude/hooks/*.sh` (9 files) | every Claude tool call |
| `sync.sh` + `install/*.sh` | every fresh-machine setup / `make sync` |

Per-fork bash cold-start on macOS is ~30-80ms. At Claude's tool-call rate, that compounds visibly. A single Rust binary: ~5ms cold start, no `sed`/`grep`/`jq` subprocesses inside hot loops, `cargo test` instead of "looks fine", and no bash 3.2 portability gotchas (macOS `/bin/sh` is bash 3.2).

## Subcommands

| Verb | Job |
|------|-----|
| `dotctl sync` | Idempotent install/resync. Installs missing tools, recreates broken symlinks, applies Brewfile/mise.toml/macOS defaults. Safe anytime; fast on no-op. |
| `dotctl sync --upgrade` | Same + brew update/upgrade/cleanup. |
| `dotctl sync --only=brew,mise` | Only listed sections. |
| `dotctl update` | Equivalent to `dotctl sync --upgrade`. |
| `dotctl doctor` | Read-only diagnostics: tool presence, symlink integrity, drift. Non-zero exit on missing tools. |
| `dotctl git-data` | Hot path. Refreshes `$XDG_CACHE_HOME/git-data/<hash>.sh` with git state + PR status. |
| `dotctl prompt-render` | Hot path. Renders the zsh powerline prompt from the git cache. |
| `dotctl statusline` | Hot path. Renders the Claude Code 3-5 line statusline. Reads JSON from stdin. |
| `dotctl hook <event>` | Hot path. Dispatches a Claude Code hook event. Event = kebab-case bash filename (e.g. `lock-file-guard`, `format-on-save`). |

## Install (fresh machine)

From a bare macOS:

```
git clone https://github.com/alxjrvs/dotFiles ~/dotFiles
~/dotFiles/bootstrap.sh
```

`bootstrap.sh` installs rust via rustup, builds + installs `dotctl` to `~/.local/bin/`, then `exec`s `dotctl sync`. The rest happens through `dotctl`.

## Design

- **Shell out to `git`** rather than link `libgit2`. Slightly slower per call but always matches the user's installed git version and config.
- **Shell out to `gh`** for PR status (with `--jq` for aggregation). Cached 60s — `gh` is called at most once per minute per repo.
- **No `tokio`.** All subcommands are synchronous; the bash they replaced was synchronous too.
- **`anyhow` for errors.** This is a binary, not a library; structured error types aren't worth their weight.
- **`clap` derive.** CLI shape lives in `src/main.rs`.
- **`serde_json`** for hook event payloads (replaces multiple `jq` forks per hook).
- **`sha2`** for the git cache filename hash (matches the bash `shasum -a 256` exactly).
- **No regex crate.** A single `grep -qE` shim in `hook::regex_match` keeps binary size down.

## Test

```
cargo build --release
./target/release/dotctl --help
./target/release/dotctl doctor
./target/release/dotctl git-data && head ~/.cache/git-data/*.sh
```
