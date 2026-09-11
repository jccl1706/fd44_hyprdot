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

-- Catch-all rule. output = "" means "every output not matched by a more
-- specific rule below", so a monitor plugged in later gets sane defaults
-- instead of nothing.
--
-- scale 1.57 is what the stock config picked for this panel. 2256 / 1.57 =
-- ~1437 logical px. Note Hyprland reports the applied scale as 1.5666667,
-- because it snaps to a value that keeps the logical size a whole number of
-- pixels - an arbitrary scale that does not divide evenly is rejected.
hl.monitor({
    output   = "",
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
