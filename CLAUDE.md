# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A dotfiles repository for macOS. All config files live here. Most are symlinked to their expected locations via `sync.sh`; a few (like `scripts/`) are read directly from `$HOME/dotFiles/` by shell scripts that hardcode that path.

## Key Commands

```bash
./sync.sh             # Full idempotent setup (Homebrew, mise, symlinks, plugins, macOS defaults)
brew bundle           # Install/update packages from Brewfile
mise install          # Install language versions from mise.toml
sheldon lock --update # Update zsh plugins
```

There are no build, test, or lint commands for this repo.

## Architecture

### Symlink Model

`sync.sh` uses a `link()` function that creates idempotent symlinks with interactive conflict resolution. Source files in this repo map to their destinations:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile` | `~/` |
| `.gitconfig`, `.gitmessage`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `nvim/` | `~/.config/nvim` (AstroNvim v5) |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` |
| `macos/LaunchAgents/*.plist` | `~/Library/LaunchAgents/` (per-file; Caps→Esc lives here) |
| `dot-claude/{CLAUDE.md, settings.json, hooks/, statusline-command.sh}` | `~/.claude/` (individually symlinked) |

### Read-in-place (no symlink)

Some files are consumed directly from `$HOME/dotFiles/` by scripts that hardcode that path. These must remain at that absolute location — they are not synced anywhere:

- `scripts/git-data.sh` — git state cache; sourced by `.zshrc` prompt and the Claude statusline.
- `scripts/theme.sh` — color palette sourced by `.zshrc`'s hand-rolled prompt.

### Claude Code Configuration (`dot-claude/`)

Each entry below is symlinked individually into `~/.claude/` by `sync.sh`. It contains:
- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style)
- `settings.json` — permissions, hooks, environment variables
- `hooks/` — event hooks (shell formatting, lock file protection, output trimming, statusline data)
- `statusline-command.sh` — statusline renderer

## Secrets convention

`.secrets` (gitignored) is sourced by `zsh/00-exports.zsh` in interactive shells only. Use it only for values that subprocesses must inherit at fork time (e.g., `GITHUB_PERSONAL_ACCESS_TOKEN` for Claude MCP). Everything else uses 1Password CLI via the `op-run` wrapper in `zsh/80-functions.zsh` — pattern: `op-run npm publish` with `.npmrc` containing `op://` references. Do NOT add new plaintext tokens to `.secrets`; route them through `op`.

## Guardrails

Pause and confirm with the user before doing any of these:

- **Prompt code in `.zshrc` / `scripts/theme.sh`**: contains raw powerline glyphs (U+E0B0, U+E0B2, U+E0A0, U+276F). The Write/Edit tools strip unicode. To modify these sections, use a Python helper that writes the file byte-exact; never Edit a line containing a glyph directly.
- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*`): never edit by hand. The `lock-file-guard.sh` PreToolUse hook blocks these; do not work around it.
- **`sync.sh` symlink semantics**: the `link()` function prompts on conflict and is interactive. Do not refactor it to auto-overwrite or skip prompts.
- **Hardcoded `$HOME/dotFiles` paths**: `scripts/*.sh` assumes this absolute path. Do not refactor them to use `$PWD` or relative paths.
- **Starship references**: the user replaced Starship with a hand-rolled prompt. If you see `starship` in files, treat it as historical — do not reintroduce Starship code or dependencies.

## Important Gotchas

- **Unicode/Nerd Font glyphs**: The Write/Edit tools strip unicode characters. Use Python to write files containing special codepoints (e.g., powerline glyphs U+E0B0, U+E0B2, U+E0A0 in prompt code).
- **sync.sh is interactive**: The `link()` function prompts on conflicts. Don't expect unattended runs if symlink targets already exist as regular files.
- **dot-claude vs .claude**: Source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root holds machine-local overrides (e.g. `settings.local.json`) that are gitignored — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `zsh-syntax-highlighting` must be last in `sheldon/plugins.toml`.
- **Hardcoded `$HOME/dotFiles` path**: Scripts in `scripts/` are read via absolute path. If the repo is cloned somewhere else, those consumers break.
- **settings.json allow + excludedCommands**: When adding a new command binary to `permissions.allow`, you must also add it to `sandbox.excludedCommands` — omitting it means the sandbox blocks the command regardless of the allow rule. The reverse also applies: an `excludedCommands` entry without a matching allow rule signals intent but has no effect on prompting.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
|------|----------|
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
4. Use `query_graph` pattern="tests_for" to check coverage.
