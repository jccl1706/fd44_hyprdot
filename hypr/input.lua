-- =========================================================================
-- Input - keyboard, pointer, touchpad, gestures
-- =========================================================================
-- https://wiki.hypr.land/Configuring/Variables/#input
--
-- This machine's pointer devices, as libinput sees them:
--   PIXA3854:00 093A:0274 Touchpad   (the trackpad)
--   PIXA3854:00 093A:0274 Mouse      (its pointer-stick interface)
--
-- List what Hyprland currently has with:  hyprctl devices

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_rules   = "",

        -- Useful kb_options values if you ever want them:
        --   caps:escape          Caps Lock acts as Escape
        --   compose:ralt         right Alt becomes a compose key
        --   grp:alt_shift_toggle cycle layouts with Alt+Shift
        kb_options = "",

        -- 1 = focus follows the mouse.
        follow_mouse = 1,

        -- -1.0 to 1.0. 0 means no modification to libinput's own accel.
        sensitivity = 0,

        touchpad = {
            -- true gives "content moves with your fingers" (macOS style).
            natural_scroll = false,

            -- Other touchpad options worth knowing:
            --   disable_while_typing = true   (default, usually wanted)
            --   tap-to-click         = true   (default)
            --   drag_lock            = false
        },
    },
})


-- -------------------------------------------------------------------------
-- Gestures
-- -------------------------------------------------------------------------
-- Three fingers horizontally switches workspaces.

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})


-- -------------------------------------------------------------------------
-- Per-device overrides
-- -------------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
--
-- Match on the name exactly as `hyprctl devices` prints it. The entry below
-- is the stock example and matches nothing on this machine - it is kept only
-- as a syntax reminder. Replace or delete it once you have a real device to
-- tune (e.g. an external mouse with its own acceleration).


-- -------------------------------------------------------------------------
-- Cursor
-- -------------------------------------------------------------------------

-- FORCE A HARDWARE CURSOR. Hyprland's default for both of these is `auto`
-- (2), and auto chose wrong here: with a second monitor attached the pointer
-- became visibly choppy, worst over a large surface like the audio panel.
--
-- A hardware cursor lives on its own scanout plane and moves whether or not
-- anything else is being composited, so it stays smooth under load. A
-- software cursor rides the ordinary render path, which puts it in
-- competition with everything else drawing - and Quickshell's drop-down
-- panels are a full-screen surface, so on the 2560x1440 external every
-- pointer motion had Qt repainting 3.7 million pixels underneath it.
--
-- Measured while moving the pointer over the open audio panel, before this:
--
--                    cursor moving        cursor still
--   quickshell       8.5% mean, 20% peak  0.1% mean
--   Hyprland         6.4% mean, 12% peak  1.0% mean
--
-- MIXED SCALING IS THE LIKELY REASON AUTO GAVE UP: this laptop runs its own
-- panel at 1.5666667 and an external at 1, and a cursor that has to be
-- rescaled per output is exactly the case a compositor falls back to
-- software for. Which means this matters on THIS machine, with a display
-- plugged in, and changes nothing on a desktop with one monitor at scale 1.
--
-- THE TRADE-OFF, so it is not a surprise later: forcing a hardware cursor
-- with fractional scaling can make the pointer look slightly coarse on the
-- SCALED output, because the plane cannot be scaled as smoothly as a drawn
-- one. Set either of these back to `nil` to return to auto if that ever
-- matters more than the smoothness.
hl.config({
    cursor = {
        no_hardware_cursors = false,
        use_cpu_buffer      = false,
    },
})
