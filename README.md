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

## Power policy

| | Battery | AC |
|---|---|---|
| Power profile | `power-saver` | `balanced` |
| Brightness | 50% | 100% |
| Lock | 5 min | 15 min |
| Screen off | 5 min | 15 min |

Two independent mechanisms, deliberately:

**Profile and brightness** are applied by `bin/power-mode.sh`, driven by
`udevadm monitor` on the `power_supply` subsystem. Event-driven rather than
polling, and entirely unprivileged - `powerprofilesctl` and `brightnessctl`
both work as the user here, so there is no udev rule and nothing in `/etc`.

**Lock and screen-off timeouts** live in `hypridle.conf`. Both listeners are
always armed and the 5-minute one tests `/sys/class/power_supply/ACAD/online`
when it fires, doing nothing on AC so the 15-minute listener handles it. This
avoids swapping config files and restarting hypridle on every plug event, and
avoids a race if the charger moves while a timer is already running.

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
