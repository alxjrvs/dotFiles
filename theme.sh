#!/bin/sh
# Nova — unified terminal colorscheme
# Usage: . "$HOME/dotFiles/theme.sh"
#
# Background: #2E3440 (Nord 0). All contrast ratios relative to this.
# Contrast notation: W=vs #ECEFF4 (white text on segment), B=vs bg (segment visibility)
# WCAG large/bold text target: 3:1

# ── Core ─────────────────────────────────────────────────────────────────────
NOVA_BG="#2E3440"         # Terminal background (Nord 0 — Polar Night)
NOVA_STATUS_BG="#2E3440"  # Terminal bg — used for powerline arrow blending only
NOVA_FG="#ECEFF4"         # Primary text (Nord 6 — Snow Storm)
NOVA_FG_DIM="#D8DEE9"     # Dimmed / inactive text (Nord 4)

# ── Git status ───────────────────────────────────────────────────────────────
# Pip order: stash → conflict → staged → unstaged → untracked → ahead → behind (or clean)
NOVA_GIT_STASH="#B48EAD"     # Stash     Nord 15 — Aurora purple  R180 G142 B173
NOVA_GIT_CONFLICT="#BF616A"  # Conflict  Nord 11 — Aurora red     R191 G97  B106
NOVA_GIT_STAGED="#A3BE8C"    # Staged    Nord 14 — Aurora green   R163 G190 B140
NOVA_GIT_UNSTAGED="#EBCB8B"  # Unstaged  Nord 13 — Aurora amber   R235 G203 B139
NOVA_GIT_UNTRACKED="#81A1C1" # Untracked Nord 9  — Frost blue     R129 G161 B193
NOVA_GIT_AHEAD="#D08770"     # Ahead     Nord 12 — Aurora orange  R208 G135 B112
NOVA_GIT_BEHIND="#5E81AC"    # Behind    Nord 10 — Frost dark     R94  G129 B172
NOVA_GIT_CLEAN="#A3BE8C"     # Clean     Nord 14 — Aurora green   R163 G190 B140

# RGB components for ANSI 24-bit escape codes (git-powerline.sh)
NOVA_BG_R=46;  NOVA_BG_G=52;   NOVA_BG_B=64
NOVA_FG_R=236; NOVA_FG_G=239;  NOVA_FG_B=244
NOVA_GIT_STASH_R=180;     NOVA_GIT_STASH_G=142;     NOVA_GIT_STASH_B=173
NOVA_GIT_CONFLICT_R=191;  NOVA_GIT_CONFLICT_G=97;   NOVA_GIT_CONFLICT_B=106
NOVA_GIT_STAGED_R=163;    NOVA_GIT_STAGED_G=190;    NOVA_GIT_STAGED_B=140
NOVA_GIT_UNSTAGED_R=235;  NOVA_GIT_UNSTAGED_G=203;  NOVA_GIT_UNSTAGED_B=139
NOVA_GIT_UNTRACKED_R=129; NOVA_GIT_UNTRACKED_G=161; NOVA_GIT_UNTRACKED_B=193
NOVA_GIT_AHEAD_R=208;     NOVA_GIT_AHEAD_G=135;     NOVA_GIT_AHEAD_B=112
NOVA_GIT_BEHIND_R=94;     NOVA_GIT_BEHIND_G=129;    NOVA_GIT_BEHIND_B=172
NOVA_GIT_CLEAN_R=163;     NOVA_GIT_CLEAN_G=190;     NOVA_GIT_CLEAN_B=140

# ── Prompt / pane segments ───────────────────────────────────────────────────
NOVA_DIR="#4C566A"         # Directory — Nord 3 (Polar Night, visible against bg)
NOVA_BRANCH="#E5E9F0"      # Git branch — Nord 5 (Snow Storm mid, matches statusline MODEL)
NOVA_BRANCH_R=229; NOVA_BRANCH_G=233; NOVA_BRANCH_B=240

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
# A*_DK are the actual colors used; derived from Nord 12 (#D08770) at 22%–85% brightness.
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
