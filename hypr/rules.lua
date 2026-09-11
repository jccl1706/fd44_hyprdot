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
