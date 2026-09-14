-- =========================================================================
-- Environment, permissions and startup programs
-- =========================================================================


-- -------------------------------------------------------------------------
-- Environment variables
-- -------------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
--
-- NOTE: this session is started by uwsm, which exports most of the important
-- variables (XDG_CURRENT_DESKTOP, XDG_SESSION_TYPE, WAYLAND_DISPLAY) into the
-- systemd user environment before Hyprland runs. Variables set here reach
-- Hyprland and anything it spawns, but NOT systemd user services that started
-- earlier. Put anything a user service needs into uwsm's environment instead
-- (~/.config/uwsm/env), not here.

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


-- -------------------------------------------------------------------------
-- Permissions
-- -------------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
--
-- Permission changes need a full Hyprland restart - they are deliberately not
-- applied by `hyprctl reload`, for obvious reasons.
--
-- Turning enforce_permissions on means screen capture, plugin loading and
-- similar privileged protocols are denied unless explicitly allowed below.
-- Leave it off until you know which binaries need entries, or screen sharing
-- will silently stop working.
--
-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })
--
-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


-- -------------------------------------------------------------------------
-- Startup programs
-- -------------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Basics/Autostart/
--
-- What already starts WITHOUT anything here, because uwsm and XDG autostart
-- handle them - do not duplicate these or you will get two of each:
--   hypridle              (idle -> lock -> dpms off)
--   hyprpolkitagent       (the polkit authentication dialog)
--   xdg-desktop-portal + -gtk + -hyprland
--   pipewire, wireplumber, pipewire-pulse
--   Xwayland              (spawned by Hyprland on demand)
--
-- Wallpaper. Quickshell draws it (quickshell/Wallpaper.qml) - there is no
-- wallpaper daemon. bin/wallpaper.sh remembers which one in ~/.local/state,
-- and quickshell watches that file.
hl.on("hyprland.start", function()
    -- Lock straight away on a machine whose disk is not encrypted: it
    -- autologins, so otherwise switching it on is a way in. On a LUKS machine
    -- the boot passphrase already guards the autologin and this does nothing.
    -- First, so nothing below is ever on screen unlocked. See
    -- bin/lock-at-login.sh.
    hl.exec_cmd("sh -c '$HOME/.config/hypr/../bin/lock-at-login.sh'")

    -- Make sure a wallpaper is chosen: on a first login this picks the
    -- default, and it replaces one that has since been deleted. Nothing waits
    -- on it - quickshell shows the choice whenever the file appears.
    hl.exec_cmd("sh -c '$HOME/.config/hypr/../bin/wallpaper.sh restore'")

    -- Refresh the picker's preview thumbnails. Safe to run every login: it
    -- only regenerates previews that are missing or older than their source,
    -- so the steady-state cost is about 80ms. The first run after adding
    -- wallpapers takes a few seconds, in the background, and nothing waits
    -- on it - the picker falls back to the full-size originals until it
    -- finishes.
    hl.exec_cmd("sh -c '$HOME/.config/hypr/../bin/wallpaper.sh thumbs'")

    -- Re-apply the remembered theme.
    --
    -- Most of what a theme switch writes survives a reboot on its own -
    -- gsettings is persistent, kitty's theme.conf is a real file - so this is
    -- not strictly required to come up in the right colours. It is here for
    -- the two cases that are not covered: Hyprland's border and shadow
    -- colours are set with hyprctl at runtime and are gone after a restart,
    -- and a fresh checkout has no palette file at all, so the bar would use
    -- its built-in dark fallback until something wrote one. Running this at
    -- every login makes a half-configured machine correct itself.
    hl.exec_cmd("sh -c '$HOME/.config/hypr/../bin/theme.sh restore'")
end)


-- Quickshell: the bar, the screen frame and the application launcher
-- (quickshell/). Without this nothing draws them, and Super+Space - which is
-- an IPC call into a RUNNING quickshell rather than a command that starts one
-- - silently does nothing.
--
-- Deliberately a child of Hyprland rather than its own systemd unit: these
-- surfaces belong to this compositor session and should go away with it.
-- Applications launched FROM the launcher are the opposite case and get their
-- own scope via uwsm - see Launcher.qml.
--
-- -d daemonizes, so Hyprland's startup is not held open by it.
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -d")
end)

-- NOTE: do not try to quit Plymouth from here.
--
-- Plymouth holds DRM master on the GPU, which is why plymouth-quit-wait.service
-- is ordered Before=getty@tty1.service: the display must be handed over before
-- any compositor starts. Masking those units so the splash outlives
-- graphical.target deadlocks the boot - Hyprland dies immediately with
-- "CBackend::create() failed!" because it cannot acquire DRM master, and then
-- nothing is left running to dismiss the splash.
