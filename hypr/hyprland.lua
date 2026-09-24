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
-- Real location: the checkout's hypr/ (~/.config/hypr is a symlink to it).
-- Scripts are reached as ~/.config/hypr/../bin/, which follows that symlink
-- and so does not care where the checkout lives.


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

    -- NOT A BINARY NAME, because there isn't one that works everywhere:
    -- Fedora's chromium package installs "chromium-browser" and ships no
    -- "chromium" symlink, while Debian installs "chromium" and nothing else.
    -- bin/browser.sh picks whichever is present and execs it.
    --
    -- THE NIXOS DESKTOP WAS FINE, checked rather than assumed - after this
    -- was written on the guess that it would not be. It has both names. The
    -- shim is still worth having: one machine happening to carry both is not
    -- a reason to write one distribution's spelling into a file every
    -- machine reads, and bin/chrome-theme.sh already searched a list for
    -- exactly this reason.
    --
    -- Reached through ~/.config/hypr, which is a symlink into the checkout,
    -- so the path resolves wherever the repository lives - the same trick the
    -- systemd units use.
    browser      = "$HOME/.config/hypr/../bin/browser.sh",

    -- The launcher is Quickshell's (quickshell/Launcher.qml), not a separate
    -- program: no wofi/fuzzel/rofi, because Quickshell already owns the bar
    -- and would duplicate it.
    --
    -- This is an IPC call rather than a command that starts something. The
    -- launcher surface already exists, unmapped, inside the running
    -- quickshell; the keybind only tells it to show itself. If quickshell is
    -- not running the call fails harmlessly and no key appears to be broken.
    --
    -- Check what a running instance exposes with:  qs ipc show
    menu         = "qs ipc call launcher toggle",
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
