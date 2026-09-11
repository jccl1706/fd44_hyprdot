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
-- What is genuinely NOT running yet:
--   hyprpaper - installed but not started, so there is no wallpaper daemon
--
-- Add it here once it is wanted:
--
-- hl.on("hyprland.start", function()
--     hl.exec_cmd("hyprpaper")
-- end)


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
