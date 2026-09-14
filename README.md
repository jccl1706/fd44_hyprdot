<div align="center">

# fd44_hyprdot

**Fedora 44 · Hyprland · Quickshell** — a complete desktop for the Framework 13 (AMD),
including the installer that builds the machine from bare metal.

<sub>
no display manager &nbsp;·&nbsp; no panel toolkit &nbsp;·&nbsp; no notification daemon &nbsp;·&nbsp; the shell is QML
</sub>

<p>
<img alt="Fedora 44" src="https://img.shields.io/badge/Fedora-44-51A2DA?style=for-the-badge&logo=fedora&logoColor=white">
<img alt="Hyprland 0.56" src="https://img.shields.io/badge/Hyprland-0.56-58E1FF?style=for-the-badge&logo=hyprland&logoColor=black">
<img alt="Quickshell 0.3" src="https://img.shields.io/badge/Quickshell-0.3-1D99F3?style=for-the-badge&logo=qt&logoColor=white">
<img alt="Framework 13 AMD" src="https://img.shields.io/badge/Framework%2013-AMD-FF5B21?style=for-the-badge&logo=framework&logoColor=white">
</p>

</div>

---

## Themes

Two palettes, switched live with `SUPER+T` or the sun/moon beside the clock.
The bar, frame, launcher, power menu, lock screen, kitty, GTK apps and Chromium
all follow — nothing restarts.

<table>
<tr>
<td width="50%" valign="top">
<img src="docs/theme-dark.png" alt="dark theme">
<p align="center"><sub><b>dark</b> — Catppuccin Mocha</sub></p>
</td>
<td width="50%" valign="top">
<img src="docs/theme-cream.png" alt="cream theme">
<p align="center"><sub><b>cream</b> — Rosé Pine Dawn</sub></p>
</td>
</tr>
</table>

A theme is one file of 47 key/value pairs in [`themes/`](themes/). `bin/theme.sh`
reads it and fans the values out to five consumers, each with its own idea of
what a config file is:

| target | mechanism | live? |
|---|---|---|
| quickshell | `Theme.qml` watches a generated palette with `FileView` | yes |
| kitty | generated `theme.conf` + `SIGUSR1` | yes |
| GTK apps | `gsettings` (colour scheme, icon theme), republished by xdg-desktop-portal | yes |
| Hyprland | `hyprctl eval` — **not** `keyword`, which the Lua parser refuses | yes |
| Chromium | `BrowserThemeColor` policy, written by a root service from a validated request, + `--refresh-platform-policy` | yes |
| hyprlock | generated colour variables it `source`s | next lock |

Adding a third theme means adding a file. Nothing else changes.

**Icons** are [Reversal](https://github.com/yeyushengfan258/Reversal-icon-theme)
(GPL-3.0): grey folders on dark, purple on cream, named by each theme's
`icon_theme` key, and the launcher's app icons too. It is opt-in - the desktop
is complete without it, and until it is installed GTK apps keep Adwaita's icons:

```sh
bin/icon-theme.sh            # ~275 MB on disk in ~/.local/share/icons, no root
bin/icon-theme.sh --status   # what the themes want vs what is installed
bin/icon-theme.sh --remove
```

It installs the colour sets the theme files name, from a pinned upstream
commit, so changing a theme's `icon_theme` and running it again is the whole
job of switching colours.

**Chromium** reads policy only from `/etc`, and that directory stays root's: a
theme switch writes just a colour and light/dark to `~/.local/state`, and a small
sandboxed root service checks it is exactly that and writes the one policy file.
Nothing running as you can set any other browser policy. The installer sets this
up; on a machine installed before it existed, run once:

```sh
sudo bin/chromium-policy-setup.sh            # --remove takes it out again
```

## What it gives you

- **Bar** — workspaces, clock, theme toggle, and an OSD that slides out of the
  left pill for volume and brightness
- **Frame** — a 4px border drawn around the whole screen, with concave fillets
  where the panels meet it
- **Launcher** (`SUPER+Space`) — rises out of the bottom frame, fuzzy app search
- **Wallpaper picker** (`SUPER+,`) — a coverflow strip of sheared tiles, with a
  crossfade when a wallpaper is applied
- **Power menu** (`SUPER+M` or the physical power button) — icon-only circles;
  log out, restart and shut down arm on the first press and fire on the second
- **Lock screen** — themed hyprlock, with battery
- **Media keys** — quickshell speaks MPRIS directly, so a media key spawns no
  process at all

## Install

The installer builds the whole machine: Btrfs + systemd-boot, optional LUKS,
Hyprland, quickshell, autologin, Plymouth. It asks for a dotfiles git URL —
give it this repo and the result is this desktop, not a generic one.

```sh
# from a Fedora Workstation live ISO
curl -O https://raw.githubusercontent.com/jccl1706/fd44_hyprdot/master/install/install_fedora_v1_11.sh
chmod +x install_fedora_v1_11.sh

./install_fedora_v1_11.sh --check-repos   # resolve every package name, no root
sudo ./install_fedora_v1_11.sh --dry-run  # print every command, change nothing
sudo ./install_fedora_v1_11.sh            # the real thing
```

It finishes with a verification pass — boot entries, fstab, autologin, the
font, the policy directory, the absence of packages that install themselves.
Twenty-six always run; up to eight more depend on the choices made — LUKS
encryption and disk swap add two each, zram two, a laptop one
(`powerprofilesctl`), and Chromium as the browser one (its policy directory).

> **The account ships with the password `changeme`.** This is a public repo, so
> assume everyone knows it. That is safe only because `~/.bash_profile` refuses
> to start a session until the password has been changed. The password is
> deliberately **not** expired: `agetty --autologin` runs `login -f`, and PAM
> rejects an expired password on that path rather than prompting, which leaves
> the machine in a getty respawn loop that never reaches a desktop.

### Testing it without hardware

```sh
# 36 packages, ~162 MB. The two -x skip weak dependencies with no use here:
# an Intel QuickAssist daemon and a UEFI shell.
sudo dnf install -x qatlib-service -x edk2-shell-x64 \
                 qemu-system-x86-core qemu-img edk2-ovmf qemu-ui-gtk \
                 qemu-device-display-virtio-gpu qemu-device-display-virtio-vga-gl \
                 qemu-device-display-virtio-gpu-gl virglrenderer

install/vm-test.sh /path/to/Fedora-Workstation-Live-*.iso
```

Works on either machine (both have AMD-V and a GPU virgl can use). Serves this
directory over HTTP so the guest can `curl` the installer at `10.0.2.2:8000`,
and forwards host port 2222 to the guest's ssh. The target disk is `/dev/vda`.
`--reboot` boots the installed disk; `--clean` throws it away.

A full install with no questions to answer, inside the VM:

```sh
curl -O http://10.0.2.2:8000/install_fedora_v1_11.sh && chmod +x install_fedora_v1_11.sh
sudo ./install_fedora_v1_11.sh --unattended --yes --desktop --disk /dev/vda \
     --dotfiles https://github.com/jccl1706/fd44_hyprdot
```

`--desktop` matters in a VM even for testing laptop changes: it turns off
encryption (the LUKS passphrase would be prompted for mid-install) and the 32G
swap partition, which a 40G test disk cannot spare.

hyprpaper cannot start on virtio-gpu either, so every VM run also exercises the
swaybg fallback.

### On a machine the installer did not build

`~/.config/hypr`, `~/.config/quickshell`, `~/.config/kitty` and
`~/.config/wireplumber` are **symlinks** into this checkout, so edits are live
and there is nothing to keep in sync.

```sh
git clone https://github.com/jccl1706/fd44_hyprdot ~/Work/fd44_hyprdot
cd ~/Work/fd44_hyprdot

for d in hypr quickshell kitty wireplumber; do ln -s "$PWD/$d" ~/.config/$d; done
systemctl --user restart wireplumber   # picks up wireplumber/ rules

mkdir -p ~/.config/systemd/user
ln -s "$PWD/systemd/power-mode.service" ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now power-mode.service

sudo dnf install rsms-inter-vf-fonts jetbrains-mono-fonts
sudo bin/install-nerd-font.sh        # installs the copy committed in fonts/
bin/theme.sh restore                 # generate the palette files
```

## Keybindings

| Key | Action |
|---|---|
| `SUPER+Return` | terminal (kitty) |
| `SUPER+B` / `+E` | browser / file manager |
| `SUPER+Space` | app launcher |
| `SUPER+,` | wallpaper picker |
| `SUPER+T` | toggle theme |
| `SUPER+M` | power menu (also the physical power button) |
| `SUPER+W` / `+F` / `+V` / `+P` | close / fullscreen / float / pseudo-tile |
| `SUPER+J` | cycle column width |
| `SUPER+[` / `+]` | consume / expel a window from its column |
| `SUPER+A` | fit all — zoom out to the whole strip |
| `SUPER+arrows` | move focus (`+SHIFT` moves the window) |
| `SUPER+1..0` | focus workspace (`+SHIFT` sends the window) |
| `SUPER+Tab` | next workspace (`+SHIFT` previous) |
| `SUPER+S` | scratchpad (`+SHIFT` send) |
| ``SUPER+` `` | btop, floating, in its own scratchpad (needs `sudo dnf install btop`) |
| `SUPER+Escape` | passthrough — hand every key to the focused window, e.g. a VM |
| `Print` | screenshot to clipboard |
| `SUPER+CTRL+P` | screenshot region to `~/Pictures/` |

Volume, brightness and media keys are bound with `locked = true`, so they keep
working on the lock screen.

> `SUPER+Escape` is a submap. While it is active **no other bind exists** — that
> is the point — so a stuck passthrough looks exactly like a broken keyboard.
> `hyprctl submap` says which is active; the same key gets you out.

## Layout

```
hypr/            Hyprland config, in Lua (0.56+)
  hyprland.lua     entry point; requires the modules below
  monitors · look · input · binds · rules · autostart
  hypridle.conf    idle → lock → screen off, AC/battery aware
  hyprlock.conf    lock screen; colours come from the theme

quickshell/      the shell itself, QML
  Theme.qml        SINGLETON — every colour, font and metric
  shell.qml        entry point; one Bar per monitor, IPC, global shortcuts
  Bar · Frame · Launcher · WallpaperPicker · PowerMenu · Osd · Media
  AudioButton · AudioPanel       volume and output/input selection
  NetworkButton · NetworkPanel   Wi-Fi and Ethernet
  CaffeineButton · Caffeine      coffee cup: stay awake - no idle lock, screen-off
                                 or suspend while on (lid close still suspends)
  DropPanel        the slide-down card both panels are built on
  BarLayout · BarZone   movable plugins: press and hold a glyph, drag it along
                   the bar, drop it; its panel then opens under it. Saved per
                   machine in ~/.local/state/fd44-hyprdot/bar-layout.json;
                   `qs ipc call bar resetLayout` puts everything back

themes/          dark.conf, cream.conf — one file per palette
fonts/           Symbols Nerd Font, vendored (MIT)
wallpapers/      resized, webp
bin/             theme.sh · wallpaper.sh · power-mode.sh · idle-action.sh · icon-theme.sh
                 qs-restart.sh — restart quickshell safely (one instance, verified)
                 lock-at-login.sh — locks at login unless the disk is encrypted
                 chrome-theme.sh · chromium-policy-setup.sh — browser colours, root-written
                 gaming-setup.sh — opt-in, not run by the installer
install/         the installer, and vm-test.sh
cooling/         CoolerControl backup of the desktop's fan curves (reviewed, no credentials)
wireplumber/     audio rules — the EVO4 uses software volume (matches only that device)
```

## Gaming

Not part of the installer, on purpose: Steam is a feature set one machine
wants, not something the base install is broken without. It lives in its own
opt-in script, run by hand on the machine that wants it.

```sh
sudo bin/gaming-setup.sh --dry-run     # print every command, change nothing
sudo bin/gaming-setup.sh               # RPM Fusion, Steam, gamemode, gamescope
sudo bin/gaming-setup.sh --proton-ge   # and the latest GE-Proton
```

It ends with a verification pass that **runs** the tools rather than asking rpm
whether they are installed — which Vulkan driver is actually loaded, whether
the 32-bit ICD is there, whether `gamemoded` starts. It also marks the Steam
library `nodatacow` before Steam's first run, which is the only moment Btrfs
allows it.

It also caps every game run through Proton at 120 fps, inside the translation
layer itself (`VKD3D_FRAME_RATE` for DX12, `DXVK_CONFIG` for DX9/11), from
`~/.config/uwsm/env.d/gaming`. That file is written into the gaming machine's
home, not this repo — the laptop shares the repo and does not game.

It also limits the GPU to 250 W, at boot and after every resume, through a
small systemd unit. With the GPU maxed out that took its own fans from about
2,000 rpm to 1,650 and its junction from 93 °C to 88 °C median, measured over
two long ARC Raiders sessions.

## Cooling

Also opt-in, and also specific to one machine's hardware: every fan on the
gaming desktop hangs off an Aquacomputer Quadro, which runs them at fixed
speeds until something drives it. `bin/cooling-setup.sh` installs
CoolerControl's daemon from its COPR and starts it.

```sh
sudo bin/cooling-setup.sh --dry-run
sudo bin/cooling-setup.sh                   # fan curves for the Quadro
sudo bin/cooling-setup.sh --gpu-overdrive   # also the GPU's own fan curve (reboot)
```

The daemon serves CoolerControl's full UI at `http://127.0.0.1:11987`, loopback
only, so the desktop app — which costs `qt6-qtwebengine`, 277 MB — is skipped.
`--gpu-overdrive` sets amdgpu's overdrive bit on the kernel command line rather
than in `/etc/modprobe.d`: amdgpu loads from the initramfs here, where a
modprobe option silently does nothing until the image is rebuilt.

`--restore-curves` restores the fan curves committed in
`cooling/coolercontrol-backup/` — made with `coolercontrold backup`, reviewed
before commit, no credentials (the daemon leaves `.passwd` and `.tokens` out).
It only restores onto the machine the backup came from: device IDs are hashes of
the hardware, so it refuses if the Quadro in the backup is not present, or if the
installed CoolerControl version differs.

## Rebuilding the desktop

How to take the gaming desktop (ASRock B650I, Ryzen 7 9700X, RX 9070 XT,
Aquacomputer Quadro) from a wiped disk back to exactly its current state.
Steps 1–4 are scripted and each ends with its own verification pass; step 5 is
the handful of things this repo deliberately does not do.

### 0. Before you wipe it

The installer erases the whole target disk, including `/home`. First:

1. **Push everything in this repo.** `git -C ~/Work/fd44_hyprdot status` should
   be clean and not ahead of `origin`.
2. **Refresh the fan-curve backup** if you changed curves in CoolerControl since
   the last commit. `--restore-curves` restores the newest directory in
   `cooling/coolercontrol-backup/`:

   ```sh
   sudo coolercontrold backup
   sudo coolercontrold list                        # note the newest TIMESTAMP
   sudo cp -r /etc/coolercontrol/backups/<TIMESTAMP> ~/Work/fd44_hyprdot/cooling/coolercontrol-backup/
   sudo chown -R "$USER": ~/Work/fd44_hyprdot/cooling/coolercontrol-backup
   ```

   Read the new files before committing — the repo is public. The daemon leaves
   passwords and tokens out unless `--include-secrets` is passed; check that
   `manifest.toml` says `includes_secrets = false`.
3. **Copy off anything that is not in the repo** and that you want back: the
   Steam library (`~/.local/share/Steam/steamapps`, optional — games can be
   re-downloaded), Claude Code's saved preferences
   (`~/.claude/projects/-home-jc-Work-fd44-hyprdot/memory/`), and personal files.

### 1. Install the base system

Boot a Fedora 44 Workstation live ISO, open a terminal, and fetch the installer:

```sh
curl -O https://raw.githubusercontent.com/jccl1706/fd44_hyprdot/master/install/install_fedora_v1_11.sh
chmod +x install_fedora_v1_11.sh
```

Then, in the order the installer recommends:

```sh
./install_fedora_v1_11.sh --check-repos     # every package name resolves; no root, no changes
./install_fedora_v1_11.sh --preflight       # report on this machine; no changes
sudo ./install_fedora_v1_11.sh --desktop --dotfiles https://github.com/jccl1706/fd44_hyprdot --dry-run
sudo ./install_fedora_v1_11.sh --desktop --dotfiles https://github.com/jccl1706/fd44_hyprdot
```

- **`--desktop`** sets the values for a machine with no battery and no lid:
  desktop machine type, no disk swap, no encryption, zram on (half of RAM, at
  most 8 GB).
- **`--dotfiles`** clones this repo to `~/Work/fd44_hyprdot`, links `hypr`,
  `quickshell` and `kitty` into `~/.config`, and enables the repo's systemd user
  units. Nothing needs linking by hand afterwards.
- The wizard still asks for the target disk — pick the NVMe — and the rest.
- It ends with its own verification pass. Reboot when it finishes.

### 2. First login

The machine autologins on the console, and the account still has the public
installer password `changeme`. Before starting Hyprland, `~/.bash_profile`
prints *"This account still has the installer default password. Set a real one
now - the desktop will not start until you do."* and runs `passwd` for you:

1. **Current password:** `changeme`
2. **New password**, then the same again to confirm.

If the change fails it simply asks again. Once it succeeds it prints *"Thank you.
Starting the desktop."* and Hyprland starts. It only happens once — it leaves a
marker at `~/.local/state/password-changed`.

### 3. Gaming — before opening Steam

Run this **before Steam's first launch**: it marks the Steam library
`nodatacow`, which Btrfs only allows while the directory is still empty.

```sh
cd ~/Work/fd44_hyprdot
sudo bin/gaming-setup.sh --dry-run     # print every command, change nothing
sudo bin/gaming-setup.sh
```

It restores: RPM Fusion, Steam with its 32-bit stack, GameMode and MangoHud
(64- and 32-bit), gamescope, the freeworld VA-API driver, the `nodatacow`
Steam library, the **120 fps cap** for Proton games, and the **250 W GPU power
limit** at boot and after every resume. Expect **31 checks** passed.

Then:

1. **Log out and back in** (`SUPER+M` → log out; autologin returns you) so the
   frame cap is loaded into the session. `echo $VKD3D_FRAME_RATE` should print
   `120`.
2. Open Steam, log in, and enable **Settings → Compatibility → Enable Steam Play
   for all other titles**.
3. Re-download games, or put the saved `steamapps` back while Steam is closed.

### 4. Cooling

```sh
cd ~/Work/fd44_hyprdot
sudo bin/cooling-setup.sh --restore-curves
```

This installs CoolerControl's daemon from its COPR, turns its liquidctl
integration off, and restores the committed fan setup: the CPU fan follows CPU
temperature; the exhausts and the side intake follow case air, with GPU edge
temperature as a safety net. Expect `restored <timestamp>` and **10 checks**
passed. The UI is at `http://127.0.0.1:11987` — it may ask you to log in or set
a password on first visit.

The restore **refuses** in two situations, on purpose:

- **CoolerControl was updated since the backup.** Compare
  `coolercontrold --version` with
  `grep daemon_version cooling/coolercontrol-backup/*/manifest.toml`. If you
  are happy to load an older backup into a newer daemon, restore by hand and
  check the curves in the UI:

  ```sh
  sudo systemctl stop coolercontrold
  sudo coolercontrold restore -y cooling/coolercontrol-backup/2026-09-13T10-41-19
  sudo systemctl start coolercontrold
  ```

- **The hardware changed** (a different Quadro, board or GPU). CoolerControl
  identifies devices by a hash of the hardware, so the saved assignments would
  point at devices that no longer exist. Recreate the curves in the UI instead,
  then refresh the backup as in step 0.

### 5. What the repo does not do

These were set up by hand on the current machine. None is needed for the desktop
itself.

**SSH from the laptop.** On the desktop:

```sh
sudo dnf install openssh-server
sudo systemctl enable --now sshd
```

Then on the laptop — the reinstall gives the desktop a new host key, so the old
one has to go first:

```sh
ssh-keygen -R <desktop-ip>
ssh-copy-id -i ~/.ssh/fd44-desktop.pub jc@<desktop-ip>
```

**Pushing to GitHub from the desktop:**

```sh
sudo dnf install gh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
git -C ~/Work/fd44_hyprdot config user.name  "Your Name"
git -C ~/Work/fd44_hyprdot config user.email "you@example.com"
```

The installer's clone is shallow (`--depth 1`); pushing works as it is, and
`git -C ~/Work/fd44_hyprdot fetch --unshallow` brings back the full history.

**Claude Code**, with the preferences saved in step 0:

```sh
curl -fsSL https://claude.ai/install.sh | bash
mkdir -p ~/.claude/projects/-home-jc-Work-fd44-hyprdot
cp -r <saved>/memory ~/.claude/projects/-home-jc-Work-fd44-hyprdot/
```

### 6. Check it is all back

```sh
echo $VKD3D_FRAME_RATE                              # 120
grep -H . /sys/class/hwmon/hwmon*/power1_cap        # the amdgpu one: 250000000
systemctl is-enabled fd44-gpu-power-limit.service   # enabled
hyprctl getoption misc:vrr                          # int: 2  (VRR for fullscreen)
systemctl is-active coolercontrold                  # active
```

Both setup scripts are safe to run again at any time — they skip what is already
done and end with the same verification passes.

## Power policy

| | Battery | AC |
|---|---|---|
| Power profile | `power-saver` | `balanced` |
| Brightness | 50% | 100% |
| Lock | 5:00 | 5:00 |
| Display off | 5:30 | 15:30 |
| Suspend | 15:00 | never (lid close only) |

Locking is not power-dependent; only the display-off timeout is. On AC the
machine stays awake so long downloads and ssh sessions are not cut off — closing
the lid still suspends, via logind's `HandleLidSwitchExternalPower`.

**Locking around autologin.** tty1 logs in by itself, so three things keep that
from being a way in:

- **At login**, `bin/lock-at-login.sh` locks the session straight away unless
  `/` is on an encrypted device. On a LUKS machine the boot passphrase already
  guards the autologin and it does nothing; on a `--desktop` install, switching
  the machine on lands on the lock screen, with everything started behind it.
  If it cannot tell, it locks.
- **When a session ends** — a crash included — `.bash_profile` logs out instead
  of leaving the autologin shell on tty1, and getty starts a fresh (locked)
  session. A compositor that dies in its first 15 seconds keeps the shell, so a
  broken config can still be fixed.
- **Before sleep**, hypridle's `inhibit_sleep = 3` holds the suspend until the
  session is actually locked, so a laptop cannot resume showing the desktop.

Two independent mechanisms. **Profile and brightness** come from
`bin/power-mode.sh`, driven by `udevadm monitor` on the `power_supply` subsystem
— event-driven, and entirely unprivileged. **Timeouts** live in `hypridle.conf`
with the logic in `bin/idle-action.sh`, where every listener is always armed and
the battery-scoped ones test the power source when they fire.

A machine with **no battery at all** counts as permanently on AC. That is not
pedantry: without it a desktop suspends itself on idle because it cannot find a
battery.

## Editing

```sh
hyprctl reload         # apply
hyprctl configerrors   # ALWAYS check - reload says "ok" even when a module failed
```

`hyprctl dispatch` evaluates **Lua**, not the old string syntax, which makes it
the fastest way to test a dispatcher before binding it:

```sh
hyprctl dispatch 'hl.dsp.window.fullscreen()'
hyprctl eval 'hl.config({ general = { gaps_in = 8 } })'   # for non-dispatchers
```

The authoritative Lua reference is the stub Hyprland ships:
`/usr/share/hypr/stubs/hl.meta.lua` — more complete than the wiki for the Lua
config format.

Quickshell watches its own files and reloads on save. `qs ipc show` lists the IPC
targets; `qs log` is the running instance's log.

When a reload is not enough — a `git pull` that adds new QML files, a change to
the `//@ pragma` line, a shell that looks stuck — restart it:

```sh
bin/qs-restart.sh      # kills every quickshell of yours, starts one, verifies it
```

Not `qs kill`: see Gotchas. The script works from a terminal and over ssh,
starts the shell inside Hyprland's session, and fails loudly unless exactly one
instance comes back with its config loaded. An open panel closes and the coffee
cup turns off.

## Gotchas

Each of these cost real time, and none produced an error message.

**Hyprland / hyprlang**

- `hyprctl dispatch dpms off` does **not** work on 0.56 — `dispatch` evaluates
  Lua, so the space-separated form is a parse error. It fails *silently* from
  hypridle's side. Nearly every example online uses the broken form.
- `hl.dsp.dpms()` **ignores its argument and toggles.** Two unguarded wake calls
  cancel out and leave the display off, both logging `ok`.
- `hyprctl keyword` is refused outright: *"keyword can't work with non-legacy
  parsers. Use eval."* Use `hyprctl eval` with a real `hl.config{}` call.
- Hyprlang `source` resolves against the **working directory**, not the file
  doing the sourcing, so a relative path silently loads nothing.
- Hyprlang has no statement separator — `;` is read as part of the value.

**Quickshell**

- `qs kill` can **segfault** on quickshell 0.3.1: the exit destroys the
  `GlobalShortcut` objects after their Wayland proxy is gone. The crash handler
  then relaunches the shell by itself, so `qs kill; qs -d` leaves **two**
  instances — stacked bars, every shortcut and IPC target doubled. Nothing on
  screen says so. `bin/qs-restart.sh` uses SIGKILL, which skips the teardown.
- A reload triggered mid-`git pull` can load `shell.qml` before a new file it
  references exists (`NetworkPanel is not a type`), and it does not retry when
  the file arrives. Restart after pulls that add QML files.

**Fonts**

- A weight appended to a family name does not resolve. `Inter Variable Bold`
  falls back to **Noto Sans**, silently. Use pango markup for weight.
- Fontconfig prefers `~/.local/share/fonts`, so a hand-placed copy can make a
  machine render perfectly while a fresh install of the same config has no
  glyphs at all. `bin/install-nerd-font.sh` removes the user copy rather than
  adding to it.

**Packaging**

- `nwg-panel` declares `Supplements: hyprland` — the *reverse* of Recommends —
  so it installs itself on every machine and is invisible to any "what pulled
  this in" query. It is excluded by name.
- `qt6-qtimageformats` is required by nothing in the Qt or quickshell stack, yet
  without it Qt cannot decode WebP and the wallpaper picker shows empty tiles —
  while swaybg, which decodes WebP itself, keeps the wallpaper looking fine. The
  laptop had it by accident; a fresh install did not. Now installed explicitly.
- `--setopt=install_weak_deps=False` is deliberately **never** used: this
  Framework's amdgpu and iwlwifi firmware both arrive only via Recommends, and
  stripping weak deps left the machine unable to load any firmware at all.

**Misc**

- In the test VM, `gl=on` plus `GDK_BACKEND=x11` paints a **black window** from
  the moment Hyprland starts — the guest is fine, qemu just never imports the
  GL scanout through XWayland. The firmware and the Plymouth splash draw
  normally, which makes it look like a boot failure. `vm-test.sh` now keeps the
  window on Wayland whenever 3D is on.
- The kernel truncates process names to 15 characters, so `pgrep -x
  chromium-browser` (16) matches nothing, silently.
- `brightnessctl` needs `-d amdgpu_bl1`, or it also picks up the ChromeOS EC LED
  classes and errors on them.
- Variables that systemd user services need belong in **uwsm's** environment,
  not `autostart.lua` — uwsm exports before Hyprland runs.
- Do not try to dismiss the Plymouth splash from Hyprland. Plymouth holds DRM
  master; masking `plymouth-quit*` deadlocks the boot.

## Not yet done

- No battery indicator or system tray in the bar yet.
- No notification daemon, so apps that send notifications get silence.
- Nothing indicates when the `passthrough` submap is active.
