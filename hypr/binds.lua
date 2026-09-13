-- =========================================================================
-- Keybindings
-- =========================================================================
-- https://wiki.hypr.land/Configuring/Basics/Binds/
--
-- Mod and Apps come from hyprland.lua.
--
-- Bind options used below:
--   { mouse     = true }   this binding is a mouse button, not a key
--   { locked    = true }   still fires while the session is locked
--   { repeating = true }   auto-repeats while held

local Mod  = Mod
local Apps = Apps


-- -------------------------------------------------------------------------
-- Applications and session
-- -------------------------------------------------------------------------

hl.bind(Mod .. " + Return", hl.dsp.exec_cmd(Apps.terminal))
hl.bind(Mod .. " + B",      hl.dsp.exec_cmd(Apps.browser))
hl.bind(Mod .. " + E",      hl.dsp.exec_cmd(Apps.file_manager))

-- Launcher. Apps.menu is nil until Quickshell provides one, so this bind is
-- skipped entirely rather than wired to an empty string - binding a key to
-- exec_cmd("") spawns a shell that does nothing, which looks like the key is
-- broken rather than unassigned.
-- Quickshell's own panels, via Hyprland's GLOBAL SHORTCUTS protocol rather
-- than by running a command.
--
-- The obvious binding is exec_cmd("qs ipc call launcher toggle"), and it
-- works - but it spawns a whole quickshell process on every press purely to
-- talk to the one already running. Measured at 113ms of dead time before the
-- panel started to appear, against a 60ms image decode inside it: the launch
-- overhead was nearly twice the actual work.
--
-- `global` hands the keypress straight to the running process. The name after
-- the colon is matched by a GlobalShortcut in quickshell/shell.qml; if
-- quickshell is not running the binding simply does nothing, which is the
-- same harmless failure exec_cmd gave.
hl.bind(Mod .. " + space", hl.dsp.global("quickshell:launcher"))
hl.bind(Mod .. " + comma", hl.dsp.global("quickshell:wallpaper"))

-- Theme. Flips the whole desktop between themes/dark.conf and
-- themes/cream.conf - quickshell, kitty, GTK apps and Hyprland all at once.
--
-- exec_cmd rather than a quickshell global shortcut, unlike the launcher and
-- the wallpaper picker: the switch is not quickshell's to make. Three of the
-- four things it changes are other programs entirely, so it has to run out of
-- a process that can write their config files and signal them. The bar's own
-- colours follow along because Theme.qml watches the palette file.
hl.bind(Mod .. " + T", hl.dsp.exec_cmd(
    '"$HOME/.config/hypr/../bin/theme.sh" toggle'
))

-- Session actions. This used to run `hyprctl dispatch exit` directly, which
-- ended the session on a single keystroke with nothing to catch a misfire.
-- It now opens quickshell's power menu instead, where lock, suspend, log out,
-- restart and shut down are separate deliberate choices.
--
-- Via the global-shortcuts protocol rather than exec_cmd, for the same reason
-- as the launcher: `qs ipc call` spawns a whole process per press.
hl.bind(Mod .. " + M", hl.dsp.global("quickshell:power"))

-- The physical power button opens the same menu.
--
-- logind owns this key by default and its default is HandlePowerKey=poweroff:
-- one press, immediate shutdown, nothing to catch a misfire - the same flaw
-- Super+M had. A drop-in in /etc/systemd/logind.conf.d hands the key over by
-- setting HandlePowerKey=ignore, which is what lets this binding see it at
-- all, and moves a clean poweroff to HandlePowerKeyLongPress so holding the
-- button still works when there is no session to show a menu.
--
-- NOT `locked = true`, deliberately: with the screen locked this binding stays
-- inert, so the button cannot raise a shutdown menu over hyprlock. Holding it
-- still powers off, which is logind's job by then, not ours.
hl.bind("XF86PowerOff", hl.dsp.global("quickshell:power"))


-- -------------------------------------------------------------------------
-- Window management
-- -------------------------------------------------------------------------
-- hl.bind returns a handle, so a binding can be disabled at runtime with
-- handle:set_enabled(false) - useful for submaps or conditional setups.

hl.bind(Mod .. " + W", hl.dsp.window.close())

-- Toggle true fullscreen. The window covers the output entirely, ignoring
-- gaps, borders and any bar.
--
-- fullscreen() also takes { mode = 1 }, which "maximizes" instead: the window
-- fills the usable area but still respects gaps and reserved space. Bind that
-- to Mod + SHIFT + F if you want both.
hl.bind(Mod .. " + F", hl.dsp.window.fullscreen())

hl.bind(Mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(Mod .. " + P", hl.dsp.window.pseudo())

-- Layout messages are layout-specific. The active layout is "scrolling"
-- (see look.lua), whose valid messages are:
--
--   colresize <+1|-1|N|+0.1|-0.1>  cycle or set the focused column's width,
--                                  stepping through scrolling.explicit_column_widths
--   fit <active|all|visible|toend|tobeg>  refit columns into the viewport
--   promote                        promote the focused window
--   expel                          move the focused window out into its own column
--   consume                        pull the next column's window into this one
--   swapcol <+1|-1>                swap this column with its neighbour
--
-- Anything else - notably dwindle's "togglesplit", which used to be on this
-- key - errors with "no such layoutmsg for scrolling".
hl.bind(Mod .. " + J", hl.dsp.layout("colresize +1"))

-- Stacking windows within a column is the scrolling layout's main trick:
-- several windows share one column slot instead of extending the strip.
--
--   [  consume  pull the NEXT column's window into this column
--   ]  expel    push the focused window back out into its own column
--
-- Both are directionless - passing "left"/"right" changes nothing.
hl.bind(Mod .. " + bracketleft",  hl.dsp.layout("consume"))
hl.bind(Mod .. " + bracketright", hl.dsp.layout("expel"))

-- Zoom out so every column in the strip is visible at once, which is the
-- practical way to find a window once the strip is longer than the screen.
hl.bind(Mod .. " + A", hl.dsp.layout("fit all"))

-- Focus movement.
hl.bind(Mod .. " + left",  hl.dsp.focus({ direction = "left"  }))
hl.bind(Mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(Mod .. " + up",    hl.dsp.focus({ direction = "up"    }))
hl.bind(Mod .. " + down",  hl.dsp.focus({ direction = "down"  }))

-- Move the window within the layout, same directions.
-- Note this is positional movement, not "send to workspace" - that stays on
-- Mod + SHIFT + number below.
hl.bind(Mod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left"  }))
hl.bind(Mod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(Mod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up"    }))
hl.bind(Mod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down"  }))

-- Drag to move, drag to resize. 272 is left mouse button, 273 is right.
hl.bind(Mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(Mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


-- -------------------------------------------------------------------------
-- Workspaces
-- -------------------------------------------------------------------------

-- Mod + 1..9,0 focuses a workspace; adding Shift moves the active window
-- there. i runs 1..10 and 10 maps onto the "0" key.
for i = 1, 10 do
    local key = i % 10
    hl.bind(Mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(Mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad (a "special" workspace that overlays the current one).
hl.bind(Mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(Mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- btop in a scratchpad of its own: a floating system monitor over whatever
-- is on screen, gone again on the same key. Nothing has to be started first -
-- the workspace rule in rules.lua launches btop whenever this opens empty,
-- so quitting btop (q) just means the next press starts a fresh one.
hl.bind(Mod .. " + grave",     hl.dsp.workspace.toggle_special("btop"))

-- Cycle workspaces from the keyboard. "e+1"/"e-1" step to the next/previous
-- EXISTING workspace, skipping empty ones, rather than to literal id+1.
hl.bind(Mod .. " + Tab",           hl.dsp.focus({ workspace = "e+1" }))
hl.bind(Mod .. " + SHIFT + Tab",   hl.dsp.focus({ workspace = "e-1" }))

-- Same thing with the scroll wheel.
hl.bind(Mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(Mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))


-- -------------------------------------------------------------------------
-- Laptop function keys
-- -------------------------------------------------------------------------
-- All marked locked = true so volume and brightness still work on the lock
-- screen, which is the behaviour you want when music is playing.
--
-- Audio goes through wpctl (PipeWire/WirePlumber). The -l 1 on volume-up
-- clamps at 100% so the key cannot push the sink into software amplification.

-- Each of these changes the value and THEN tells quickshell to show its OSD.
-- Order matters: the OSD reads the real value from PipeWire / sysfs when it
-- displays, so announcing before the change would show the old number.
--
-- `qs ipc call osd volume` targets the IpcHandler in quickshell/shell.qml.
-- If quickshell is not running the call fails harmlessly and the volume still
-- changes - the OSD is decoration, never a dependency.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && qs ipc call osd volume"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && qs ipc call osd volume"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && qs ipc call osd volume"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })

-- Through bin/backlight.sh rather than brightnessctl directly, because the
-- device is not the same on every machine: this laptop's panel is
-- `amdgpu_bl1`, an Intel one is `intel_backlight`, and A DESKTOP HAS NONE AT
-- ALL. The script resolves it from /sys/class/backlight and exits 0 doing
-- nothing when there is nothing to do, so these binds are correct on a
-- machine without a backlight instead of needing to be deleted there.
--
-- The curve settings moved into the script with the device: -e4 is a 4th-power
-- curve so low-end steps feel even, -n2 stops it going fully dark.
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("$HOME/.config/hypr/../bin/backlight.sh set 5%+ && qs ipc call osd brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("$HOME/.config/hypr/../bin/backlight.sh set 5%- && qs ipc call osd brightness"), { locked = true, repeating = true })

-- Media keys.
-- Via quickshell, which speaks MPRIS itself (quickshell/Media.qml), so a
-- media key spawns NO process. These used to run playerctl, forking it once
-- per press - the same cost the launcher and wallpaper picker were moved off
-- exec_cmd to avoid, and the media keys were simply the ones left behind.
--
-- It also removed a package: playerctl was never in the installer's list and
-- existed on the development machine only as a weak dependency of something
-- unrelated, so the media keys worked there and would have been dead on any
-- fresh install.
--
-- `locked = true` still: quickshell keeps running while hyprlock is up, so
-- the keys keep working on a locked screen, which is where media keys are
-- most useful.
hl.bind("XF86AudioNext",  hl.dsp.global("quickshell:media-next"),   { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("quickshell:media-toggle"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.global("quickshell:media-toggle"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.global("quickshell:media-prev"),   { locked = true })


-- -------------------------------------------------------------------------
-- Screenshots
-- -------------------------------------------------------------------------
-- grim, slurp and wl-clipboard are all installed, so these work as-is.
-- Region to clipboard, whole screen to clipboard, region to a file.

hl.bind(Mod .. " + SHIFT + P", hl.dsp.exec_cmd(
    'grim -g "$(slurp)" - | wl-copy'
))
hl.bind("Print", hl.dsp.exec_cmd(
    'grim - | wl-copy'
))
hl.bind(Mod .. " + CTRL + P", hl.dsp.exec_cmd(
    'grim -g "$(slurp)" "$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"'
))


-- -------------------------------------------------------------------------
-- Passthrough submap (for nested compositors / VMs)
-- -------------------------------------------------------------------------
-- Running a VM - or another Wayland session - inside this one means two
-- compositors competing for SUPER, and the host always wins: Hyprland
-- intercepts the modifier before the guest window ever sees it. qemu cannot
-- take it back either. Under XWayland its XGrabKeyboard only affects the X
-- server, and on the Wayland backend GTK3 implements no pointer constraints,
-- so grabbing there kills mouse motion instead.
--
-- A submap sidesteps all of it: while "passthrough" is active, none of the
-- bindings above exist, so every key including SUPER goes straight to the
-- focused window. SUPER+Escape toggles it, and that one binding is all the
-- submap defines - which is also why it cannot trap you: the same key gets
-- you out.
--
-- Check which submap is active at any time with:  hyprctl submap
hl.define_submap("passthrough", function()
    hl.bind(Mod .. " + Escape", hl.dsp.submap("reset"))
end)

hl.bind(Mod .. " + Escape", hl.dsp.submap("passthrough"))
