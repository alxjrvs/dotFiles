---
name: agent-stuff-tmux
description: |
  Use when remotely controlling tmux sessions for interactive CLI applications like Python REPLs, GDB, or other programs that require keystrokes and pane output capture. Triggers on phrases like "run in tmux", "control a tmux session", "send keys to tmux", or when debugging with GDB or running interactive Python sessions.
user-invocable: true
---

# tmux Remote Control for Interactive CLI Applications

## Socket Convention

Always place sockets under `CLAUDE_TMUX_SOCKET_DIR`:

```bash
SOCKET_DIR="${CLAUDE_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/claude-tmux-sockets}"
mkdir -p "$SOCKET_DIR"
SOCKET="$SOCKET_DIR/claude.sock"
SESSION="my-session"
```

## Starting a Session

```bash
tmux -S "$SOCKET" new -d -s "$SESSION" -n shell
```

After starting, always give the user a copy-paste monitor command:

```bash
# User can watch live output with:
tmux -S "$SOCKET" attach -t "$SESSION"
```

## Sending Input

Prefer literal sends to avoid shell interpretation:

```bash
# Send a command
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" -l -- "your command here"
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" Enter

# Control keys
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" C-c   # interrupt
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" C-d   # EOF
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" C-z   # suspend
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" Escape
```

## Capturing Output

```bash
# Capture last 200 lines of history
tmux -S "$SOCKET" capture-pane -p -J -t "${SESSION}:0.0" -S -200
```

## Waiting for Prompts

Use a wait script to poll until expected output appears:

```bash
./scripts/wait-for-text.sh -t "${SESSION}:0.0" -p '^>>>' -T 15 -l 4000
```

Or implement inline:

```bash
wait_for_prompt() {
  local target="$1" pattern="$2" timeout="${3:-15}"
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    output=$(tmux -S "$SOCKET" capture-pane -p -J -t "$target" -S -200)
    echo "$output" | grep -qE "$pattern" && return 0
    sleep 0.5
    elapsed=$((elapsed + 1))
  done
  return 1
}
```

## Special Requirements

### Python REPL

Always set `PYTHON_BASIC_REPL=1` to disable the new REPL interface that doesn't play well with capture-pane:

```bash
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" -l -- "PYTHON_BASIC_REPL=1 python3"
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" Enter
wait_for_prompt "${SESSION}:0.0" "^>>>" 15
```

### GDB

Use GDB by default for debugging. Disable paging immediately:

```bash
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" -l -- "gdb ./my-binary"
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" Enter
wait_for_prompt "${SESSION}:0.0" "^\(gdb\)" 15

# Disable paging
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" -l -- "set pagination off"
tmux -S "$SOCKET" send-keys -t "${SESSION}:0.0" Enter
```

## Cleanup

```bash
# Kill a specific session
tmux -S "$SOCKET" kill-session -t "$SESSION"

# Kill everything on the socket
tmux -S "$SOCKET" kill-server
```

## Quick Reference

| Task | Command |
|------|---------|
| New session | `tmux -S "$SOCKET" new -d -s "$SESSION" -n shell` |
| Send text | `tmux -S "$SOCKET" send-keys -t TARGET -l -- "text"` |
| Send Enter | `tmux -S "$SOCKET" send-keys -t TARGET Enter` |
| Capture output | `tmux -S "$SOCKET" capture-pane -p -J -t TARGET -S -200` |
| Kill session | `tmux -S "$SOCKET" kill-session -t "$SESSION"` |
