# Route interactive Claude Code through its own app bundle, so a macOS update
# stops re-prompting for file access.
#
# macOS TCC keys a grant to the executable's absolute PATH, and the native
# installer stages every release at its own ~/.local/share/claude/versions/<ver>
# — so every update is a brand-new client and every "wants to access data from
# other apps" dialog comes back. The ClaudeCode.app bundle beside versions/ is
# Anthropic's own, and already holds the grants.
#
# A shell function, NOT a launcher at ~/.local/bin/claude: leaving that path to
# the installer keeps auto-update, version cleanup and `claude doctor` working,
# and keeps this out of the boot path of every script and launchd job, where a
# wrapper would fail closed into "no working claude".
#
# Two traps:
#   - It must NOT `exec`. Inside a function that replaces the shell itself, so
#     the terminal closes the moment Claude exits.
#   - An alias cannot do this: the bundle hardlink must be refreshed before
#     launch, and Claude Code only refreshes it when process.execPath is under
#     versions/ — which stops being true the moment anything sits in front.
#
# macOS only: TCC does not exist elsewhere, and `-ef` here is an inode test.
if [[ $OSTYPE == darwin* ]]; then
  claude() {
    local bin exe
    # Ask the installer what is current instead of re-deriving it by sorting
    # versions/ — this symlink is the answer it just wrote.
    bin=$(readlink -f ~/.local/bin/claude 2> /dev/null)
    exe=~/.local/share/claude/ClaudeCode.app/Contents/MacOS/claude
    if [[ -x $bin && -d ${exe:h} ]]; then
      # Same inode, not a copy: the bundle executable must BE the release, or
      # every update duplicates 317MB.
      [[ $exe -ef $bin ]] || { rm -f -- "$exe"; ln -- "$bin" "$exe"; } 2> /dev/null
      [[ -x $exe ]] && { "$exe" "$@"; return }
    fi
    # Any doubt at all — no bundle yet on a fresh machine, a changed install
    # layout, a failed link — falls through to the installer's own launcher.
    command claude "$@"
  }
fi
