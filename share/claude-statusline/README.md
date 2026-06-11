# claude-statusline

A self-contained [Claude Code](https://claude.com/claude-code) statusline in a single bash script.
No Rust, no extra binaries — just `git` and `jq`.

## What it shows

```
 dotFiles [ main] [ #42: approved] [C: 1 untracked, 2 modified] [+42/-7]
[M: Opus 4.8] [E: medium]
CTX ▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱  63%
5h  ▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱  40% [3h 12m left] [+8%]
7d  ▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  22% [5d 06h left] [-3%]
[$1.23 ($1.23/h)]
```

- **Line 1** — repo (links to GitHub), branch, worktree, PR + review state, git counters (stash/conflict/untracked/modified/staged/ahead/behind), session churn `+added/-removed`.
- **Line 2** — model, effort level (and an optional advisor name).
- **Line 3** — context window with a blackbody-gradient bar; an amber cell marks the autocompact threshold, `AC` when crossed, `200k+` past 200k tokens.
- **Lines 4–5** — 5-hour and 7-day rate-limit windows. The blue pip is the wall-clock position in the window; the yellow pip projects end-of-window usage at the current burn rate; `[+N%]` is usage-vs-clock delta.
- **Line 6** — session cost and $/h burn rate, both read straight from the stdin JSON.

Repo/branch/PR cells are OSC8 hyperlinks — ⌘-click them in a supporting terminal.

## Requirements

- `git` and `jq` on `PATH`.
- A [Nerd Font](https://www.nerdfonts.com/) for the branch//PR glyphs on line 1 (otherwise they render as tofu boxes — everything else is plain Unicode).
- Works with macOS system bash (3.2) and newer.

## Install

```sh
curl -fsSL <raw-gist-url>/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
}
```

## Notes

- The 5h/7d windows show `rate_limits unavailable` until you've made a request in the session that populates them.
- The statusline writes nothing to disk — every cell is rendered from the JSON Claude Code passes on stdin.
- To set the autocompact marker to match a custom threshold, export `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (1–100); defaults to 80.
