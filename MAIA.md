# MAIA

The desktop PC: Ryzen 7 7800X3D, Radeon AI PRO R9700 (gfx1201), ASUS ProArt B850, a BenQ
GW3290QT shared with laptops through a CalDigit TS4. Ubuntu 26.04 is the main OS and Windows 11
the games side. The same chezmoi source sets up both: `.chezmoiignore` decides what lands where,
and the hardware steps only run when the hostname is `maia`.

None of this has run on the real machine yet. It renders and lints in CI. The first boot is the test.

## Ubuntu: one command

Name the computer `maia` in the installer. Then, from a terminal:

```bash
sh -c "$(wget -qO- get.chezmoi.io)" -- -b ~/.local/bin init --apply --use-builtin-git=true alxjrvs/dotFiles
```

`init` asks the [day-one values and flags](#day-one-values-and-flags) once (Enter takes the default:
empty, 230, off). The apply asks for your password for apt. Then:

1. Log out and back in. zsh becomes the login shell, and the kvm, render, video and i2c groups
   take effect.
2. Sign in to 1Password. Under Settings › Developer, turn on Use the SSH Agent and Integrate with
   1Password CLI.
3. Run `gh auth login --scopes workflow && chezmoi apply`, then `claude` once to log in.

**Dry run.** `chezmoi init alxjrvs/dotFiles` (without `--apply`), then
`chezmoi apply --dry-run --verbose`. That prints every file and every setup script, rendered with
your values, and changes nothing. After that, `chezmoi apply` does what it showed.

What the apply does on Ubuntu, any host (`run_once_after_05-ubuntu-upgrade.sh`,
`run_onchange_after_10-ubuntu.sh`):

- runs `apt full-upgrade` once, on the first apply only
- installs zsh, git, jq, ripgrep, fd (Ubuntu's `fd-find`, linked as `fd`), starship, Fira Code,
  OBS and wl-clipboard
- adds the official signed apt repos for Claude Code and Claude desktop (key fingerprint checked),
  1Password and its CLI, the GitHub CLI and VS Code
- sets up Claude Code's sandbox, which `~/.claude/settings.json` requires: bubblewrap, socat, and
  the AppArmor profile Ubuntu needs for it
- adds you to `kvm` for Cowork
- reuses the shared dotfiles: zsh, git (signing through 1Password's Linux agent), ssh, starship,
  mise runtimes and the Claude config. On Linux, `open`, `pbcopy` and `pbpaste` map to `xdg-open`,
  `wl-copy` and `wl-paste`.

On `maia` (`run_onchange_after_60-maia.sh.tmpl`):

- **Gaming:** adds i386, enables multiverse, and installs `steam-installer` and `steam-devices`
  (Valve's .deb, not the Snap).
- **Local AI:** adds you to `render` and `video`, installs `rocminfo`, and installs Ollama with its
  official installer.
- **GPU noise:** installs LACT 0.10.1 (Ubuntu 26.04 build, SHA-256 pinned) and enables `lactd`.
- **Desk:** installs ddcutil, loads `i2c-dev` at boot, adds the `i2c` group and its udev rule, and
  installs display-switch 1.4.1 (pinned) as a systemd user service.
- **Commands:** `maia-gpu-check` and `maia-data-mount` in `~/.local/bin`.

Nothing partitions, formats, or touches GRUB, BIOS or a DKMS driver unless its flag is on. Every
step prints what it is about to do. A re-run skips whatever is already in place.

**Not installed on Ubuntu,** because there's no clean official apt route: Discord, Slack and Tuple
(vendor .debs only), Ghostty (no official Ubuntu package), Chrome, gcloud and ngrok (vendor repos I
haven't verified for 26.04), Docker (OrbStack's job on the Mac), LM Studio (an AppImage, with no repo to script), and Raycast and noTunes (macOS
only). Nightly `mise run upkeep` is macOS-only too. On Ubuntu, Software Updater keeps apt packages
current and `mise upgrade` is run by hand.

## Windows: one command

Rename the PC first (`Rename-Computer MAIA`, then reboot). Then, in PowerShell:

```powershell
winget install --id twpayne.chezmoi --exact; chezmoi init --apply --use-builtin-git=true alxjrvs/dotFiles
```

(Open a new PowerShell if `chezmoi` isn't on PATH yet.) `run_onchange_after_10-windows.ps1.tmpl`:

- winget installs Steam, Git, the GitHub CLI, 1Password and its CLI, VS Code, ripgrep, fd and jq
- installs display-switch 1.4.1 (pinned) and adds it to the Startup folder once `maia.dockUsb` is
  set

Windows only gets the git config and the display-switch config. chezmoi copies files rather than
symlinking them, so Developer Mode isn't needed. zsh, ssh, mise and Claude Code stay on the Mac and
Linux.

- **AMD Software: Adrenalin** has no winget package. Download it from amd.com: **26.2.1 or later**
  (26.1.1 broke monitor control on this chip).
- Nothing here touches boot order, BitLocker or the Linux drives. **Windows updates can reset the
  boot order:** "ubuntu" must stay first in the BIOS boot list.

## Day-one values and flags

All of them live in one place: `[data.maia]` in `~/.config/chezmoi/chezmoi.toml` on that machine,
never in this repo. `chezmoi init` asks for each once and remembers it. To change one, edit that file
and run `chezmoi apply`; the step that uses it re-runs. To set them non-interactively, pass
`--promptString "<question>=<value>"` or `--promptBool "<question>=true"` to `init`.

| key | default | what | how to measure |
|---|---|---|---|
| `dockUsb` | empty | the TS4's USB id, vendor:product | `lsusb -d 2188:` with the dock plugged in; any device it lists |
| `usbcInput` | empty | the BenQ's USB-C input code | `ddcutil capabilities`, feature 60; likely `0x10` or `0x1b` |
| `powerCap` | 230 | GPU power cap in watts, for LACT | tune by ear |
| `rocm` | false | `apt install rocm` from Ubuntu's archive (several GB) | |
| `kisakMesa` | false | ppa:kisak/kisak-mesa and an upgrade to its Mesa, for game issues (only if the PPA publishes for 26.04) | |
| `ppfeaturemask` | false | `amdgpu.ppfeaturemask=0xffffffff` via a GRUB drop-in, then `update-grub`. LACT needs it for a custom fan curve on RDNA3+ | |

Until `dockUsb` is set, display-switch stays installed but switched off. Until `usbcInput` is set,
unplugging the dock changes nothing.

The GRUB flag writes `/etc/default/grub.d/99-maia-ppfeaturemask.cfg`. To undo it, delete that file
and run `sudo update-grub`.

**The data partition's UUID** isn't stored anywhere. Once the 2TB is split (mostly ext4, plus about
250GB NTFS for Windows-only games), run:

```bash
lsblk -f                                  # the ext4 partition's UUID
maia-data-mount --dry-run <UUID>          # prints each step
maia-data-mount <UUID>
```

It adds a `nofail` fstab entry for `/data` (backing up to `/etc/fstab.pre-maia` first) and mounts
it. It creates `/data/models` and `/data/steam`, owned by you, and points Ollama at `/data/models`
with a drop-in that waits for the mount. It never formats: a partition that isn't ext4 is refused.
Then add `/data/steam` as a library under Steam › Settings › Storage.

## LACT: the fan curve and power cap

LACT keys each GPU by its PCI ids and slot, which exist only once the card is in, so its config
can't be written ahead of time. `~/.config/maia/lact.yaml` holds the starting point to tune by ear:
a 230 W cap (from `powerCap`) and a five-point curve that keeps the blower low until the card is
warm. On day one:

1. Turn on `ppfeaturemask` (above), apply, and reboot.
2. Run `lact cli list-gpus` to get the GPU's id.
3. Under `gpus:` in `/etc/lact/config.yaml`, add the block from `~/.config/maia/lact.yaml` with
   `GPU_ID` replaced by that id. Or enter the same values in LACT's window. lactd picks the change
   up without a restart.

## Desk: the monitor follows the dock

display-switch watches for the TS4 (`dockUsb`). When the dock connects, it switches the BenQ to
DisplayPort (`0x0f`); when it disconnects, to USB-C (`usbcInput`). The config is
`~/.config/display-switch/display-switch.ini` on Linux and
`%APPDATA%\display-switch\display-switch.ini` on Windows, rendered from the same template. The
Linux log is `~/.local/share/display-switch/display-switch.log`.

**Fallback, documented only:** if display-switch misbehaves, a udev rule can run ddcutil instead:
`ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2188", RUN+="/usr/bin/ddcutil setvcp 60 0x0f"`,
with a `remove` twin that sets the USB-C code. udev runs it as root, with no retries and no
debounce, which is why it isn't the default.

## First-boot checklist

- [ ] `mokutil --sb-state` says `SecureBoot enabled`
- [ ] `maia-gpu-check`: `rocminfo` shows `gfx1201`, and `ollama ps` shows `100% GPU` with a model
      loaded (`ollama run <model> hello` first)
- [ ] Steam launches a Proton game. Turn on Steam Play for all titles under Steam › Settings ›
      Compatibility; that's a GUI setting, so the setup can't do it.
- [ ] Measure `dockUsb` and `usbcInput`, set them, and apply. Then the monitor switches when the
      dock cable moves to a laptop and back.
- [ ] Find the data partition's UUID and run `maia-data-mount`
- [ ] LACT: apply the fan curve and power cap, and listen
- [ ] Windows: Adrenalin 26.2.1 or later, display-switch switches there too, and "ubuntu" is still
      first in the BIOS boot order after Windows updates
