# Keybindings

Every key this desktop binds, in one page. `SUPER` is the Windows key; the
source of truth is [`hypr/binds.lua`](../hypr/binds.lua), and `hyprctl binds`
lists what the running compositor actually has registered.

There is a styled twin, [`keybindings.html`](keybindings.html), for reading on
the machine itself — `xdg-open docs/keybindings.html`, and `Ctrl+P` prints it on
two sheets. GitHub serves HTML as source, so this is the page to read here.

> **Nothing here is bound twice by accident.** Hyprland does not shadow an
> existing bind when you add another on the same key — it registers both and
> fires both. If a key seems to do two things, that is what happened.

---

## The six to learn first

| | |
|---|---|
| `SUPER` `Return` | a terminal |
| `SUPER` `Space` | the app launcher |
| `SUPER` `W` | close the window |
| `SUPER` `←` `→` | move focus along the strip |
| `SUPER` `A` | zoom out until every window is visible |
| `SUPER` `M` | the power menu — lock, suspend, log out, reboot, shut down |

---

## Applications and session

| Keys | Does |
|---|---|
| `SUPER` `Return` | Terminal — kitty |
| `SUPER` `B` | Browser — whichever of chromium / chrome / firefox is installed |
| `SUPER` `E` | File manager — nautilus |
| `SUPER` `Y` | YouTube, in its own window rather than a browser tab |
| `SUPER` `Space` | App launcher |
| `SUPER` `,` | Wallpaper picker |
| `SUPER` `SHIFT` `,` | Settings — also one click on the bar's logo |
| `SUPER` `T` | Toggle theme, dark ⇄ cream: bar, terminal, GTK apps and compositor together |
| `SUPER` `Z` | Focus mode — hide the bar down to a single button to come back |
| `SUPER` `M` | Power menu |
| power button | The same power menu. Hold it to power off regardless |

The launcher, wallpaper picker, settings, focus mode and power menu are panels
inside the already-running Quickshell, reached through Hyprland's
global-shortcuts protocol rather than by running a command — a keypress starts
no process. If Quickshell is not running these keys do nothing at all, which is
the same harmless failure as an unbound key.

`SUPER` `Z` changes a *setting* rather than showing a window, so focus mode
survives a shell restart. The bar keeps a visible button to leave it, because a
mode entered by accident must not need a second secret key to undo.

The power button is deliberately **not** `locked = true`: with the screen locked
it stays inert, so nobody can raise a shutdown menu over the lock screen.

---

## Windows

| Keys | Does |
|---|---|
| `SUPER` `W` | Close |
| `SUPER` `F` | True fullscreen — covers the output, ignoring gaps and the bar |
| `SUPER` `V` | Float / tile |
| `SUPER` `P` | Pseudo-tile |
| `SUPER` `←` `→` `↑` `↓` | Move focus |
| `SUPER` `SHIFT` `←` `→` `↑` `↓` | Move the window within the layout |
| `SUPER` + right-drag | Move the window with the mouse |
| `SUPER` + left-drag | Resize the window with the mouse |

**Right drags, left resizes** — the opposite way round from the Hyprland default.
Moving is the thing done constantly and resizing the thing done occasionally, and
the right button is the one a free hand finds without looking. Both still need
`SUPER`: a bare right drag would stop right-click reaching applications at all,
so no context menus anywhere.

---

## The scrolling layout

Windows live in a horizontal strip of columns rather than a tree. Several windows
can share one column, which is the layout's main trick.

| Keys | Does |
|---|---|
| `SUPER` `J` | Cycle the focused column's width |
| `SUPER` `[` | Consume — pull the next column's window into this column |
| `SUPER` `]` | Expel — push the focused window back out into its own column |
| `SUPER` `A` | Fit all — zoom out so the whole strip is on screen |

`SUPER` `A` is how you find a window once the strip is longer than the screen.

Layout messages are layout-specific: dwindle's `togglesplit` and friends error
with *no such layoutmsg for scrolling*.

---

## Workspaces

| Keys | Does |
|---|---|
| `SUPER` `1` … `9` `0` | Focus workspace 1–10 |
| `SUPER` `SHIFT` `1` … `9` `0` | Send the window to that workspace |
| `SUPER` `Tab` | Next workspace that exists, skipping empty ones |
| `SUPER` `SHIFT` `Tab` | Previous workspace that exists |
| `SUPER` + scroll wheel | The same, with the mouse |
| `SUPER` `S` | Scratchpad — overlays whatever is on screen |
| `SUPER` `SHIFT` `S` | Send the window to the scratchpad |
| `SUPER` + `` ` `` | btop, floating, in a scratchpad of its own |

The btop scratchpad needs nothing started first: a workspace rule launches btop
whenever it opens empty, so quitting btop with `q` just means the next press
gets a fresh one. It does need btop installed (`sudo dnf install btop`).

---

## Volume, brightness and media

All of these are bound with `locked = true`, so they keep working on the lock
screen — which is where media keys are most useful.

| Keys | Does |
|---|---|
| `XF86AudioRaiseVolume` `XF86AudioLowerVolume` | Volume ±5%, clamped at 100% so it never software-amplifies |
| `XF86AudioMute` | Mute the output |
| `XF86AudioMicMute` | Mute the microphone |
| `XF86MonBrightnessUp` `XF86MonBrightnessDown` | Backlight ±5% on a 4th-power curve, never fully dark |
| `XF86AudioPlay` `XF86AudioPause` | Play / pause |
| `XF86AudioNext` `XF86AudioPrev` | Next / previous track |

Volume and brightness show an on-screen display, and each key changes the value
*before* asking for it — the OSD reads the real number from PipeWire or sysfs, so
announcing first would show the old one. The OSD is decoration: if Quickshell is
down the volume still changes.

The brightness keys go through `bin/backlight.sh`, which resolves the panel from
`/sys/class/backlight` — `amdgpu_bl1` here, `intel_backlight` elsewhere, nothing
at all on a desktop, where the keys correctly do nothing rather than needing to
be deleted.

Media keys speak MPRIS from inside Quickshell, so they too fork no process.

---

## Screenshots

| Keys | Does |
|---|---|
| `Print` | Whole screen → clipboard |
| `SUPER` `SHIFT` `P` | Select a region → clipboard |
| `SUPER` `CTRL` `P` | Select a region → `~/Pictures/screenshot-YYYYmmdd-HHMMSS.png` |

---

## Passthrough, for VMs and nested compositors

| Keys | Does |
|---|---|
| `SUPER` `Escape` | Toggle the passthrough submap |

Running a VM — or another Wayland session — inside this one means two compositors
competing for `SUPER`, and the host always wins. While passthrough is active
**none of the binds on this page exist**, so every key including `SUPER` goes
straight to the focused window.

> A stuck passthrough looks exactly like a broken keyboard. `hyprctl submap` says
> which submap is active, and `SUPER` `Escape` is the only bind the submap
> defines — the same key always gets you out.

---

## Inside the terminal

Not Hyprland's, but the two that come up daily:

| Keys | Does |
|---|---|
| `CTRL` `B` | tmux prefix |
| `ALT` `←` `→` | Previous / next tmux window, no prefix needed |
| `ALT` `1` … `9` | Jump straight to that tmux window |
| click a URL | Open it in the browser — `CTRL` `SHIFT` click where something else has taken the plain click |
| `CTRL` `SHIFT` `E` | Hints mode: label every URL on screen and pick one by letter |

Links go through `bin/browser.sh` rather than `xdg-open`, so a link in the
terminal and `SUPER` `B` open the same program by construction. Hints mode is
the one to learn: it needs no mouse, so it still works over SSH and inside tmux,
where mouse reporting swallows the click.
