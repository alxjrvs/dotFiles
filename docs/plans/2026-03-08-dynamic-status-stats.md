# Dynamic Status Stats: Language Detection + Conditional Colors

## Summary

Add a language version stat to the tmux status bar that detects the dominant language in the active pane's directory. Make battery and CPU segment colors change based on their values.

## Language Stat (`tmux-lang.sh`)

**Position**: Leftmost stat on status-format[1], before UP.

**Detection**: Check marker files in `pane_current_path`, first match wins:

| Language | Markers | Color | Label |
|---|---|---|---|
| Node.js | package.json, .nvmrc, .node-version | #5f87af | NODE |
| Deno | deno.json, deno.jsonc | #5f87af | DENO |
| Python | pyproject.toml, setup.py, requirements.txt, .python-version | #4a8a70 | PY |
| Rust | Cargo.toml | #b87050 | RUST |
| Go | go.mod | #6e9ecf | GO |
| Ruby | Gemfile, .ruby-version | #c45050 | RUBY |
| Elixir | mix.exs | #7b6aa0 | EX |
| Swift | Package.swift, *.xcodeproj | #d08050 | SWIFT |
| Java | pom.xml, build.gradle | #b07050 | JAVA |
| Kotlin | build.gradle.kts | #9070b0 | KT |
| PHP | composer.json | #7a86b8 | PHP |
| Zig | build.zig | #d0a050 | ZIG |

**Version**: `asdf current <lang>` first, fallback to `<runtime> --version`.

**Output**: Full tmux-styled segment (arrow + value + arrow + label). Hidden when no language detected.

## Dynamic Battery (`tmux-bat.sh`)

Replaces `tmux-sysinfo.sh bat`. Outputs full styled segment with conditional color:

- >50%: #4a9070 (green)
- 20-50%: #c8a030 (yellow)
- <20%: #c05050 (red)
- Charging: prepend lightning bolt before percentage

## Dynamic CPU (`tmux-cpu.sh`)

Replaces `tmux-sysinfo.sh cpu`. Outputs full styled segment with conditional color:

- <50%: #b87050 (orange)
- 50-80%: #c8a030 (yellow)
- >80%: #c05050 (red)

## Architecture

Dynamic segments (lang, cpu, bat) output their own complete tmux format strings with embedded colors. Static segments (UP, MEM) stay hardcoded in status-format[1].

## Files

- **New**: `tmux-lang.sh` — language detection + version
- **New**: `tmux-cpu.sh` — CPU with conditional color
- **New**: `tmux-bat.sh` — battery with conditional color + charging indicator
- **Modified**: `tmux.conf` line 82 — update status-format[1] to use new scripts
- **Unchanged**: `tmux-sysinfo.sh` — still used for uptime and mem
