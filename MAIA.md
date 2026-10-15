# MAIA

The desktop PC: Ryzen 7 7800X3D, Radeon AI PRO R9700 (gfx1201), ASUS ProArt B850, and a BenQ
GW3290QT shared with laptops through a CalDigit TS4. Ubuntu 26.04 is the main OS and Windows 11
the games side. The same chezmoi source sets up both: `.chezmoiignore` decides what lands where,
and the hardware steps only run when the hostname is `maia`.

None of this has run on the real machine yet. It renders and lints in CI. The first boot is the test.

## Before the first boot

In the BIOS:

- Turn on **SVM Mode** (Advanced › CPU Configuration). ASUS ships it off, and Cowork needs it.
- Leave **CPPC** on, so Linux drives the CPU with amd-pstate.
- Keep **Secure Boot** on.

Plug the dock into a rear 10Gbps USB-C port.

## Compatibility

Researched on 2026-10-15, before the hardware exists. `maia-check` confirms each of these on the
machine itself.

| Part | On Ubuntu 26.04 (kernel 7.0, Mesa 26.0.3) | On Windows 11 |
|---|---|---|
| R9700 (Navi 48, gfx1201) | In-kernel `amdgpu` (6.14+) and RADV (Mesa 25+): stock is enough, so Secure Boot needs no MOK. Never install `amdgpu-dkms` or AMD's `amdgpu-install`. | Adrenalin from amd.com |
| ROCm on gfx1201 | Supported upstream since ROCm 6.4.2. Ubuntu's archive has 7.1; whether that build includes gfx1201 is unverified, and the `rocm` flag tests it. Ollama ships its own ROCm 7 and lists the R9700. | Ollama's Windows ROCm list stops at RX 7000; its Vulkan backend is the route there |
| Ryzen 7 7800X3D | `amd-pstate` (needs CPPC) and `k10temp`. Single CCD, so no V-Cache driver needed | AMD chipset driver from amd.com |
| 2x 5GbE (Realtek RTL8126) | `r8169` | ASUS support page |
| Wi-Fi 7 (Realtek RTL8922AE) | `rtw89_8922ae` | ASUS support page |
| Bluetooth (RTL8922A over USB) | `btusb` and `btrtl` | ASUS support page |
| Audio (Realtek ALC1220P) | `snd_hda_intel` | Windows Update |
| Board sensors (fans, voltages) | `asus_ec_sensors` doesn't list this board, and `nct6775` may not load. Cosmetic: CPU and GPU temperatures don't depend on it | ASUS Armoury Crate |
| CalDigit TS4 over 10Gbps USB-C | USB, audio and card readers work. **Its 2.5GbE port doesn't** (Thunderbolt hosts only), and it can't charge the PC. Neither matters here | Same |
| BenQ GW3290QT | DDC/CI through `ddcutil`. The USB-C input code isn't published, so `maia-desk` measures it | display-switch reads the measured code |
| Steam | `steam-installer` from multiverse, with 32-bit Mesa installed by name. Proton runs on RDNA4 with Mesa 25+ | Valve.Steam |

On Windows, install AMD's chipset driver first, then the Realtek LAN, Wi-Fi and Bluetooth drivers
from the ASUS support page for the ProArt B850-Creator WiFi NEO.

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
- **Local AI:** adds you, and Ollama's service user, to `render` and `video`. Installs `rocminfo` and
  `vulkan-tools`, and installs Ollama with its official installer, which adds no kernel module.
- **Desk:** installs ddcutil, loads `i2c-dev` at boot, adds the `i2c` group and its udev rule, and
  installs display-switch 1.4.1 (pinned). Then it runs `maia-desk`, which measures the dock and the
  monitor's USB-C input, writes display-switch's config, and starts its user service.
- **Data drive:** runs `maia-data-mount` when `dataUuid` is set.
- **Commands** in `~/.local/bin`: `maia-check` (read-only), `maia-desk` and `maia-data-mount`. Each
  is safe to run again by hand.

Nothing partitions, formats, or touches GRUB, BIOS or a DKMS driver. Every
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
  (26.1.1 broke monitor control on this chip). AMD's R9700 page offers 26.8.1 as of 2026-10.
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
| `rocm` | false | `apt install rocm` from Ubuntu's archive (several GB) | |
| `kisakMesa` | false | ppa:kisak/kisak-mesa and an upgrade to its Mesa, for game issues (only if the PPA publishes for 26.04) | |

A value you set always wins over a measured one.

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

- [ ] `maia-check` passes. It covers Secure Boot, SVM and Cowork, amdgpu and RADV on gfx1201, ROCm,
      Ollama and its groups, both NICs, Wi-Fi, Bluetooth, the dock, DDC to the BenQ and `/data`.
- [ ] `ollama run <model> hello`, then `ollama ps` shows `100% GPU`
- [ ] Steam launches a Proton game. Turn on Steam Play for all titles under Steam › Settings ›
      Compatibility; it's a GUI setting, so the setup can't do it.
- [ ] The monitor switches when the dock cable moves to a laptop and back. If it doesn't,
      `maia-desk --dry-run` shows what it measured.
- [ ] Claude desktop's Cowork tab opens (it needs SVM, kvm and vhost_vsock)
- [ ] Data partition: set `dataUuid` and apply
- [ ] Windows: Adrenalin 26.2.1 or later, display-switch switches there too, and "ubuntu" is still
      first in the BIOS boot order after Windows updates
