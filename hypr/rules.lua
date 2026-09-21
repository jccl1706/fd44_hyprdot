-- =========================================================================
-- Window, workspace and layer rules
-- =========================================================================
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
--
-- match fields are REGULAR EXPRESSIONS, not Lua patterns, despite this being
-- a Lua file. `%d` is a literal "%d" to the matcher; a digit is `\d`, which
-- inside a Lua string is written "\\d". Checked behaviourally - two probe
-- windows, one rule each, and only the regex spelling matched. Anything valid
-- in both syntaxes (^kitty$, .*) hides the difference, which is how this note
-- used to say "Lua patterns" and nobody noticed until a rule needed a
-- character class. Find the class/title of a running window with:
--   hyprctl clients


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

-- The Steam client lives on workspace 5, floating.
--
-- Steam is one X11 application that opens a lot of small top-level windows -
-- Friends List, Special Offers, Settings, the screenshot uploader, one per
-- chat - and every one of them arrives as a normal toplevel with class
-- "steam". In a tiling layout they take a column each; two were already
-- doing it within a minute of the first login. Giving the whole client a
-- workspace of its own and floating it keeps the store, the library and
-- every popup out of the way of actual work.
--
-- The class is measured, not assumed: lowercase `steam`, on XWayland, per
-- hyprctl clients against a running client.
--
-- GAMES ARE DELIBERATELY NOT MATCHED, so a game is never forced to float. A
-- game does still OPEN on workspace 5 in practice - not because of this rule,
-- but because misc:initial_workspace_tracking (on by default) places a window
-- on the workspace of the process that launched it, and every game descends
-- from the Steam client: GameThread <- reaper <- steam, measured.
hl.window_rule({
    name  = "steam-workspace",
    match = { class = "^steam$" },

    workspace = "5",
    float     = true,
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
-- `steam_app_<id>` is the class Steam gives a launched title - measured
-- against ARC Raiders on the RX 9070 XT desktop: steam_app_1808500, on
-- XWayland. Do not key anything on a game's title: that one fills its title
-- with zero-width characters, presumably to defeat overlays that read it.
--
-- `\d`, NOT `%d` - see the note at the top of this file. This rule first
-- shipped as `%d+`, loaded without a single error, and matched nothing: the
-- game sat in true fullscreen for four minutes reporting inhibitingIdle=false.
hl.window_rule({
    name  = "gaming-idle-inhibit",
    match = { class = "^steam_app_\\d+$" },

    idle_inhibit = "fullscreen",
})

hl.window_rule({
    name  = "gamescope-idle-inhibit",
    match = { class = "^gamescope$" },

    idle_inhibit = "fullscreen",
})

-- Nautilus, translucent like the terminal.
--
-- 0.92 is kitty's `term_opacity`, deliberately the same number: two windows
-- side by side at different opacities over one wallpaper reads as a mistake
-- rather than a choice.
--
-- A COMPOSITOR RULE, NOT GTK CSS, and that distinction was learned the hard
-- way. GTK can draw a translucent window by making libadwaita's own
-- window_bg_color translucent in ~/.config/gtk-4.0/gtk.css - and doing that
-- costs the live light/dark switch, because GTK reads that file once at
-- startup and pinning its named colours leaves libadwaita nothing to swap
-- when the scheme changes. Hyprland blends the whole surface without Nautilus
-- knowing anything about it, so the theme switch stays instant.
--
-- Only Nautilus, not every GTK4 app: a blanket rule would catch dialogs and
-- pickers where translucency is a nuisance rather than a look. Another app is
-- another rule, and one line.
hl.window_rule({
    name  = "nautilus-translucent",
    match = { class = "^org.gnome.Nautilus$" },

    opacity = 0.92,
})

-- Hyprland's own run dialog (hyprland-guiutils): float it near the bottom
-- left rather than tiling it.
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- btop's scratchpad terminal (SUPER + `, see binds.lua; launched by the
-- special:btop workspace rule below). Floating and centred, big enough for
-- btop's full layout - CPU graph, memory, network and the process list - to
-- fit without it collapsing panels.
hl.window_rule({
    name  = "btop-scratchpad",
    match = { class = "^btop$" },

    float  = true,
    size   = "monitor_w*0.6 monitor_h*0.7",
    center = true,
})

-- File dialogs (Open File, Save File) that apps hand to the GTK portal -
-- Chromium's, for one. GTK remembers the chooser's last size, 1203x925, and
-- asks for it every time: on the laptop (1440x960 logical at scale 1.567)
-- that plus the shadow is taller than the screen, and the header with Cancel
-- and Open sat under the bar. Size it to the monitor instead, centred.
hl.window_rule({
    name  = "portal-file-dialog",
    match = { class = "^xdg-desktop-portal-gtk$" },

    float  = true,
    size   = "monitor_w*0.6 monitor_h*0.7",
    center = true,
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
--
-- (The btop scratchpad's rule is further down, after this commented block.)
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

-- THE STREAMING DUMMY IS GONE. Workspace 9 used to be pinned to
-- "desc:Telecom Technology Centre Co. Ltd. DP1080P60", a display dummy plugged
-- into the old living-room desktop so Sunshine had a screen to capture, with a
-- window rule putting gamescope on it fullscreen.
--
-- That machine runs SteamOS now and streaming.nix was deleted from fd44_nixos,
-- so the dummy exists on no machine this config runs on - checked on both: the
-- Framework reports only BOE 0x0BCA and gaming-pc00 only the UltraGear.
--
-- It was not harmless while it lasted. A workspace pinned to a monitor that is
-- not present becomes an ORPHAN, and quickshell's bar treats orphans as
-- workspaces inherited from an unplugged screen - so the rule put a phantom 9
-- into the reckoning on machines that never had the dummy.

-- ORDER MATTERS, AND THIS BLOCK IS DELIBERATELY LAST. Workspace 9 is named
-- both here and by the streaming-dummy rule above, and the later rule wins:
-- with this block first, SUPER + 9 on the laptop followed the dummy rule to a
-- monitor that is not connected and fell back to whatever had focus. Measured
-- exactly that way round before moving it.
--
-- The consequence is that the dummy rule no longer decides workspace 9
-- anywhere. That costs nothing today - the Sunshine stack it served lived in
-- fd44_nixos, and that install has been replaced by SteamOS - but if streaming
-- is ever rebuilt, give the dummy a workspace outside 1-9 rather than moving
-- this block back.
-- Workspaces pinned to screens: 1-5 on the external, 6-9 on the laptop panel.
--
-- WITHOUT THESE, HYPRLAND BINDS A WORKSPACE TO WHICHEVER MONITOR HAPPENED TO
-- BE FOCUSED WHEN IT WAS FIRST OPENED, and it stays there. That is not a bug,
-- but it means a number means a different screen depending on where you were
-- standing when you first pressed it - and because focusing an existing
-- workspace moves the focus to ITS monitor rather than dragging the workspace
-- over, SUPER + 2 would throw the keyboard onto the other screen unpredictably.
-- Pinned, a number always means the same physical screen.
--
-- THE PANEL BY CONNECTOR NAME, THE EXTERNAL BY DESCRIPTION, and the asymmetry
-- is deliberate - the same reasoning as monitors.lua. eDP-1 IS the internal
-- panel by definition and both laptops call theirs that, so the name is the
-- portable way to say "the built-in screen". An external's connector name says
-- only which socket a cable is in: this monitor read as DP-2 today and would
-- be DP-1 or DP-3 plugged in elsewhere. `desc:` follows the display instead.
-- The match is a prefix, so the serial number Hyprland appends does not need
-- to be written out.
--
-- ON A MACHINE WITH ONLY ONE SCREEN THESE DO NOT BITE, and that was measured
-- rather than assumed: a brand-new workspace pinned to
-- "desc:No Such Monitor 9999" opened on the focused monitor, with no error and
-- no complaint. So the desktop - one monitor, no eDP-1, no UltraGear - behaves
-- exactly as it did before. That is what keeps this config portable rather
-- than this laptop's config.
--
-- EXISTING WORKSPACES DO NOT MIGRATE. A rule is applied when a workspace is
-- created, so anything already open stays on the monitor it was born on until
-- it is emptied and reopened, or Hyprland restarts. Adding these rules moves
-- nothing that is already on screen.
-- THE LOW NUMBERS GO TO THE BIG SCREEN, which is the way round that matches
-- how the keyboard is actually used: 1-5 are the reachable keys and get the
-- 2560x1440 external, while 6-9 fall back to the 13" panel for whatever is
-- being kept to one side. The other way round put the main working workspace
-- on the smaller screen and left the external empty.
-- ONLY ON A MACHINE THAT HAS BOTH SCREENS, which is the validation this block
-- was missing. It splits nine workspaces across a laptop panel and an external,
-- and that only makes sense where a laptop panel exists.
--
-- It went wrong on gaming-pc00, which has the same UltraGear on its desk but no
-- eDP-1 at all. 1-5 pinned to the monitor correctly; 6-9 pinned to a connector
-- that will never appear, and a workspace pinned to an absent monitor is an
-- ORPHAN. quickshell's bar reads orphans as workspaces inherited from a screen
-- that was unplugged - reasonable when an external really has been removed, and
-- permanently wrong here, because eDP-1 is not coming back. The bar showed 6-9
-- and nothing else.
--
-- The test is whether the kernel exposes an eDP connector at all, not whether
-- one is connected: a laptop has the connector even with the lid shut, and a
-- desktop has none. Read from /sys/class/drm rather than asked of Hyprland,
-- because this runs while the config is parsed. Checked both ways - the
-- Framework has card1-eDP-1, gaming-pc00 has no eDP entry of any kind.
--
-- With no pinning at all, the bar falls back to showing 1-5 and every workspace
-- still works on the single monitor. That is the single-screen behaviour this
-- config had before the split was added.
local function has_internal_panel()
    -- The card number is not fixed, so try a few rather than hardcode card1.
    for card = 0, 4 do
        for idx = 1, 2 do
            local f = io.open(("/sys/class/drm/card%d-eDP-%d/status"):format(card, idx))
            if f then
                f:close()
                return true
            end
        end
    end
    return false
end

if has_internal_panel() then
    for i = 1, 5 do
        hl.workspace_rule({
            workspace = tostring(i),
            monitor   = "desc:LG Electronics LG ULTRAGEAR",
        })
    end

    for i = 6, 9 do
        hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1" })
    end
end

-- The btop scratchpad (SUPER + `). Whenever special:btop is opened with
-- nothing on it - the first press after login, or after quitting btop - this
-- starts it, in a kitty whose class the "btop-scratchpad" window rule above
-- floats and centres.
--
-- btop is not part of the base install. Rather than a terminal that flashes
-- open and shut, a machine without it gets a window saying how to add it.
hl.workspace_rule({
    workspace        = "special:btop",
    -- The advice is per-distribution, because this config runs on two systems
    -- and "sudo dnf install btop" is wrong on one of them - btop is not
    -- installed on nixos-gaming00, so that is the message that would actually
    -- have appeared there.
    on_created_empty = [[kitty --class btop -e sh -c 'command -v btop >/dev/null && exec btop || { . /etc/os-release 2>/dev/null; case "$ID" in fedora) hint="sudo dnf install btop" ;; nixos) hint="add btop to fd44_nixos modules/packages.nix, then nixos-rebuild switch" ;; arch) hint="sudo pacman -S btop" ;; debian|ubuntu) hint="sudo apt install btop" ;; *) hint="install btop with your package manager" ;; esac; printf "btop is not installed.\n\n    %s\n\nPress Enter to close." "$hint"; read -r _; }']],
})


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

-- The bar's drop-down panels (quickshell/DropPanel.qml - audio, network) are
-- the same arrangement - a full-screen overlay whose card slides down out of
-- the bar - so the same reasoning applies.
hl.layer_rule({
    name    = "drop-panels-no-anim",
    match   = { namespace = "^quickshell-(audio|network)$" },
    no_anim = true,
})

-- The wallpaper (quickshell/Wallpaper.qml) crossfades itself, from the theme's
-- background colour at login and from one image to the next after that. A
-- compositor fade of the whole surface on top of it would run the same fade
-- twice on different curves.
hl.layer_rule({
    name    = "wallpaper-no-anim",
    match   = { namespace = "^quickshell-wallpaper$" },
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
