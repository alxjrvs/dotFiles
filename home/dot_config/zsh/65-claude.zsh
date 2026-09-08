# Route interactive Claude Code through its own app bundle, so a macOS update
# stops re-prompting for file access.
#
# Why it happens. macOS TCC keys a file-access grant to the executable's
# absolute PATH — `csreq` is NULL on those rows, so the code hash is NOT pinned,
# only the path — and the native installer stages every release at its own
# ~/.local/share/claude/versions/<ver>. Every update is therefore a brand-new
# client and the whole set of "wants to access data from other apps" dialogs
# comes back. Nothing is misconfigured; the recommended install layout guarantees
# this. The ClaudeCode.app bundle beside versions/ is Anthropic's own (background
# sessions already re-exec through it, so it holds the grants); docs/DECISIONS.md
# has the measurement.
#
# Why a shell function and NOT a launcher at ~/.local/bin/claude. Leaving that
# path to the installer keeps auto-update and automatic version cleanup working,
# keeps `claude doctor` quiet, and keeps this out of the boot path of every
# script, hook and launchd job — a wrapper there fails closed into "no working
# claude", which is a far worse outcome than the dialog it removes. Interactive
# shells are also exactly the sessions that can show a dialog, so the narrower
# scope costs nothing real.
#
# Two traps worth keeping:
#   - It must NOT `exec`. Inside a function that replaces the shell itself, so
#     the terminal would close the moment Claude exits.
#   - An alias cannot do this at all — the bundle hardlink has to be refreshed
#     before launch, or it silently pins the machine to whatever version it last
#     held. Claude Code only refreshes it when process.execPath is under
#     versions/, which stops being true the moment anything sits in front.
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
