# fd44_hyprdot

Dotfiles for Fedora 44 + Hyprland on a Framework 13 (AMD Ryzen 7040 series).

No display manager: the session is started by **uwsm** from a getty autologin
on tty1. Quickshell is intended to provide the bar, launcher and notification
popups, so no separate launcher or notification daemon is installed.

## Layout

```
hypr/
  hyprland.lua           entry point - shared values, then requires the modules
  monitors.lua           outputs, resolution, scaling
  look.lua               colors, general, decoration, animations, layouts, misc
  input.lua              keyboard, touchpad, gestures, per-device tweaks
  binds.lua              keybindings
  rules.lua              window, workspace and layer rules
  autostart.lua          environment variables, permissions, startup programs
  hypridle.conf          idle -> lock -> screen off (AC/battery aware)
  hyprlock.conf          lock screen appearance

bin/
  power-mode.sh          applies power profile + brightness for the current
                         power source; `watch` mode reacts to the charger
  idle-action.sh         lock/blank/wake actions called by hypridle; keeps the
                         quoting out of hypridle.conf and is testable with
                         --dry-run

systemd/
  power-mode.service     user unit that runs power-mode.sh in watch mode

quickshell/
  Theme.qml              SINGLETON - every colour, font and metric lives here
                         and nowhere else. Change the bar's look from one file.
  shell.qml              entry point - one Bar per monitor, plus the IpcHandler
                         that Hyprland's keybinds call
  Bar.qml                the panel: left / centre / right regions
  Logo.qml               Fedora mark (Nerd Font glyph, SVG fallback)
  Workspaces.qml         five fixed slots, live state from Hyprland IPC
  Clock.qml              24h clock, SystemClock-driven
  Osd.qml                hidden volume/brightness indicator

install/
  install_fedora_v1_10.sh guided Fedora 44 installer that builds this machine
                         from bare metal: Btrfs + systemd-boot + optional
                         LUKS, Hyprland/quickshell, autologin, Plymouth
  vm-test.sh             boots a throwaway UEFI VM to test the installer
                         without reformatting anything real
```

`require()` resolves relative to `hyprland.lua`'s directory, so `input.lua`
next to it is required as `require("input")` with no path.

## Install

`~/.config/hypr` is a **symlink to `hypr/`** in this repo, so edits are live
immediately - there is no copy step and nothing to keep in sync.

```sh
git clone <this repo> ~/Work/fd44_hyprdot

# Hyprland config
ln -s ~/Work/fd44_hyprdot/hypr ~/.config/hypr

# AC/battery power policy
mkdir -p ~/.config/systemd/user
ln -s ~/Work/fd44_hyprdot/systemd/power-mode.service \
      ~/.config/systemd/user/power-mode.service
systemctl --user daemon-reload
systemctl --user enable --now power-mode.service
```

`power-mode.service` is `WantedBy=graphical-session.target`, so it starts and
stops with the Hyprland session.

## Quickshell bar

`~/.config/quickshell` is a symlink to `quickshell/` here, same as the Hyprland
config. Run it with `qs`; it watches its own files and reloads on save.

```
[ logo | 1 2 3 4 5   <osd> ]        [ 13:47 ]        [ ... ]
```

The OSD is hidden until a volume or brightness key is pressed. Those keybinds
change the value and then call `qs ipc call osd volume` / `... brightness` -
see the bottom of `hypr/binds.lua`. The OSD reads the real value from PipeWire
or `/sys/class/backlight` at display time, so it cannot drift out of sync, and
if quickshell is not running the call fails harmlessly and the key still works.

Inspect a running instance:

```sh
qs ipc show                       # what IPC targets exist
hyprctl layers                    # confirm the layer surface (namespace: quickshell)
```

### Changing the look

Everything visual is in `quickshell/Theme.qml` - colours, fonts, sizes,
spacing, corner radius, animation durations. Components read `Theme.accent`
directly rather than declaring their own properties, so there is nothing to
thread through and no second copy to forget.

Two QML traps worth knowing if you edit it:

- `color` needs `import QtQuick`; with only `import Quickshell` it fails with
  "color is not a type".
- An identifier starting with `on` plus a capital letter is parsed as a SIGNAL
  HANDLER, not a property. `readonly property color onAccent` fails with
  "Cannot assign a value to a signal" - hence `accentFg`.

### Font dependencies

The bar needs two fonts that are not part of this repo. **The installer
handles both** - this section is for when you are setting the config up on a
machine it did not build.

- **Inter Variable** - `sudo dnf install rsms-inter-vf-fonts`.
  NOTE the family is registered as `Inter Variable`, not `Inter`. Asking for
  `Inter` silently falls back to Noto Sans and merely looks slightly wrong.
  Check with `fc-match "Inter Variable"`.
- **Symbols Nerd Font** - glyphs for the logo and the OSD icons. Not packaged
  in Fedora at all; the official symbols-only release is ~2.2 MiB:
  ```sh
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.tar.xz \
    | sudo tar -xJC /usr/local/share/fonts SymbolsNerdFont-Regular.ttf
  sudo fc-cache -f
  ```
  Check with `fc-match ':charset=f30a'` - it should name SymbolsNerdFont, not
  Noto Sans. Without it the logo and OSD icons render as empty boxes;
  `Logo.qml` can fall back to an SVG by setting `useGlyph: false`, but the OSD
  icons have no fallback.

Neither missing font produces an error. Fontconfig substitutes silently, so
the failure looks like a styling mistake rather than a missing dependency -
which is why both are installed explicitly rather than assumed.

## Rebuilding this machine

`install/install_fedora_v1_10.sh` installs Fedora 44 + Hyprland from a live
environment. It asks for a dotfiles git URL; give it this repo's URL and it
clones it, symlinks `~/.config/hypr` at `hypr/`, and enables the user units in
`systemd/` - so the result is this setup, not a generic one.

**The installed account ships with the password `changeme`, expired on
creation.** It is in a public repo, so assume everyone knows it - that is fine
only because `chage -d 0` forces a new password at the very first login,
before a shell is reached. If you replace `user_password` with your own hash,
drop the `chage` line too.

Never run it against real hardware untested. `install/vm-test.sh` boots a
throwaway UEFI VM for exactly that:

```sh
sudo dnf install qemu-system-x86-core qemu-img edk2-ovmf qemu-ui-gtk \
                 qemu-device-display-virtio-gpu qemu-device-display-virtio-vga-gl \
                 qemu-device-display-virtio-gpu-gl virglrenderer

cd install && ./vm-test.sh /path/to/Fedora-Workstation-Live-*.iso
```

It serves this directory over HTTP so the VM can `curl` the installer at
`10.0.2.2:8000`, and forwards host port 2222 to the VM's ssh. Inside the VM the
target disk is `/dev/vda`. `--reboot` boots the installed disk, `--clean`
throws it away.

Both scripts have safe modes that change nothing: `--check-repos` resolves
every package name, `--preflight` reports on the machine, `--dry-run` prints
every command it would run.

## Power policy

| | Battery | AC |
|---|---|---|
| Power profile | `power-saver` | `balanced` |
| Brightness | 50% | 100% |
| Lock | 5:00 | 5:00 |
| Display off | 5:30 | 15:30 |
| Suspend | 15:00 | never (lid close only) |

Locking is not power-dependent; only the display-off timeout is. On AC the
machine deliberately stays awake so long downloads, builds and ssh sessions
are not cut off - closing the lid still suspends, via logind's
`HandleLidSwitchExternalPower`.

The 30 second gap between locking and blanking is load-bearing - see the
comment in `hypridle.conf`.

Two independent mechanisms, deliberately:

**Profile and brightness** are applied by `bin/power-mode.sh`, driven by
`udevadm monitor` on the `power_supply` subsystem. Event-driven rather than
polling, and entirely unprivileged - `powerprofilesctl` and `brightnessctl`
both work as the user here, so there is no udev rule and nothing in `/etc`.

**Lock, display-off and suspend timeouts** live in `hypridle.conf`, with the
logic in `bin/idle-action.sh`. Every listener is always armed and the
battery-scoped ones test `/sys/class/power_supply/ACAD/online` when they fire,
doing nothing on AC. This avoids swapping config files and restarting hypridle
on every plug event, and avoids a race if the charger moves while a timer is
already running.

Watch it react:

```sh
journalctl --user -u power-mode.service -f
```

## Editing

```sh
hyprctl reload         # apply changes
hyprctl configerrors   # ALWAYS check - reload reports "ok" even when a
                       # module failed to load
```

Useful while writing rules:

```sh
hyprctl clients        # class/title of open windows, for window rules
hyprctl layers         # layer-shell surfaces, for layer rules
hyprctl devices        # exact device names, for per-device input config
hyprctl binds          # every registered keybind
hyprctl monitors       # outputs, modes, applied scale
hyprctl animations     # which curve and speed each leaf resolved to
```

`hyprctl dispatch` evaluates **Lua**, not the old string syntax, which makes it
the fastest way to test a dispatcher before binding it:

```sh
hyprctl dispatch 'hl.dsp.window.fullscreen()'
hyprctl dispatch 'hl.dsp.window.move({ direction = "left" })'
```

The full Lua API is documented in the stub shipped with Hyprland:
`/usr/share/hypr/stubs/hl.meta.lua`. It is the authoritative reference for
what `hl.*` accepts - more complete than the wiki for the Lua config format.

## Keybindings

| Key | Action |
|---|---|
| `SUPER+Return` | terminal (kitty) |
| `SUPER+B` | browser (chromium) |
| `SUPER+E` | file manager (nautilus) |
| `SUPER+W` | close window |
| `SUPER+F` | fullscreen |
| `SUPER+V` | toggle floating |
| `SUPER+P` | pseudo-tile |
| `SUPER+J` | cycle column width (scrolling) |
| `SUPER+[` | consume - pull next column's window into this column |
| `SUPER+]` | expel - push focused window out to its own column |
| `SUPER+A` | fit all - zoom out to show the whole strip |
| `SUPER+arrows` | move focus |
| `SUPER+SHIFT+arrows` | move window within the layout |
| `SUPER+1..9,0` | focus workspace |
| `SUPER+SHIFT+1..9,0` | send window to workspace |
| `SUPER+Tab` / `+SHIFT` | next / previous workspace |
| `SUPER+S` / `+SHIFT` | scratchpad toggle / send |
| `SUPER+M` | exit Hyprland |
| `SUPER+SHIFT+P` | screenshot region to clipboard |
| `Print` | screenshot screen to clipboard |
| `SUPER+CTRL+P` | screenshot region to `~/Pictures/` |

`SUPER+R` is reserved for a launcher and is **not bound** - `Apps.menu` in
`hyprland.lua` is `nil`, and `binds.lua` skips the bind rather than wiring a
key to an empty command. Set `Apps.menu` once Quickshell provides one.

Laptop function keys (volume, brightness, media) are all bound with
`locked = true`, so they keep working on the lock screen.

## Gotchas specific to this machine

- **`hl.dsp.dpms()` IGNORES its argument and TOGGLES.** Verified on 0.56.2:
  three consecutive `dpms("on")` calls give dpmsStatus `1 -> 0 -> 1 -> 0`,
  with or without a monitor name. Combined with the fact that hypridle fires
  `on-resume` for *every* armed listener simultaneously, two unguarded wake
  calls cancel out and leave the display off - while both log `ok`. That is
  what stranded this machine on 2026-09-11: the screen blanked on schedule, a
  keypress fired two wakes in the same second, and it never came back; only a
  VT switch got out. `bin/idle-action.sh` therefore reads dpmsStatus and only
  toggles when the state must actually change, under an `flock` so concurrent
  callers serialise.
- **Recovery if the display is ever stuck off**, from a TTY (Ctrl+Alt+F3):
  ```sh
  export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)
  hyprctl monitors | grep dpmsStatus        # 0 = off
  hyprctl dispatch 'hl.dsp.dpms("on")'      # toggles; re-check, do not repeat blindly
  ```
- **`hyprctl dispatch` only accepts dispatchers.** For top-level `hl.*`
  functions use `hyprctl eval '<lua>'`, or `hyprctl repl` for an interactive
  Lua prompt.
- **Restarting hypridle kills hyprlock.** `lock_cmd` spawns hyprlock as a
  child of hypridle, in the same systemd cgroup, so
  `systemctl --user restart hypridle` while locked takes the lock screen down
  and leaves the desktop behind a stale frame.
- **`hyprctl dispatch dpms off` does NOT work on Hyprland 0.56.** `hyprctl
  dispatch` evaluates Lua, so the old space-separated form is a parse error:
  `error: [string "return hl.dispatch(dpms off)"]:1: ')' expected near 'off'`.
  It fails **silently** from hypridle's side - hypridle logs "Executing
  hyprctl dispatch dpms off" and the screen simply never blanks. Nearly every
  hypridle example online uses the broken form. The working one is
  `hyprctl dispatch 'hl.dsp.dpms("off")'`, wrapped in `bin/idle-action.sh`.
- **hypridle expands `$HOME`** in `on-timeout`/`on-resume` (verified - it
  passes commands through a shell, which is also why `pidof hyprlock ||
  hyprlock` works in `lock_cmd`), so config entries need no absolute paths.
- **`brightnessctl` needs `-d amdgpu_bl1`.** Without it, it also picks up the
  ChromeOS EC LED classes (`chromeos:white:power` and friends) and errors on
  them, because those expose no readable brightness.
- **One plug event emits several `power_supply` udev events** - ACAD plus each
  USB-C port's `ucsi-source-psy` device - so `power-mode.sh` debounces on the
  resulting AC state rather than reacting per event.
- **`speed` is required on every `hl.animation`**, including spring ones where
  the physics, not the timeline, sets the duration. Omitting it is a config
  error.
- Variables that systemd user services need belong in **uwsm's** environment,
  not `autostart.lua` - uwsm exports its environment before Hyprland runs, so
  anything set in the Hyprland config arrives too late for them.
- **Do not try to dismiss the Plymouth splash from Hyprland.** Plymouth holds
  DRM master; masking `plymouth-quit*` so the splash outlives
  `graphical.target` deadlocks the boot - Hyprland dies immediately with
  `CBackend::create() failed!` and nothing is left to quit the splash. See the
  note at the bottom of `autostart.lua`.

## Not yet done

- `~/.config/quickshell` is empty - no bar, launcher or notification daemon.
- `hyprpaper` is installed but not started, so there is no wallpaper daemon.
