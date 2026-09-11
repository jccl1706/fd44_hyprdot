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
hl.bind(Mod .. " + J", hl.dsp.layout("togglesplit"))  -- dwindle only

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

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })

-- brightnessctl -e4 uses a 4th-power curve so low-end steps feel even, and
-- -n2 stops it going fully dark (minimum 2).
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

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
