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

-- Everything that is not an internal panel: no scaling, and placed to the LEFT
-- of whatever else is already there.
--
-- `auto-left` rather than `auto`, and that is a preference rather than a
-- default. With `auto` Hyprland puts each new output to the RIGHT of the ones
-- placed before it, so an external display landed to the right of the laptop
-- panel - which has it backwards. The external is the large screen and the one
-- being looked at; the laptop panel is the thing beside it.
--
-- IT PUTS THE EXTERNAL AT A NEGATIVE X. Measured with the Framework and a
-- 2560x1440 LG: the panel keeps 0,0 and the LG lands at -2560,0. That is
-- ordinary in Hyprland and nothing in this config cares, but it is worth
-- knowing when reading `hyprctl monitors`, and when handing coordinates to
-- something like grim, which will want the negative numbers too.
--
-- ON A MACHINE WITH ONE MONITOR IT STILL SHIFTS, which is not what this
-- comment first claimed. `auto-left` does not mean "left of the others if
-- there are any" - it places the output left of the origin regardless, so the
-- desktop's single 2560x1440 display sits at -2560,0 rather than 0,0.
-- Measured on fedora-hypr once it was next booted:
--
--   Monitor DP-1  2560x1440@143.97  at -2560x0
--
-- Harmless in use: Hyprland works in negative coordinates, and layer surfaces,
-- wallpapers and window placement are all per-output. What it does change is
-- anything given coordinates by hand - `grim -g "0,0 300x40"` on that machine
-- captures nothing at all, because nothing is there.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto-left",
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
-- eDP-1. `desc:` matches the panel's make and model instead, spelled EXACTLY
-- as the description `hyprctl monitors` prints - which is not always the EDID's
-- three-letter maker code. Hyprland expands the codes it knows: the T480's
-- EDID says AUO, its description says "AU Optronics", and a rule written
-- "desc:AUO 0x213D" silently matched nothing (the panel came up at 1). The
-- match is a prefix, so a serial number after the model does not break it.
--
-- The target is about 125-130 effective px per inch, so text is the same
-- physical size on every machine:
--
--   Framework 13  BOE 0x0BCA           2256x1504 13.5"  ~201 ppi  1.57 -> 1440x960  ~128
--   ThinkPad T480 AU Optronics 0x213D  1920x1080 13.9"  ~158 ppi  1.25 -> 1536x864  ~126
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
    output   = "desc:AU Optronics 0x213D",   -- ThinkPad T480, 14" FHD
    mode     = "preferred",
    position = "auto",
    scale    = "1.25",
})

-- The living-room TV, which is a different problem from a monitor: not pixel
-- density, but viewing distance. An LG 4K set at sofa range is about 3 m away
-- against 50 cm for a laptop panel, so text needs to be several times larger
-- in physical terms even though the panel is far less dense.
--
-- Scale 2 - 3840x2160 becomes 1920x1080 logical. It divides exactly, so
-- Hyprland has nothing to snap and none of the fractional-scale seams apply.
--
-- `desc:` rather than HDMI-A-1, for the same reason as the panels above: the
-- connector name says where a cable is plugged, not what is on the end of it,
-- and HDMI-A-1 on another machine is somebody's monitor.
--
-- NOT "auto", and this is why: the set's EDID claims a physical size of
-- 1600x900 mm, which is a lie no 4K television is - anything deriving DPI from
-- it lands somewhere arbitrary. Televisions misreport this routinely.
--
-- This only shows on the desktop. Couch mode runs Steam under gamescope, which
-- owns the display and does its own scaling; this is what you get when Hyprland
-- is on the TV instead - deliberately, or because the couch session failed to
-- start and the login hook fell back to it.
hl.monitor({
    output   = "desc:LG Electronics LG TV SSCR2",
    mode     = "preferred",
    position = "auto",
    scale    = "2",
})

-- The display dummy, for streaming. A DisplayPort dongle with an EDID and no
-- screen: it gives the card a second output to scan out to, which is what
-- Sunshine captures when a game is streamed to the laptop.
--
-- IT HAS TO BE A LIVE MONITOR, not a disabled one, and that is not the
-- obvious choice. A dummy plug is usually there so a headless machine has
-- somewhere to draw; the instinct is to hide it from the desktop so windows
-- do not wander onto a screen nobody can see. That instinct is wrong here:
-- a disabled output has no CRTC, nothing scans out on it, and there is
-- nothing for KMS capture to read. No monitor, no stream.
--
-- gamescope cannot simply take the connector instead, because its DRM
-- backend takes DRM master over the WHOLE CARD - which is why couch mode
-- replaces the desktop session rather than running beside it. The streaming
-- session is therefore gamescope NESTED, an ordinary Wayland client,
-- fullscreened onto this monitor. See modules/streaming.nix in fd44_nixos.
--
-- IT IS NOT THE DONGLE'S OWN EDID. fd44_nixos replaces it through
-- drm.edid_firmware with one built by firmware/make-edid.py, which is why
-- this rule matches "The Linux Foundation fd44 stream" rather than the
-- dongle's "Telecom Technology Centre Co. Ltd. DP1080P60". Change that
-- override and this line has to change with it - a mismatched desc matches
-- nothing, silently, and the output lands on 640x480.
--
-- 1920x1280 BECAUSE IT IS 3:2, like the laptop panel being streamed to
-- (2256x1504). The dongle's own best mode is 1920x1200, which is 16:10, so
-- the picture arrives letterboxed; at 3:2 it fills the screen, and with more
-- pixels than the 16:10 mode rather than fewer.
--
-- The panel's own 2256x1504 would be better still and is not available: this
-- connector has a pixel-clock ceiling somewhere around 180 MHz - two
-- DisplayPort lanes at HBR - and that mode needs 224. The evidence is in what
-- the dongle's own EDID got away with: its 1920x1080 @ 60 (148.5 MHz) was
-- accepted and its 2560x1440 and 2560x1600 timings (241.5 and 268.5 MHz)
-- were dropped without a word, which is what made it look like it was lying.
-- The replacement EDID carries 1800x1200 and 1920x1200 as fallbacks, so a
-- link that will not carry 164 MHz still comes up with something sane.
--
-- Matching the DEVICE and not the socket, for a reason that was measured
-- rather than assumed: this dongle was read on DP-3 and then, after being
-- moved, on DP-1 with a byte-identical EDID. The connector name follows the
-- socket. This rule follows the dongle.
--
-- The catch-all above puts it to the left, so it sits off the far edge of
-- the television rather than anywhere the pointer passes by accident. It is
-- still a real screen the pointer can reach - the cost of having something
-- to capture.
--
-- This mode must match streamW/streamH in fd44_nixos's modules/streaming.nix
-- and the resolution Moonlight asks for. Any disagreement gets silently
-- absorbed by something rescaling, which is the softness all this is for.
hl.monitor({
    output   = "desc:The Linux Foundation fd44 stream",
    mode     = "1920x1280@60",
    position = "auto-left",
    scale    = "1",
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

-- Scales chosen in the Display page of quickshell's settings, if any have
-- been. Written by quickshell/Monitors.qml, per machine, and not in git.
--
-- LAST, SO IT WINS. Hyprland applies monitor rules in order and the last one
-- matching an output takes effect - the same rule the catch-all at the top of
-- this file depends on. A scale picked in the settings therefore beats the
-- hand-measured one above without either having to know about the other.
--
-- pcall because the file does not exist until something is chosen, and a
-- missing require is a hard error that would take the whole config with it.
--
-- To keep a value permanently, move its hl.monitor block up into this file
-- where it will be read by a person, and delete monitors_local.lua. The two
-- panels above were measured that way and are better for it.
pcall(require, "monitors_local")
