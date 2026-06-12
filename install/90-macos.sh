#!/usr/bin/env bash
# install/90-macos.sh — macOS defaults apply + audit.
# Tags: macos
# Sourced-only — by sync (apply) and doctor (audit). Both define and export
# os_kind before sourcing this module, so this file carries no inlined helpers
# of its own.

_macos_tags() { printf 'macos\n'; }

# ── Data table ────────────────────────────────────────────────────────────────
# Format: "domain|key|kind|raw"   (kind: bool|int|float|string)
_MACOS_DEFAULTS=(
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

# Normalize a raw write value to the string `defaults read` would return.
# Bool "true"/"TRUE"/"yes"/"YES"/"1" → "1"; anything else → "0".
# Non-bool kinds pass through unchanged.
_macos_expected_read() {
  local kind="$1" raw="$2"
  if [[ "$kind" == "bool" ]]; then
    case "$raw" in
      true | TRUE | yes | YES | 1) printf '1\n' ;;
      *) printf '0\n' ;;
    esac
  else
    printf '%s\n' "$raw"
  fi
}

# ── Run (apply) ───────────────────────────────────────────────────────────────

_macos_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> macOS defaults\n'

  local applied=0
  local entry domain key kind raw flag
  for entry in "${_MACOS_DEFAULTS[@]}"; do
    IFS='|' read -r domain key kind raw <<< "$entry"
    case "$kind" in
      bool) flag="-bool" ;;
      int) flag="-int" ;;
      float) flag="-float" ;;
      *) flag="-string" ;;
    esac
    if defaults write "$domain" "$key" "$flag" "$raw" > /dev/null 2>&1; then
      applied=$((applied + 1))
    fi
  done

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
  local entry domain key kind raw expected actual
  for entry in "${_MACOS_DEFAULTS[@]}"; do
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
  done
}
