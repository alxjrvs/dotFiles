#!/usr/bin/env bash
# install/90-macos.sh — macOS defaults apply + audit.
# Tags: macos
# Sourced-only — by sync (apply) and doctor (audit). Both define and export
# os_kind/host_id and set __DOT_SYNC_SOURCED before sourcing this module, so
# this file carries no inlined helpers of its own.

_macos_tags() { printf 'macos\n'; }

# ── Data table ────────────────────────────────────────────────────────────────
# Format: "domain|key|kind|raw"
# kind: bool|int|float|string
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

# ── Snapshot (pre-write backup) ───────────────────────────────────────────────
# Before the first `defaults write` of a run, record the current value of every
# (domain,key) the run is about to write, so the prior state is recoverable.
# Keys not yet set read back empty → recorded as 'unset' (never aborts the run).
# Writes a single timestamped file under ~/.local/state/dotfiles/defaults-backup/.
# Echoes the backup path on success; returns non-zero (without aborting the
# caller) if the directory could not be created.
_macos_snapshot() {
  local host="$1"
  local dir="${HOME}/.local/state/dotfiles/defaults-backup"
  if ! mkdir -p "$dir" 2> /dev/null; then
    return 1
  fi
  local stamp
  stamp=$(date +%Y%m%dT%H%M%S)
  local file="${dir}/${stamp}.txt"

  local entry domain key _kind _raw current
  {
    printf '# dotfiles macOS defaults snapshot — %s (host: %s)\n' "$stamp" "$host"
    while IFS= read -r entry; do
      IFS='|' read -r domain key _kind _raw <<< "$entry"
      if current=$(defaults read "$domain" "$key" 2> /dev/null); then
        current=$(printf '%s' "$current" | tr -d '\n')
        printf '%s|%s|%s\n' "$domain" "$key" "$current"
      else
        printf '%s|%s|unset\n' "$domain" "$key"
      fi
    done < <(_macos_managed_for "$host")
  } > "$file" 2> /dev/null

  printf '%s\n' "$file"
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

  # Snapshot current values before the first write (best-effort; never aborts).
  local snapshot
  if snapshot=$(_macos_snapshot "$host"); then
    printf '\033[2m  - snapshot saved to %s\033[0m\n' "${snapshot/#$HOME\//~/}"
  else
    printf '\033[0;33m  \xe2\x9a\xa0 could not write defaults snapshot (continuing)\033[0m\n' >&2
  fi

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
