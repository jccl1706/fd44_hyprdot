-- =========================================================================
-- Window, workspace and layer rules
-- =========================================================================
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
--
-- match fields are Lua patterns matched against window properties. Find the
-- class/title of a running window with:  hyprctl clients


-- -------------------------------------------------------------------------
-- Window rules
-- -------------------------------------------------------------------------

-- Ignore maximize requests from every application. Tiling compositors and
-- app-initiated maximize do not mix well - without this, some GTK and
-- Electron apps fight the layout on startup.
--
-- hl.window_rule returns a handle, so this can be toggled at runtime with
-- suppress_maximize:set_enabled(false).
local suppress_maximize = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Works around a drag-and-drop bug with XWayland clients: the transient,
-- unnamed surface XWayland creates mid-drag would otherwise steal focus and
-- cancel the drag. Now that XWayland is actually installed on this machine,
-- this rule is live rather than theoretical.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Steam's secondary windows float; its main window does not.
--
-- The Steam client is one X11 application that opens a lot of small
-- top-level windows - Friends List, Special Offers, Settings, the screenshot
-- uploader, one per chat - and every one of them arrives as a normal
-- toplevel with class "steam". In a tiling layout they take a column each.
-- Two of them were already doing it within a minute of the first login, which
-- is what prompted this rule.
--
-- `negative:` inverts a match, so this is "class steam, title anything but
-- exactly Steam". Both halves are measured rather than assumed: the class is
-- lowercase `steam` on XWayland (hyprctl clients), and the negative prefix
-- was checked behaviourally with two throwaway windows, because a rule that
-- merely PARSES is not a rule that works - the three other spellings tried
-- were rejected outright as unknown fields, which at least fails loudly.
--
-- Games are unaffected: a launched title gets class steam_app_<id>, not
-- steam.
hl.window_rule({
    name  = "float-steam-popups",
    match = { class = "^steam$", title = "negative:^Steam$" },

    float = true,
})

-- Do not lock the screen in the middle of a game.
--
-- hypridle locks at 5:00 of idle, and "idle" means no input device activity.
-- A gamepad is not one: libinput reports it, but a controller-only session
-- produces no keyboard or pointer events at all, so a two-hour sitting reads
-- as two hours away from the machine. The lock lands on top of the game.
--
-- `idleinhibit fullscreen` inhibits only while the matched window is
-- fullscreen, so a windowed game or the Steam client itself still lets the
-- machine idle normally.
--
-- SCOPED TO GAMES, not to every fullscreen window. The broader rule -
-- class = ".*" - is what most configurations use and it also stops the
-- machine locking behind a fullscreen video or a fullscreen terminal, which
-- is a worse trade than it looks.
--
-- `steam_app_<id>` is the class Steam gives a launched title. VERIFY IT on
-- the machine that games: start something, run `hyprctl clients`, and read
-- the real class. If it differs the rule is simply inert - it fails quietly,
-- which is exactly the failure mode to distrust here.
hl.window_rule({
    name  = "gaming-idle-inhibit",
    match = { class = "^steam_app_%d+$" },

    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name  = "gamescope-idle-inhibit",
    match = { class = "^gamescope$" },

    idle_inhibit = "fullscreen",
})

-- Hyprland's own run dialog (hyprland-guiutils): float it near the bottom
-- left rather than tiling it.
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})


-- -------------------------------------------------------------------------
-- Workspace rules
-- -------------------------------------------------------------------------

-- "Smart gaps" / "no gaps when only one window". Two halves are needed: the
-- workspace rules drop the outer gaps, the window rules drop the border and
-- rounding on the window itself.
--
--   w[tv1]  workspace with exactly one tiled visible window
--   f[1]    workspace with one fullscreen window
--
-- Uncomment all four together - enabling only half looks wrong.
--
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
--
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })


-- -------------------------------------------------------------------------
-- Layer rules
-- -------------------------------------------------------------------------
-- Layer rules target layer-shell surfaces - bars, launchers, notification
-- popups - rather than ordinary windows. This is where Quickshell's surfaces
-- will be tuned once it has a config.
--
-- Inspect live layers with:  hyprctl layers
--
-- hl.layer_rule({
--     name    = "no-anim-overlay",
--     match   = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
--
-- Typical Quickshell rules, for when the bar exists:
--
-- hl.layer_rule({ name = "blur-bar",   match = { namespace = "^quickshell$" }, blur = true })
-- hl.layer_rule({ name = "ignore-bar", match = { namespace = "^quickshell$" }, ignore_alpha = 0.3 })


-- The launcher animates itself: the card slides up out of the bottom frame
-- and the scrim fades, both driven by Qt inside quickshell/Launcher.qml.
--
-- Hyprland's default layersIn/layersOut fade runs on the whole surface at the
-- same time, so the compositor was cross-fading a 1440x960 overlay while Qt
-- was sliding a card inside it. The two animations do not share a curve or a
-- duration, and the result reads as stutter rather than as either animation.
-- Hand the motion entirely to Quickshell.
hl.layer_rule({
    name    = "launcher-no-anim",
    match   = { namespace = "^quickshell-launcher$" },
    no_anim = true,
})


-- NO BLUR ON THE LAUNCHER. It was tried and removed; this note is here so it
-- does not get added back on the assumption that it was simply overlooked.
--
-- A frosted panel looks good, but Hyprland's layer blur applies to the whole
-- SURFACE, not to the parts of it that happen to be painted. The launcher's
-- surface covers the entire screen - it has to, so that clicking anywhere
-- outside the panel dismisses it - so blurring it blurs everything behind it,
-- including the frame. Measured effect on the frame's top edge, which should
-- be a hard 1px line:
--
--     blur off          1.3 px transition, reaching full white
--     blur on           4.5 px transition, never exceeding 246
--
-- and that was true at every x across the screen, not only under the panel.
-- The frame edge visibly turns to mush whenever the launcher opens.
--
-- Neither obvious lever helps. ignore_alpha, which reads like the knob for
-- restricting blur by opacity, disables it outright instead. Removing the
-- scrim so the surface is transparent everywhere except the panel makes it
-- WORSE, not better (5.7-7.0 px) - proof the blur is not alpha-gated at all.
--
-- So it is blur or a crisp frame, and the frame wins: it is on screen all the
-- time, the launcher is not. Theme.panelAlpha still gives the panel its
-- translucency.


-- The WALLPAPER PICKER does get blur, because its surface is not full-screen.
--
-- It deliberately omits ExclusionMode.Ignore, so the bar's and the frame's
-- exclusive zones shrink it to the content well - and a layer's blur reaches
-- only as far as its own surface. The frame sits outside that surface, so it
-- keeps its hard edge while everything behind the picker is blurred.
--
-- This is the same rule that was wrong for the launcher, made right by
-- changing the surface rather than the rule.
hl.layer_rule({
    name  = "wallpaper-picker-blur",
    match = { namespace = "^quickshell-wallpapers$" },
    blur  = true,
})
