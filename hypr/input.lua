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

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
