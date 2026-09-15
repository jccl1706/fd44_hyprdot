-- =========================================================================
-- Monitors
-- =========================================================================
-- https://wiki.hypr.land/Configuring/Basics/Monitors/
--
-- This machine: Framework 13 AMD, internal panel is eDP-1, a BOE 0x0BCA
-- running 2256x1504@60. Native modes also include 48Hz, which the panel
-- advertises for power saving.
--
-- Inspect what Hyprland currently sees with:  hyprctl monitors

-- TWO RULES, AND THE ORDER MATTERS. Hyprland applies monitor rules in the
-- order they are declared and the last one matching an output wins, so the
-- catch-all comes first and the specific rule overrides it.
--
-- This is what makes the config portable between machines rather than being
-- this laptop's config. A fractional scale is right for a 13" 2256x1504 panel
-- and wrong for nearly everything else: an external 27" 1440p display, or a
-- desktop's only monitor, wants 1:1. Keying on the OUTPUT NAME rather than on
-- the hostname means neither machine needs to know the other exists - eDP is
-- an internal laptop panel by definition, DP and HDMI are not.

-- Everything that is not an internal panel: no scaling.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

-- Variable refresh rate, for fullscreen windows only.
--
-- 2 is FULLSCREEN ONLY, not 1 (always). With VRR on everywhere the panel's
-- refresh rate follows whatever is drawing, so an idle desktop drags it to the
-- bottom of the range, where many panels visibly flicker in brightness.
-- Fullscreen is where frame pacing is the point, which is games.
--
-- GLOBAL, NOT ON THE MONITOR RULE - and that was measured, not chosen.
-- hl.monitor accepts a `vrr` field and loads it without a word, but on
-- Hyprland 0.56 it changed nothing. On the desktop's LG (DP-2, EDID range
-- 48-144 Hz, reported vrr-capable by the DRM driver), with a game fullscreen
-- and on screen, adaptive sync read as off with the monitor rule at either
-- value. The global option is the one that does something:
--
--   monitor rule vrr = 1 or 2   desktop off   game off
--   misc.vrr = 1                desktop on    game on
--   misc.vrr = 2                desktop off   game on    <- this
--   misc.vrr = 3                desktop off   game off   (wants a content-type
--                                                        hint Proton games do
--                                                        not send)
--
-- Being global, it reaches the laptop as well. That is fullscreen-only there
-- too, and on a panel with no adaptive sync there is nothing for it to enable.
hl.config({ misc = { vrr = 2 } })

-- Internal laptop panels, PER PANEL. The right scale follows pixel density,
-- which the connector name cannot tell apart: both laptops call their panel
-- eDP-1. `desc:` matches the panel's EDID make and model instead, as
-- `hyprctl monitors` prints them.
--
-- The target is about 125-130 effective px per inch, so text is the same
-- physical size on every machine:
--
--   Framework 13  BOE 0x0BCA  2256x1504 13.5"  ~201 ppi  1.57 -> 1440x960   ~128
--   ThinkPad T480 AUO 0x213D  1920x1080 13.9"  ~158 ppi  1.25 -> 1536x864   ~126
--
-- Hyprland snaps a scale to one that keeps the logical size whole, and reports
-- the Framework's 1.57 as 1.5666667. A value that cannot be snapped cleanly
-- ends up somewhere else - 1.25 on the Framework lands on 1.175 - so a new
-- panel's scale is worth checking with `hyprctl monitors` after adding it.
--
-- Any other internal panel gets 1, not "auto". Measured on the Framework,
-- "auto" picked 2 (1128x752 logical - far too big); 1 is at worst small text
-- on a dense panel, never a desktop that does not fit.
--
-- Fractional scales are also why several things in quickshell carry a 1px
-- overlap: a logical coordinate times 1.5667 can land mid-pixel, and two
-- antialiased edges that meet there sum to about 78% coverage instead of
-- opaque. Those overlaps are harmless at scale 1, just unnecessary.
hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

hl.monitor({
    output   = "desc:BOE 0x0BCA",     -- Framework 13 AMD
    mode     = "preferred",
    position = "auto",
    scale    = "1.57",
})

hl.monitor({
    output   = "desc:AUO 0x213D",     -- ThinkPad T480, 14" FHD
    mode     = "preferred",
    position = "auto",
    scale    = "1.25",
})

-- Example: pin the internal panel explicitly and put an external display to
-- its right. Uncomment and adjust when you actually dock something.
--
-- hl.monitor({
--     output   = "eDP-1",
--     mode     = "2256x1504@60",
--     position = "0x0",
--     scale    = "1.57",
-- })
--
-- hl.monitor({
--     output   = "DP-3",
--     mode     = "preferred",
--     position = "auto-right",
--     scale    = "1",
-- })

-- Example: disable the internal panel when the lid is shut and an external
-- display is connected. Needs a matching lid handler - left off for now.
--
-- hl.monitor({ output = "eDP-1", disabled = true })
