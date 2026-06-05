#!/usr/bin/env bash
# install/90-macos.sh — macOS defaults apply + audit.
# Ports macos_defaults.rs + sync.rs step_macos + doctor.rs macos audit.
# Tags: macos
# Sourced by sync; audit() also called by doctor.

# ── Self-contained helpers ────────────────────────────────────────────────────
if [[ -z "${__DOT_SYNC_SOURCED:-}" ]]; then
  os_kind() {
    case "$(uname -s)" in
      Darwin) printf 'darwin\n' ;;
      Linux) printf 'linux\n' ;;
      *) printf 'unknown\n' ;;
    esac
  }
  host_id() {
    local forced="${DOTFILES_HOST:-}"
    if [[ -n "$forced" ]]; then
      case "$(printf '%s' "$forced" | tr '[:upper:]' '[:lower:]')" in
        air)
          printf 'air\n'
          return 0
          ;;
        pro)
          printf 'pro\n'
          return 0
          ;;
      esac
    fi
    local hostname=""
    if command -v scutil > /dev/null 2>&1; then
      hostname=$(scutil --get LocalHostName 2> /dev/null || true)
    fi
    local lower
    lower=$(printf '%s' "$hostname" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" == *air* ]]; then
      printf 'air\n'
    elif [[ "$lower" == *pro* ]]; then
      printf 'pro\n'
    else
      printf 'unknown\n'
    fi
  }
fi

_macos_tags() { printf 'macos\n'; }

# ── Data table ────────────────────────────────────────────────────────────────
# Format: "domain|key|kind|raw"
# kind: bool|int|float|string
# Maps directly to macos_defaults.rs SHARED const.
_MACOS_SHARED_DEFAULTS=(
  "NSGlobalDomain|KeyRepeat|int|2"
  "NSGlobalDomain|InitialKeyRepeat|int|15"
  "NSGlobalDomain|ApplePressAndHoldEnabled|bool|false"
  "com.apple.finder|AppleShowAllFiles|bool|true"
  "NSGlobalDomain|AppleShowAllExtensions|bool|true"
  "com.apple.finder|_FXShowPosixPathInWindowTitle|bool|true"
  "com.apple.AppleMultitouchTrackpad|Clicking|bool|true"
  "com.apple.dock|autohide|bool|true"
  "com.apple.dock|autohide-delay|float|0"
  "com.apple.dock|autohide-time-modifier|float|0.3"
  "com.apple.dock|tilesize|int|48"
  "NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|bool|false"
  "NSGlobalDomain|NSAutomaticCapitalizationEnabled|bool|false"
  "NSGlobalDomain|NSAutomaticPeriodSubstitutionEnabled|bool|false"
  "NSGlobalDomain|NSAutomaticDashSubstitutionEnabled|bool|false"
  "NSGlobalDomain|NSAutomaticQuoteSubstitutionEnabled|bool|false"
  "com.apple.desktopservices|DSDontWriteNetworkStores|bool|true"
  "com.apple.desktopservices|DSDontWriteUSBStores|bool|true"
)

# Per-host overlays — currently empty, matching Rust AIR_OVERLAY/PRO_OVERLAY.
_MACOS_AIR_OVERLAY=()
_MACOS_PRO_OVERLAY=()

# ── Helpers ───────────────────────────────────────────────────────────────────

# Normalize a raw write value to the string `defaults read` would return.
# Bool "true"/"TRUE"/"yes"/"YES"/"1" → "1"; anything else → "0".
# Non-bool kinds pass through unchanged.
_macos_expected_read() {
  local kind="$1" raw="$2"
  if [[ "$kind" == "bool" ]]; then
    case "$raw" in
      true | TRUE | yes | YES | 1)
        printf '1\n'
        ;;
      *)
        printf '0\n'
        ;;
    esac
  else
    printf '%s\n' "$raw"
  fi
}

# Build the effective managed list for the current host by merging SHARED with
# the per-host overlay. Overlay entries matching domain+key override SHARED;
# new pairs are appended. Writes to stdout as "domain|key|kind|raw" lines.
_macos_managed_for() {
  local host="${1:-unknown}"
  local -a overlay=()
  case "$host" in
    air) overlay=("${_MACOS_AIR_OVERLAY[@]+"${_MACOS_AIR_OVERLAY[@]}"}") ;;
    pro) overlay=("${_MACOS_PRO_OVERLAY[@]+"${_MACOS_PRO_OVERLAY[@]}"}") ;;
  esac

  # Start with SHARED, then apply overlay.
  local -a merged=("${_MACOS_SHARED_DEFAULTS[@]}")

  local o_entry o_domain o_key _o_rest
  local i entry domain key
  for o_entry in "${overlay[@]+"${overlay[@]}"}"; do
    IFS='|' read -r o_domain o_key _o_rest <<< "$o_entry"
    local found=0
    for i in "${!merged[@]}"; do
      IFS='|' read -r domain key _ _ <<< "${merged[$i]}"
      if [[ "$domain" == "$o_domain" && "$key" == "$o_key" ]]; then
        merged[i]="$o_entry"
        found=1
        break
      fi
    done
    if [[ "$found" == "0" ]]; then
      merged+=("$o_entry")
    fi
  done

  local e
  for e in "${merged[@]}"; do
    printf '%s\n' "$e"
  done
}

# ── Run (apply) ───────────────────────────────────────────────────────────────

_macos_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> macOS defaults\n'

  local host
  host=$(host_id)
  local applied=0
  local entry domain key kind raw flag

  while IFS= read -r entry; do
    IFS='|' read -r domain key kind raw <<< "$entry"
    case "$kind" in
      bool) flag="-bool" ;;
      int) flag="-int" ;;
      float) flag="-float" ;;
      string) flag="-string" ;;
      *) flag="-string" ;;
    esac
    if defaults write "$domain" "$key" "$flag" "$raw" \
      > /dev/null 2>&1; then
      applied=$((applied + 1))
    fi
  done < <(_macos_managed_for "$host")

  # Dynamic: screenshots directory.
  local screenshots="${HOME}/Screenshots"
  mkdir -p "$screenshots"
  defaults write com.apple.screencapture location -string "$screenshots" \
    > /dev/null 2>&1 || true

  # Restart services.
  for svc in SystemUIServer Dock Finder; do
    killall "$svc" > /dev/null 2>&1 || true
  done

  printf '\033[0;32m  \xe2\x9c\x93 macOS defaults applied (%d keys; Dock + Finder restarted)\033[0m\n' "$applied"
}

# ── Audit (used by doctor) ────────────────────────────────────────────────────
# Prints one line per entry to stdout:
#   "match|domain|key"            — actual == expected
#   "drift|domain|key|expected|actual"
#   "missing|domain|key|expected"
macos_audit() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi
  local host="${1:-$(host_id)}"
  local entry domain key kind raw expected actual

  while IFS= read -r entry; do
    IFS='|' read -r domain key kind raw <<< "$entry"
    expected=$(_macos_expected_read "$kind" "$raw")
    actual=$(defaults read "$domain" "$key" 2> /dev/null || true)
    actual=$(printf '%s' "$actual" | tr -d '\n')
    if [[ -z "$actual" ]]; then
      printf 'missing|%s|%s|%s\n' "$domain" "$key" "$expected"
    elif [[ "$actual" == "$expected" ]]; then
      printf 'match|%s|%s\n' "$domain" "$key"
    else
      printf 'drift|%s|%s|%s|%s\n' "$domain" "$key" "$expected" "$actual"
    fi
  done < <(_macos_managed_for "$host")
}
