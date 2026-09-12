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

-- Internal laptop panels. scale 1.57 is what the stock config picked for the
-- Framework's 2256x1504: 2256 / 1.57 = ~1437 logical px. Hyprland reports the
-- applied scale as 1.5666667, because it snaps to a value that keeps the
-- logical size a whole number of pixels - an arbitrary scale that does not
-- divide evenly is rejected.
--
-- That fractional scale is also why several things in quickshell carry a 1px
-- overlap: a logical coordinate times 1.5667 can land mid-pixel, and two
-- antialiased edges that meet there sum to about 78% coverage instead of
-- opaque. Those overlaps are harmless at scale 1, just unnecessary.
hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "auto",
    scale    = "1.57",
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
