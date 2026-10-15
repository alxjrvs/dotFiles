# MAIA

The desktop PC: Ryzen 7 7800X3D, Radeon AI PRO R9700 (gfx1201), ASUS ProArt B850, and a BenQ
GW3290QT shared with laptops through a CalDigit TS4. Ubuntu 26.04 is the main OS and Windows 11
the games side. The same chezmoi source sets up both: `.chezmoiignore` decides what lands where,
and the hardware steps only run when the hostname is `maia`.

None of this has run on the real machine yet. It renders and lints in CI. The first boot is the test.

## Before the first boot

In the BIOS, turn on **SVM** (AMD virtualization), which ASUS boards ship with off. Cowork needs it.

## Ubuntu: one command

Name the computer `maia` in the installer. Keep the dock plugged in, since it carries the keyboard
anyway. Then, from a terminal:

```bash
sh -c "$(wget -qO- get.chezmoi.io)" -- -b ~/.local/bin init --apply --use-builtin-git=true alxjrvs/dotFiles
```

`init` asks the [day-one values and flags](#day-one-values-and-flags) once. Pressing Enter on each
is fine: the dock and the USB-C input are measured, and every flag stays off. The apply asks for your
password once, for apt. It provisions everything it can. What only you can do:

1. Log out and back in. zsh becomes the login shell, and the kvm, render, video and i2c groups
   take effect.
2. Sign in to 1Password. Under Settings › Developer, turn on Use the SSH Agent and Integrate with
   1Password CLI.
3. Run `gh auth login --scopes workflow && chezmoi apply`. Then sign in to Claude: run `claude`
   once, and open Claude desktop once.

**Dry run.** Run `chezmoi init alxjrvs/dotFiles` (without `--apply`), then
`chezmoi apply --dry-run --verbose`. That prints every file and every setup script, rendered with
your values, and changes nothing. After that, `chezmoi apply` does what it showed. The maia
commands each take `--dry-run` too.

What the apply does on Ubuntu, any host (`run_once_after_05-ubuntu-upgrade.sh`,
`run_onchange_after_10-ubuntu.sh`):

- Runs `apt full-upgrade` once, on the first apply only.
- Installs zsh, git, jq, ripgrep, fd (Ubuntu's `fd-find`, linked as `fd`), starship, Fira Code,
  OBS and wl-clipboard.
- **Claude:** adds Anthropic's signed apt repos and checks the key fingerprint, then installs
  `claude-code` and `claude-desktop`. Cowork's QEMU comes along as recommended packages.
  `vhost_vsock` loads at boot, you join `kvm`, and Claude Code's sandbox gets bubblewrap, socat
  and Ubuntu's AppArmor profile for it. `~/.claude/` is the shared config, so its plugins install
  themselves in the first session.
- Adds the official repos for 1Password and its CLI, the GitHub CLI and VS Code.
- Reuses the shared dotfiles: zsh, git (signing through 1Password's Linux agent), ssh, starship
  and mise runtimes. On Linux, `open`, `pbcopy` and `pbpaste` map to `xdg-open`, `wl-copy` and
  `wl-paste`.

On `maia` (`run_onchange_after_60-maia.sh.tmpl`):

- **Gaming:** adds i386, enables multiverse, and installs `steam-installer` and `steam-devices`
  (Valve's .deb, not the Snap).
- **Local AI:** adds you to `render` and `video`, installs `rocminfo`, and installs Ollama with its
  official installer.
- **GPU noise:** installs LACT 0.10.1 (Ubuntu 26.04 build, SHA-256 pinned), enables `lactd`, and
  runs `maia-gpu-tune`. That sets the power cap and adds the fan curve once overdrive is on (see
  [LACT](#lact-the-fan-curve-and-power-cap)).
- **Desk:** installs ddcutil, loads `i2c-dev` at boot, adds the `i2c` group and its udev rule, and
  installs display-switch 1.4.1 (pinned). Then it runs `maia-desk`, which measures the dock and the
  monitor's USB-C input, writes display-switch's config, and starts its user service.
- **Data drive:** runs `maia-data-mount` when `dataUuid` is set.
- **Commands** in `~/.local/bin`: `maia-gpu-check`, `maia-gpu-tune`, `maia-desk` and
  `maia-data-mount`. Each is safe to run again by hand.

Nothing partitions, formats, or touches GRUB, BIOS or a DKMS driver unless its flag is on. Every
step prints what it's about to do. A re-run skips whatever is already in place.

**Not installed on Ubuntu,** because there's no clean official apt route:

- Discord, Slack and Tuple: vendor .debs only
- Ghostty: no official Ubuntu package
- Chrome, gcloud and ngrok: vendor repos I haven't verified for 26.04
- Docker: OrbStack's job on the Mac
- LM Studio: an AppImage, with no repo to script
- Raycast and noTunes: macOS only

The nightly `mise run upkeep` is macOS-only too. On Ubuntu, Software Updater keeps apt packages
current, and you run `mise upgrade` by hand.

## Windows: one command

Rename the PC first (`Rename-Computer MAIA`, then reboot). Then, in PowerShell:

```powershell
winget install --id twpayne.chezmoi --exact; chezmoi init --apply --use-builtin-git=true alxjrvs/dotFiles
```

If `chezmoi` isn't on PATH yet, open a new PowerShell. At `init`, enter the `dockUsb` and
`usbcInput` that `maia-desk` printed on Ubuntu, since Windows can't measure them.
`run_onchange_after_10-windows.ps1.tmpl` then:

- uses winget to install Steam, Claude desktop, Claude Code, Git, the GitHub CLI, 1Password and its
  CLI, VS Code, ripgrep, fd and jq
- installs display-switch 1.4.1 (pinned) and adds it to the Startup folder once `dockUsb` is set

Windows gets only the git config and display-switch's config. chezmoi copies files rather than
symlinking them, so Developer Mode isn't needed. Claude Code keeps stock settings on Windows,
because the shared ones require a sandbox that native Windows doesn't have. zsh, ssh and mise
stay on the Mac and Linux.

- **AMD Software: Adrenalin** has no winget package. Download it from amd.com: **26.2.1 or later**
  (26.1.1 broke monitor control on this chip).
- Nothing here touches boot order, BitLocker or the Linux drives. **Windows updates can reset the
  boot order:** "ubuntu" must stay first in the BIOS boot list.

## Day-one values and flags

All of them live in one place: `[data.maia]` in `~/.config/chezmoi/chezmoi.toml` on that machine,
never in this repo. `chezmoi init` asks for each once and remembers it. To change one, edit that file
and run `chezmoi apply`; the step that uses it re-runs. To set them without prompts, pass
`--promptString "<question>=<value>"` or `--promptBool "<question>=true"` to `init`.

| key | default | what | if left empty |
|---|---|---|---|
| `dockUsb` | empty | the TS4's USB id, vendor:product | measured by `maia-desk`: the first device `lsusb -d 2188:` lists |
| `usbcInput` | empty | the BenQ's USB-C input code | measured by `maia-desk` over DDC, when exactly one input (feature 60) is neither DisplayPort-1 nor HDMI; otherwise it lists the candidates (likely `0x10` or `0x1b`) |
| `dataUuid` | empty | the 2TB's ext4 partition UUID (`lsblk -f`) | the data drive waits; run `maia-data-mount UUID` by hand later |
| `powerCap` | 230 | GPU power cap in watts | |
| `rocm` | false | `apt install rocm` from Ubuntu's archive (several GB) | |
| `kisakMesa` | false | ppa:kisak/kisak-mesa and an upgrade to its Mesa, for game issues (only if the PPA publishes for 26.04) | |
| `ppfeaturemask` | false | `amdgpu.ppfeaturemask=0xffffffff` via a GRUB drop-in, then `update-grub`. LACT needs it for a custom fan curve on RDNA3 and later | |

A value you set always wins over a measured one. The GRUB flag writes
`/etc/default/grub.d/99-maia-ppfeaturemask.cfg`. To undo it, delete that file and run
`sudo update-grub`.

## The data drive

Split the 2TB first: mostly ext4, plus about 250GB of NTFS for Windows-only games. Nothing here
partitions or formats. Then set `dataUuid` and apply, or run it by hand:

```bash
lsblk -f                                  # the ext4 partition's UUID
maia-data-mount --dry-run <UUID>          # prints each step
maia-data-mount <UUID>
```

It adds a `nofail` fstab entry for `/data`, backing up the old fstab to `/etc/fstab.pre-maia`
first, and mounts it. It creates `/data/models` and `/data/steam`, owned by you, and points Ollama
at `/data/models` with a drop-in that waits for the mount. A partition that isn't ext4 is refused.
Then add `/data/steam` as a library under Steam › Settings › Storage.

## LACT: the fan curve and power cap

`~/.config/maia/lact.yaml` is the starting point to tune by ear: a 230 W cap (from `powerCap`) and
a five-point curve that keeps the blower low until the card is warm. `maia-gpu-tune` applies it
through LACT, under the GPU's real id.

- **Power cap:** set on every run, with `lact cli power-limit set`.
- **Fan curve:** written into `/etc/lact/config.yaml` once, while the GPU has no curve yet, so a
  curve you later tune in LACT's window stays. It needs overdrive: turn on `ppfeaturemask`, apply,
  reboot, then run `maia-gpu-tune`.

## Desk: the monitor follows the dock

display-switch watches for the TS4. When the dock connects, it switches the BenQ to DisplayPort
(`0x0f`); when it disconnects, to USB-C. On Linux, `maia-desk` writes
`~/.config/display-switch/display-switch.ini`. If the dock wasn't plugged in during setup, plug it
in and run `maia-desk`. On Windows, chezmoi renders `%APPDATA%\display-switch\display-switch.ini`
from `[data.maia]`. The Linux log is `~/.local/share/display-switch/display-switch.log`.

**Fallback, documented only:** if display-switch misbehaves, a udev rule can run ddcutil instead:
`ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2188", RUN+="/usr/bin/ddcutil setvcp 60 0x0f"`,
with a `remove` twin that sets the USB-C code. udev runs it as root, with no retries and no
debounce, which is why it isn't the default.

## First-boot checklist

- [ ] `mokutil --sb-state` says `SecureBoot enabled`
- [ ] `maia-gpu-check`: `rocminfo` shows `gfx1201`, and `ollama ps` shows `100% GPU` with a model
      loaded (run `ollama run <model> hello` first)
- [ ] Steam launches a Proton game. Turn on Steam Play for all titles under Steam › Settings ›
      Compatibility; it's a GUI setting, so the setup can't do it.
- [ ] The monitor switches when the dock cable moves to a laptop and back. If it doesn't,
      `maia-desk --dry-run` shows what it measured.
- [ ] Claude desktop's Cowork tab opens (it needs SVM, kvm and vhost_vsock)
- [ ] Data partition: set `dataUuid` and apply
- [ ] Fan curve: turn on `ppfeaturemask`, reboot, run `maia-gpu-tune`, then listen and tune
- [ ] Windows: Adrenalin 26.2.1 or later, display-switch switches there too, and "ubuntu" is still
      first in the BIOS boot order after Windows updates
