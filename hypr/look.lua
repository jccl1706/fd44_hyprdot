-- =========================================================================
-- Look and feel - general, decoration, animations, layouts, misc
-- =========================================================================
-- https://wiki.hypr.land/Configuring/Basics/Variables/


-- -------------------------------------------------------------------------
-- Colors
-- -------------------------------------------------------------------------
-- Kept at the top so the palette is in one place. Hyprland takes either a
-- plain "rgba(...)" string or, for a gradient, a table of colors plus an
-- angle in degrees.

local colors = {
    border_active_a   = "rgba(33ccffee)",
    border_active_b   = "rgba(00ff99ee)",
    border_inactive   = "rgba(595959aa)",
    shadow            = 0xee1a1a1a,
}


-- -------------------------------------------------------------------------
-- General
-- -------------------------------------------------------------------------

hl.config({
    general = {
        gaps_in  = 8,

        -- Measured from INSIDE quickshell's frame, not from the screen edge:
        -- Frame.qml draws a 4px border and reserves that space, so a window
        -- sits frame + gaps_out from the edge. This used to be kept minimal
        -- (8/4) on the argument that the frame already separates windows from
        -- the edge; it was raised for a floating, airier look, previewed live
        -- and chosen over 12/8 and 24/20. (An old value of 20 on all sides was
        -- too much.) If you ever stop running quickshell, add the 4px back.
        --
        -- Per-side, in CSS order. Top and bottom get more room than the sides
        -- because they are the crowded ones: the top edge carries the 38px bar
        -- rather than a 4px strip, so the same gap reads as tighter there, and
        -- matching the bottom to it keeps the window visually centred in the
        -- well instead of riding low.
        gaps_out = { top = 16, right = 12, bottom = 16, left = 12 },

        -- No window borders. The quickshell frame already draws the outline of
        -- the screen, and gaps_in/gaps_out separate the windows from each
        -- other, so a per-window border was a third edge doing the same job.
        --
        -- TRADEOFF: the active/inactive gradient below is what marked the
        -- focused window, and with no border to paint it on, nothing does.
        -- Put this back to 2 if you lose track of focus; the colours are still
        -- configured and will take effect again immediately.
        border_size = 0,

        col = {
            active_border   = {
                colors = { colors.border_active_a, colors.border_active_b },
                angle  = 45,
            },
            inactive_border = colors.border_inactive,
        },

        -- Resize windows by dragging their borders and the gaps around them.
        resize_on_border = false,

        -- Tearing trades visual correctness for latency in fullscreen games.
        -- Read the wiki before enabling:
        -- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/
        allow_tearing = false,

        -- "dwindle" | "master" | "scrolling"
        layout = "scrolling",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = colors.shadow,
        },

        -- Blur is the most expensive effect here. If battery life matters
        -- more than looks, this is the first thing to turn off - it runs on
        -- every frame that has a translucent surface over something.
        blur = {
            enabled   = true,
            size      = 3,
            passes    = 1,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})


-- -------------------------------------------------------------------------
-- Animation curves
-- -------------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
--
-- These must be defined before the hl.animation() calls that reference them
-- by name, which is why look.lua is required early from hyprland.lua.

-- Beziers. The two points are the control points of a cubic curve from (0,0)
-- to (1,1). Pulling the FIRST point's y up near 1 early is what makes a
-- motion feel "snappy": most of the distance is covered in the first few
-- frames, then it eases into place.

-- Nearly all the travel happens immediately, then a short settle. This is the
-- workhorse for anything that should feel instant.
hl.curve("snappy",       { type = "bezier", points = { {0.05, 0.9},  {0.1, 1.0}  } })

-- Slightly gentler: still front-loaded, but with a visible glide at the end.
-- Better for larger surfaces where "instant" reads as a jump-cut.
hl.curve("easeOutFast",  { type = "bezier", points = { {0.16, 1},    {0.3, 1}    } })

hl.curve("linear",       { type = "bezier", points = { {0, 0},       {1, 1}      } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}   } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},    {0.1, 1}    } })

-- Springs are physical rather than time-based, so their `speed` is ignored -
-- duration falls out of the physics. This is what produces "fluid" motion:
-- the window decelerates naturally instead of following a fixed timeline.
--
-- Damping ratio zeta = dampening / (2 * sqrt(stiffness * mass)) decides feel:
--   zeta < 1   underdamped - overshoots and settles back (bouncy)
--   zeta = 1   critically damped - fastest approach with no overshoot
--   zeta > 1   overdamped - sluggish, never overshoots
--
-- Raising stiffness is what makes a spring faster; dampening must rise with
-- it to keep the same character.

-- zeta = 34 / (2*sqrt(420)) = 0.83 - quick, with just enough overshoot to
-- read as alive rather than mechanical. Default for windows.
hl.curve("snap",   { type = "spring", mass = 1, stiffness = 420, dampening = 34 })

-- zeta = 24 / (2*sqrt(350)) = 0.64 - noticeably bouncier. Swap "snap" for
-- this on windowsIn if you want more character on window open.
hl.curve("bouncy", { type = "spring", mass = 1, stiffness = 350, dampening = 24 })

-- zeta = 39 / (2*sqrt(380)) = 1.0003 - critically damped: the fastest
-- approach that never overshoots.
--
-- OVERSHOOT IS FINE ON POSITION AND WRONG ON SIZE, which is why this exists
-- alongside "snap". A window sliding past its place and coming back reads as
-- weight. A window scaling past its size does not: every glyph inside it is
-- being resampled, so the overshoot arrives as a frame or two of blurred,
-- wrong-sized text and then a correction. That is the "clonky" part of an
-- open or close, and no amount of tuning the duration fixes it - the defect
-- is the direction reversing at all.
--
-- STIFFNESS IS THE SPEED KNOB. Settling time is roughly 4 / sqrt(stiffness):
-- 380 settles in about 205ms, 1100 in about 120ms. Dampening has to rise with
-- it to hold zeta at 1 - it is 2 * sqrt(stiffness) for critical damping - or
-- raising the stiffness alone just makes it bouncy instead of fast.
hl.curve("glide",  { type = "spring", mass = 1, stiffness = 1100, dampening = 66 })


-- -------------------------------------------------------------------------
-- Animations
-- -------------------------------------------------------------------------
-- "leaf" names a node in Hyprland's animation tree; children inherit from
-- parents unless overridden. Set animations.enabled = false above to kill all
-- of them at once without editing this list.

-- speed is in DECISECONDS: speed = 2 means 200ms. Lower is faster.
-- Springs ignore speed entirely - see the note above the curve definitions.
--
-- Target feel: window operations land in ~150-250ms, fades in under 100ms.
-- Much below that and motion stops reading as motion and becomes a jump-cut,
-- which paradoxically feels less responsive because you lose track of what
-- moved where.

hl.animation({ leaf = "global",        enabled = true,  speed = 3,    bezier = "snappy" })
hl.animation({ leaf = "border",        enabled = true,  speed = 2,    bezier = "easeOutFast" })

-- Windows use the spring, so the settle is driven by the physics above rather
-- than by a fixed timeline. NOTE: `speed` is still a REQUIRED field even for
-- spring animations - omitting it is a config error - so it is supplied here
-- and simply carries little weight compared to stiffness/dampening.
-- ONE CURVE FOR THE WHOLE GESTURE. Opening a window in a tiling layout is
-- not one animation, it is two: the new window arrives and every neighbour
-- resizes to make room. Those used to run on different curves - the arrival
-- on an underdamped spring, the re-tile on the same spring but a different
-- distance - so the screen settled in stages, which is most of what read as
-- clonky. They share "glide" now and land together.
hl.animation({ leaf = "windows",       enabled = true,  speed = 2.0,  spring = "glide" })

-- popin 85%. Deeper than the original 90% so the growth is legible as
-- motion, but not the 80% tried alongside the slower spring: the shorter the
-- animation, the less distance it can cover before the travel itself starts
-- to look like a flicker.
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 2.0,  spring = "glide",        style = "popin 85%" })

-- Closing keeps a fixed timeline rather than the spring: a window on its way
-- out should not decelerate into a place it is not going to be. 90ms on the
-- front-loaded curve, and fadeOut below is set to the same so the window does
-- not become invisible partway through shrinking and leave the rest of the
-- animation playing to nobody - which it did at 60ms against 100ms.
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 0.9,  bezier = "snappy",       style = "popin 90%" })

-- Fades are the most latency-sensitive thing here: they gate how quickly a
-- new window appears to exist. Keep these short.
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 0.5,  bezier = "snappy" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 0.9,  bezier = "snappy" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 1.0,  bezier = "snappy" })

-- Layer surfaces: bars, launchers, notification popups. Once Quickshell
-- exists these govern how its panels appear.
hl.animation({ leaf = "layers",        enabled = true,  speed = 1.5,  bezier = "easeOutFast" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 1.5,  bezier = "easeOutFast",  style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.0,  bezier = "snappy",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.0,  bezier = "snappy" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 0.8,  bezier = "snappy" })

-- Workspace switching. style = "fade" cross-fades; "slide" pushes the old
-- workspace off-screen, which reads as more fluid but is heavier to render.
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.5,  bezier = "easeOutFast",  style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.3,  bezier = "easeOutFast",  style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.3,  bezier = "easeOutFast",  style = "fade" })

hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 3,    bezier = "quick" })


-- -------------------------------------------------------------------------
-- Layouts
-- -------------------------------------------------------------------------
-- Only the one named by general.layout above is active; the others are
-- configured here so switching is a one-word change.

-- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
hl.config({
    dwindle = {
        preserve_split = true,
    },
})

-- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/
hl.config({
    master = {
        new_status = "master",
    },
})

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
--
-- THIS IS THE ACTIVE LAYOUT (general.layout above).
--
-- Windows form an infinite horizontal strip of columns. Instead of splitting
-- the screen ever smaller, new windows extend the strip and the viewport
-- scrolls to follow focus. Values below are Hyprland's own defaults, written
-- out explicitly so they are visible and easy to tune.
hl.config({
    scrolling = {
        -- Fraction of the screen a new column occupies. 0.5 = half width, so
        -- two columns fill the screen.
        column_width = 0.5,

        -- Which way the strip grows when a window opens: "right" or "left".
        direction = "right",

        -- Widths cycled through when resizing a column. Handy set: a third,
        -- a half, two thirds, full.
        explicit_column_widths = "0.333, 0.5, 0.667, 1.0",

        -- How the viewport positions itself around the focused column.
        focus_fit_method = 1,

        -- Scroll the viewport automatically to keep focus visible.
        follow_focus = true,

        -- Minimum fraction of the focused column that must stay on screen
        -- before the viewport scrolls to follow it.
        follow_min_visible = 0.4,

        -- A lone column behaves as fullscreen (no gaps/borders wasted).
        fullscreen_on_one_column = true,

        -- Moving focus past either end wraps around to the other end,
        -- rather than stopping.
        wrap_focus = true,
        wrap_swapcol = true,
    },
})


-- -------------------------------------------------------------------------
-- Misc
-- -------------------------------------------------------------------------

hl.config({
    misc = {
        -- No built-in mascot wallpaper or logo. Quickshell draws the real
        -- wallpaper (quickshell/Wallpaper.qml), so for the second a quickshell
        -- restart takes there is nothing on the background layer, and
        -- Hyprland paints background_color instead. bin/theme.sh keeps that at
        -- the theme's own background, so a restart shows a plain field of the
        -- right colour rather than anime art. This value is the dark theme's,
        -- for the moment before theme.sh has run.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = "rgb(11111b)",
    },
})
