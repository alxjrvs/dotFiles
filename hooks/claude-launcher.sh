#!/bin/sh
# claude-launcher.sh — give Claude Code a STABLE macOS TCC identity.
#
# NOT a boom hook: this is `link`ed to ~/.local/bin/claude and replaces the
# symlink the native installer puts there.
#
# The problem. macOS keys a TCC grant to the executable's absolute path (the
# `csreq` column on those rows is NULL, so the code hash is NOT pinned — only
# the path is). The native installer stages every release at its own path,
# ~/.local/share/claude/versions/<ver>, so each update is a brand-new client to
# TCC and every "wants to access data from other apps" prompt comes back. This
# machine had accumulated 76 such rows, 46 of them kTCCServiceSystemPolicyAppData
# — one per update since May 2026.
#
# The fix, and why it is Anthropic's own. Claude Code ships a stable app bundle
# beside the versions dir (ClaudeCode.app, CFBundleIdentifier
# com.anthropic.claude-code) and re-execs itself through it with responsibility
# disclaimed — but only on the background/PTY-host path, never for the
# foreground TUI. So bg sessions already have a permanent identity and
# interactive ones do not. This launcher closes that gap: it points the bundle's
# executable at the newest installed release and execs *that*, so TCC sees the
# bundle every time. Grants then survive updates because the identity no longer
# moves. Nothing here is a private interface — the bundle, its Info.plist and
# its CFBundleIdentifier are all written by Claude Code itself.
#
# Why a wrapper is allowed to live here. `claude doctor` names this exact
# arrangement: a launcher at ~/.local/bin/claude that is not a symlink into
# versions/ is reported as "expected" if intentional, and auto-update leaves it
# alone — "new versions still install under $XDG_DATA_HOME/claude/versions, your
# launcher decides what runs". Two consequences are load-bearing:
#   1. Automatic version cleanup is disabled while this is in place (the
#      installer cannot know which version a launcher needs, so it keeps them
#      all, at ~317MB each), so this script prunes instead — newest three kept,
#      and only on the update transition.
#   2. Refreshing the bundle hardlink CANNOT be delegated back to Claude Code.
#      Its own refresh only runs when process.execPath is under versions/, which
#      is never true once this launcher is in front — so a bare symlink to the
#      bundle would silently pin the machine to whatever version it last held.
#      Refresh-then-exec is the whole reason this is a script and not a symlink.
#
# Fails OPEN: every error path falls through to exec'ing the release binary
# directly. A stale TCC prompt is an annoyance; a `claude` that will not start is
# an outage.
#
# To hand the launcher back to Claude Code: rm ~/.local/bin/claude && claude update
# (and drop the `Claude Code launcher` section from boomfile.toml, or boom will
# put it back on the next sync).

set -u

root="${XDG_DATA_HOME:-$HOME/.local/share}/claude"
versions="$root/versions"
app="$root/ClaudeCode.app"
exe="$app/Contents/MacOS/claude"

# Newest installed release. Mirrors Claude Code's own resolver: strict semver
# names only, which is also what excludes the `<ver>.tmp.<n>.<n>` files the
# updater stages mid-download.
newest=$(printf '%s\n' "$versions"/* 2> /dev/null | sed 's|.*/||' |
  grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[ -n "$newest" ] && bin="$versions/$newest" || bin=""

# Nothing installed, or not macOS: there is no bundle to route through.
if [ -z "$bin" ] || [ ! -x "$bin" ] || [ "$(uname -s)" != "Darwin" ]; then
  [ -n "$bin" ] && [ -x "$bin" ] && exec "$bin" "$@"
  echo "claude: no installed version found under $versions" >&2
  exit 127
fi

# Point the bundle at the newest release. A hardlink, not a copy — the bundle
# executable must BE the release binary (same inode) or the signature and the
# 317MB are duplicated on every update.
if [ ! -e "$exe" ] || [ "$(stat -f %i "$exe" 2> /dev/null)" != "$(stat -f %i "$bin")" ]; then
  mkdir -p "$app/Contents/MacOS" 2> /dev/null
  # Byte-identical to the plist Claude Code writes for itself, so a future
  # version that does refresh the bundle finds nothing to change. The usage
  # strings are what macOS shows in the mic / Apple Events prompts.
  cat > "$app/Contents/Info.plist" 2> /dev/null << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.anthropic.claude-code</string><key>CFBundleName</key><string>Claude Code</string><key>CFBundleDisplayName</key><string>Claude Code</string><key>CFBundleExecutable</key><string>claude</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/><key>NSMicrophoneUsageDescription</key><string>Claude Code uses the microphone for voice dictation.</string><key>NSAppleEventsUsageDescription</key><string>Claude Code needs to send Apple Events to open URLs and control applications you authorize.</string><key>NSLocalNetworkUsageDescription</key><string>Claude Code connects to servers and devices on your local network when commands you run need to reach them.</string></dict></plist>
PLIST
  rm -f "$exe" 2> /dev/null
  ln "$bin" "$exe" 2> /dev/null || exec "$bin" "$@"

  # Replace the version cleanup this launcher disables (see header). Only runs
  # on the update transition, never on a normal launch, and only ever removes
  # strict-semver files under versions/ — never the newest three.
  #
  # Safe precisely BECAUSE this launcher exists: every session it starts has a
  # process.execPath of the bundle, not of a versions/ path, so nothing live is
  # holding the file being removed. The one exception is a session started
  # before this launcher was installed, which would have to survive three
  # updates to be affected.
  printf '%s\n' "$versions"/* 2> /dev/null | sed 's|.*/||' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | tail -n +4 |
    while read -r stale; do rm -f "$versions/$stale"; done
fi

exec "$exe" "$@"
