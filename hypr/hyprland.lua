-- =========================================================================
-- Hyprland - entry point
-- =========================================================================
--
-- This file does two things and nothing else: declare the handful of values
-- that more than one module needs, then pull the modules in. All actual
-- configuration lives in the required files.
--
-- Layout (one file per concern):
--   monitors   outputs, resolution, scaling
--   look       general / decoration / animations / layouts / misc
--   input      keyboard, touchpad, gestures, per-device tweaks
--   binds      keybindings
--   rules      window, workspace and layer rules
--   autostart  environment variables, permissions, startup programs
--
-- require() resolves relative to this directory, so a file "input.lua" next
-- to this one is required as "input" with no path.
--
-- Reload after editing with:  hyprctl reload
-- Then always check:          hyprctl configerrors
--
-- Real location: ~/Work/fd44_hyprdot/hypr/  (~/.config/hypr is a symlink to it)


-- -------------------------------------------------------------------------
-- Shared values
-- -------------------------------------------------------------------------
--
-- A deliberate global. Lua modules loaded with require() share _G, so this is
-- the simplest way to let binds.lua and autostart.lua agree on which terminal
-- to launch without threading a table through every file. Keep it small - if
-- this grows past a few entries it should become its own module that returns
-- a table.

Apps = {
    terminal     = "kitty",
    file_manager = "nautilus",

    -- Fedora's chromium package installs the binary as "chromium-browser",
    -- not "chromium" - there is no "chromium" symlink.
    browser      = "chromium-browser",

    -- No application launcher is installed. This is deliberate: Quickshell is
    -- intended to own the bar, launcher and notification popups, so a separate
    -- launcher (wofi/fuzzel/rofi) would duplicate it.
    --
    -- Leave this nil until Quickshell provides one. binds.lua checks for nil
    -- and skips the launcher keybind rather than binding a key to an empty
    -- command, which is what the stock config did.
    menu         = nil,
}

-- Main modifier used throughout binds.lua.
Mod = "SUPER"


-- -------------------------------------------------------------------------
-- Modules
-- -------------------------------------------------------------------------
--
-- Order matters a little: look.lua defines the animation curves that other
-- settings reference, and autostart.lua sets environment variables that
-- programs launched at startup inherit. Everything else is independent.

require("monitors")
require("look")
require("input")
require("binds")
require("rules")
require("autostart")
