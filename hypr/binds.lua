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
if Apps.menu then
    hl.bind(Mod .. " + R", hl.dsp.exec_cmd(Apps.menu))
end

-- Exit. Prefers hyprshutdown if it is installed, otherwise exits directly.
hl.bind(Mod .. " + M", hl.dsp.exec_cmd(
    "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"
))


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

-- brightnessctl -e4 uses a 4th-power curve so low-end steps feel even, and
-- -n2 stops it going fully dark (minimum 2).
-- -d amdgpu_bl1 is required: without it brightnessctl also picks up the
-- ChromeOS EC LED classes and errors on them.
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -d amdgpu_bl1 -e4 -n2 set 5%+ && qs ipc call osd brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d amdgpu_bl1 -e4 -n2 set 5%- && qs ipc call osd brightness"), { locked = true, repeating = true })

-- Media keys. playerctl is installed.
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


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
