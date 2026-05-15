#!/bin/sh
# shellcheck disable=SC2034
# Nova — unified terminal colorscheme. Sourced (not executed).
# Usage: . "$DOTFILES_DIR/scripts/theme.sh"
#
# Background: #2E3440 (Nord 0). All contrast ratios relative to this.
# Hex is the single source of truth; *_R/_G/_B decimal triplets are
# auto-derived at the bottom for ANSI 24-bit consumers (prompt, statusline).
# SC2034 suppressed file-wide: every NOVA_* is consumed by external scripts.

# ── Core ─────────────────────────────────────────────────────────────────────
NOVA_BG="#2E3440"         # Terminal background (Nord 0 — Polar Night)
NOVA_STATUS_BG="#2E3440"  # Terminal bg — used for powerline arrow blending only
NOVA_FG="#ECEFF4"         # Primary text (Nord 6 — Snow Storm)
NOVA_FG_DIM="#D8DEE9"     # Dimmed / inactive text (Nord 4)

# ── Git status ───────────────────────────────────────────────────────────────
NOVA_GIT_STASH="#B48EAD"     # Stash     Nord 15 — Aurora purple
NOVA_GIT_CONFLICT="#BF616A"  # Conflict  Nord 11 — Aurora red
NOVA_GIT_STAGED="#A3BE8C"    # Staged    Nord 14 — Aurora green
NOVA_GIT_UNSTAGED="#EBCB8B"  # Unstaged  Nord 13 — Aurora amber
NOVA_GIT_UNTRACKED="#81A1C1" # Untracked Nord 9  — Frost blue
NOVA_GIT_AHEAD="#D08770"     # Ahead     Nord 12 — Aurora orange
NOVA_GIT_BEHIND="#5E81AC"    # Behind    Nord 10 — Frost dark
NOVA_GIT_CLEAN="#A3BE8C"     # Clean     Nord 14 — Aurora green

# PR check status (colors the GitHub icon in branch pill)
NOVA_PR_PASS="#A3BE8C"       # Passing   Nord 14 — Aurora green
NOVA_PR_PENDING="#EBCB8B"    # Pending   Nord 13 — Aurora amber
NOVA_PR_FAIL="#BF616A"       # Failed    Nord 11 — Aurora red

# ── Prompt / pane segments ───────────────────────────────────────────────────
NOVA_DIR="#D8DEE9"         # Directory — Nord 4 (Snow Storm 1)
NOVA_BRANCH="#D8DEE9"      # Git branch — Nord 4 (Snow Storm 1)
NOVA_WORKTREE="#5E81AC"    # Worktree indicator — Nord 10 (Frost dark blue)
NOVA_SEG_BG="#434C5E"      # Segment background — Nord 2 (Polar Night)

# ── Status-right: Time ───────────────────────────────────────────────────────
NOVA_TIME="#3B4252"        # Nord 1 (Polar Night) — far right edge
NOVA_TIME_DK="#2E3440"     # Nord 0 (terminal bg) — label half

# ── Status-right: Battery ────────────────────────────────────────────────────
NOVA_BAT_GOOD="#A3BE8C"    # Nord 14 — Aurora green (functional)
NOVA_BAT_NORM="#5E81AC"    # Nord 10 — Frost blue (positional, good state)
NOVA_BAT_NORM_DK="#4C566A" # Nord 3 — Polar Night (label, always)
NOVA_BAT_WARN="#EBCB8B"    # Nord 13 — Aurora yellow (warning)
NOVA_BAT_LOW="#BF616A"     # Nord 11 — Aurora red (alert)

# ── Status-right: CPU ────────────────────────────────────────────────────────
NOVA_CPU_NORM="#81A1C1"    # Nord 9 — Frost blue (brightest, near center)
NOVA_CPU_NORM_DK="#4C566A" # Nord 3 — Polar Night (label)
NOVA_CPU_WARN="#EBCB8B"    # Nord 13 — Aurora yellow (warning)
NOVA_CPU_HIGH="#BF616A"    # Nord 11 — Aurora red (functional)

# ── Tabs: active ID — fixed blue background (all active tabs use same ID color) ──
NOVA_TAB_ACTIVE_ID="#5E81AC"   # Nord 10 — Frost blue

# ── Tabs: inactive bg + active name section (1=darkest/left, 6=brightest/center) ──
# Derived from Nord 12 (#D08770) at 22%–85% brightness.
NOVA_TAB_A1_DK="#2E1E19"
NOVA_TAB_A2_DK="#432B24"
NOVA_TAB_A3_DK="#593A30"
NOVA_TAB_A4_DK="#744C3F"
NOVA_TAB_A5_DK="#925F4E"
NOVA_TAB_A6_DK="#B1735F"

# ── Pane borders ─────────────────────────────────────────────────────────────
NOVA_PANE_BORDER="#4C566A"   # Nord 3 — Polar Night (inactive border)
NOVA_PANE_ACTIVE="#D08770"   # Nord 12 — Aurora orange (active border)
NOVA_PANE_PATH="#81A1C1"     # Nord 9 — Frost blue (inactive path text)

# ── Claude Code alert ────────────────────────────────────────────────────────
NOVA_CLAUDE_ALERT="#D08770"  # Nord 12 — Aurora orange — tab ID blink when needs input

# ── R/G/B decimal triplets (auto-derived from hex above) ─────────────────────
# Consumers needing decimal ANSI codes get them via NOVA_<NAME>_R / _G / _B.
# Add a NAME to this list when a new color needs decimal access.
for _c in NOVA_BG NOVA_FG NOVA_BRANCH NOVA_WORKTREE NOVA_SEG_BG \
          NOVA_GIT_STASH NOVA_GIT_CONFLICT NOVA_GIT_STAGED NOVA_GIT_UNSTAGED \
          NOVA_GIT_UNTRACKED NOVA_GIT_AHEAD NOVA_GIT_BEHIND NOVA_GIT_CLEAN \
          NOVA_PR_PASS NOVA_PR_PENDING NOVA_PR_FAIL
do
  _hex=$(eval "printf '%s' \"\$$_c\"")
  _hex=${_hex#\#}
  _hr=${_hex%????}
  _rest=${_hex#??}
  _hg=${_rest%??}
  _hb=${_rest#??}
  eval "${_c}_R=$((0x$_hr)) ${_c}_G=$((0x$_hg)) ${_c}_B=$((0x$_hb))"
done
unset _c _hex _rest _hr _hg _hb
