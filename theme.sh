#!/bin/sh
# Nova — unified terminal colorscheme
# Usage: . "$HOME/dotFiles/theme.sh"
#
# Background: #282c34 (OneDark). All contrast ratios relative to this.
# Contrast notation: W=vs #f0f0f0 (white text on segment), B=vs bg (segment visibility)
# WCAG large/bold text target: 3:1

# ── Core ─────────────────────────────────────────────────────────────────────
NOVA_BG="#282c34"         # Terminal background (OneDark)
NOVA_STATUS_BG="#686e84"  # Status bar background (matches pane border branch color)
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
NOVA_DIR="#c07820"         # Directory amber    W 3.0:1  B 4.1:1  R192 G120 B32
NOVA_BRANCH="#686e84"      # Git branch slate   W 4.1:1  B 3.0:1  R104 G110 B132
NOVA_BRANCH_R=104; NOVA_BRANCH_G=110; NOVA_BRANCH_B=132

# ── Status-right: Time ───────────────────────────────────────────────────────
NOVA_TIME="#8855cc"        # Violet             W 4.4:1  B 2.8:1
NOVA_TIME_DK="#6640aa"     # Violet dark

# ── Status-right: Memory ─────────────────────────────────────────────────────
NOVA_MEM="#2d74cc"         # Ocean blue         W 4.1:1  B 3.0:1
NOVA_MEM_DK="#225baa"      # Blue dark

# ── Status-right: Battery ────────────────────────────────────────────────────
NOVA_BAT_GOOD="#349966"    # Emerald            W 3.1:1  B 3.9:1
NOVA_BAT_GOOD_DK="#277a52"
NOVA_BAT_WARN="#aa7c1e"    # Gold               W 3.4:1  B 3.9:1
NOVA_BAT_WARN_DK="#886018"
NOVA_BAT_LOW="#cc4444"     # Crimson            W 4.1:1  B 3.0:1
NOVA_BAT_LOW_DK="#a03333"

# ── Status-right: CPU ────────────────────────────────────────────────────────
NOVA_CPU_NORM="#9a5c38"    # Terracotta         W 4.7:1  B 2.6:1
NOVA_CPU_NORM_DK="#7a4428"
NOVA_CPU_WARN="#aa8022"    # Saffron            W 3.2:1  B 3.9:1
NOVA_CPU_WARN_DK="#886410"
NOVA_CPU_HIGH="#cc3a3a"    # Crimson            W 4.4:1  B 2.8:1
NOVA_CPU_HIGH_DK="#a02a2a"

# ── Tabs: active ID — warm gold gradient (1 = brightest, 6 = darkest) ────────
# Used for the active tab ID section. Yellow-gold: clearly distinct from the
# orange-brown amber name section. W≈3.5:1 at tab 1.
NOVA_TAB_N1="#d4a820"
NOVA_TAB_N2="#b88c18"
NOVA_TAB_N3="#9c7212"
NOVA_TAB_N4="#80580c"
NOVA_TAB_N5="#643e06"
NOVA_TAB_N6="#482400"

# ── Tabs: active — amber gradient (1 = brightest, 6 = darkest) ───────────────
# All active tabs use fg=#f0f0f0. Tab 1 W≈3.2:1, dims gracefully.
NOVA_TAB_A1="#c07018"  ; NOVA_TAB_A1_DK="#9a5818"
NOVA_TAB_A2="#aa6014"  ; NOVA_TAB_A2_DK="#844810"
NOVA_TAB_A3="#945010"  ; NOVA_TAB_A3_DK="#6e380c"
NOVA_TAB_A4="#7e400c"  ; NOVA_TAB_A4_DK="#582808"
NOVA_TAB_A5="#683008"  ; NOVA_TAB_A5_DK="#421804"
NOVA_TAB_A6="#522004"  ; NOVA_TAB_A6_DK="#2c1202"

# ── Tabs: inactive — slate/indigo gradient (1 = most visible) ────────────────
# Outer bg uses fg=#abb2bf (dim), inner label uses fg=#f0f0f0.
# Purple-slate hue contrasts with amber active tabs.
NOVA_TAB_I1="#62607a"  ; NOVA_TAB_I1_LBL="#78748c"
NOVA_TAB_I2="#565470"  ; NOVA_TAB_I2_LBL="#6c6884"
NOVA_TAB_I3="#4a4864"  ; NOVA_TAB_I3_LBL="#605c78"
NOVA_TAB_I4="#3e3c58"  ; NOVA_TAB_I4_LBL="#54506c"
NOVA_TAB_I5="#32304c"  ; NOVA_TAB_I5_LBL="#484460"
NOVA_TAB_I6="#262440"  ; NOVA_TAB_I6_LBL="#3c3854"

# ── Pane borders ─────────────────────────────────────────────────────────────
NOVA_PANE_BORDER="#5a5a6a"   # Inactive border (brighter than old #4a4a4a)
NOVA_PANE_ACTIVE="#aa88ee"   # Active border lavender (was #A884D4)
NOVA_PANE_PATH="#8866cc"     # Inactive border path text (was #6344a0)

# ── Claude Code alert ────────────────────────────────────────────────────────
NOVA_CLAUDE_ALERT="#D97757"  # Claude brand orange — tab ID blink when needs input
