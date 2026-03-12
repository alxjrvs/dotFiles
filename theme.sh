#!/bin/sh
# Nova — unified terminal colorscheme
# Usage: . "$HOME/dotFiles/theme.sh"
#
# Background: #282c34 (OneDark). All contrast ratios relative to this.
# Contrast notation: W=vs #f0f0f0 (white text on segment), B=vs bg (segment visibility)
# WCAG large/bold text target: 3:1

# ── Core ─────────────────────────────────────────────────────────────────────
NOVA_BG="#282c34"         # Terminal background (OneDark)
NOVA_STATUS_BG="#282c34"  # Terminal bg — used for powerline arrow blending only
NOVA_FG="#f0f0f0"         # Primary text
NOVA_FG_DIM="#abb2bf"     # Dimmed / inactive text

# ── Git status ───────────────────────────────────────────────────────────────
# OneDark — kept as-is; these are tuned for terminal readability
NOVA_GIT_BLUE="#61afef"    # Stash          W 4.7:1  B 5.7:1  R97  G175 B239
NOVA_GIT_RED="#e06c75"     # Dirty          W 4.2:1  B 3.8:1  R224 G108 B117
NOVA_GIT_YELLOW="#e5c07b"  # Unpushed       W 2.5:1  B 5.8:1  R229 G192 B123
NOVA_GIT_GREEN="#98c379"   # Clean          W 2.8:1  B 4.6:1  R152 G195 B121

# RGB components for ANSI 24-bit escape codes (git-powerline.sh)
NOVA_BG_R=40;  NOVA_BG_G=44;   NOVA_BG_B=52
NOVA_FG_R=240; NOVA_FG_G=240;  NOVA_FG_B=240
NOVA_GIT_BLUE_R=97;    NOVA_GIT_BLUE_G=175;  NOVA_GIT_BLUE_B=239
NOVA_GIT_RED_R=224;    NOVA_GIT_RED_G=108;   NOVA_GIT_RED_B=117
NOVA_GIT_YELLOW_R=229; NOVA_GIT_YELLOW_G=192; NOVA_GIT_YELLOW_B=123
NOVA_GIT_GREEN_R=152;  NOVA_GIT_GREEN_G=195;  NOVA_GIT_GREEN_B=121

# ── Prompt / pane segments ───────────────────────────────────────────────────
NOVA_DIR="#7D4B19"         # Directory warm dark brown (lake_superior anchor)
NOVA_BRANCH="#324B64"      # Git branch cool dark blue (lake_superior anchor)
NOVA_BRANCH_R=50; NOVA_BRANCH_G=75; NOVA_BRANCH_B=100

# ── Status-right: Time ───────────────────────────────────────────────────────
NOVA_TIME="#19324B"        # Darkest navy — far right edge
NOVA_TIME_DK="#0f2036"     # Even darker for label half

# ── Status-right: Memory ─────────────────────────────────────────────────────
NOVA_MEM="#324B64"         # Lake_superior dark blue
NOVA_MEM_DK="#1e3450"

# ── Status-right: Battery ────────────────────────────────────────────────────
NOVA_BAT_GOOD="#2e8a5c"    # Cool green (functional)
NOVA_BAT_GOOD_DK="#226b46"
NOVA_BAT_WARN="#b07820"    # Amber warning (functional)
NOVA_BAT_WARN_DK="#8a5c18"
NOVA_BAT_LOW="#c04040"     # Red alert (functional)
NOVA_BAT_LOW_DK="#9e3030"

# ── Status-right: CPU ────────────────────────────────────────────────────────
NOVA_CPU_NORM="#4B647D"    # Lake_superior medium blue — brightest (near center)
NOVA_CPU_NORM_DK="#324B64"
NOVA_CPU_WARN="#b07820"    # Amber (functional)
NOVA_CPU_WARN_DK="#8a5c18"
NOVA_CPU_HIGH="#c04040"    # Red (functional)
NOVA_CPU_HIGH_DK="#9e3030"

# ── Tabs: active ID — fixed blue background (all active tabs use same ID color) ──
NOVA_TAB_ACTIVE_ID="#4B647D"   # Lake superior medium blue

# ── Tabs: inactive bg + active name section (1=darkest/left, 6=brightest/center) ──
# A*_DK are the actual colors used; non-DK variants and NOVA_TAB_I* removed (unused).
NOVA_TAB_A1_DK="#3e2210"
NOVA_TAB_A2_DK="#56301a"
NOVA_TAB_A3_DK="#6e4020"
NOVA_TAB_A4_DK="#865228"
NOVA_TAB_A5_DK="#9e6430"
NOVA_TAB_A6_DK="#b47838"

# ── Pane borders ─────────────────────────────────────────────────────────────
NOVA_PANE_BORDER="#324B64"   # Inactive border — lake_superior dark blue
NOVA_PANE_ACTIVE="#C87D4B"   # Active border — lake_superior terracotta
NOVA_PANE_PATH="#4B647D"     # Inactive path text — lake_superior medium blue

# ── Claude Code alert ────────────────────────────────────────────────────────
NOVA_CLAUDE_ALERT="#D97757"  # Claude brand orange — tab ID blink when needs input
