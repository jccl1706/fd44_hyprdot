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

-- THE THEME AS WELL AS THE SIZE, and leaving the theme out was a real bug
-- rather than an omission of tidiness.
--
-- With only the size pinned, every toolkit resolves the cursor THEME on its
-- own. They do not all land in the same place, so the pointer was drawn from
-- one cursor set over a Qt surface and another over a GTK one - different
-- images, and different hotspots. Crossing between them moved where the
-- pointer appeared to be, which showed up as the cursor jumping on the way
-- from the desktop onto the bar.
--
-- Adwaita because it is the one theme on this system that actually contains
-- cursors: /usr/share/icons/Adwaita/cursors has 63, while breeze,
-- breeze-dark and default have none at all - they are empty directories that
-- a client can nonetheless "resolve" to.
--
-- It only LOOKED like a mouse fault because a high-resolution mouse crosses
-- those boundaries quickly and often; the trackpad ambles over them and the
-- swap goes unnoticed. Measured before getting here: the mouse delivers
-- 12,644 reports with zero dropouts, and the pointer's coordinates move in
-- continuous 1-2px steps. Nothing was ever moving wrongly - it was being
-- DRAWN differently on either side of a surface edge.
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")
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
--
-- THE ICON BRIDGE RUNS FIRST, IN THE SAME SHELL, and the ordering is the
-- whole reason it is written this way rather than as its own exec_cmd.
-- quickshell resolves icon names through Qt, which in a bare Hyprland
-- session can only see the "hicolor" theme; bin/icon-bridge.sh symlinks the
-- selected theme's categories into a user-level hicolor so those names
-- resolve. Qt reads the theme when it first needs an icon and caches it, so
-- a bridge built after quickshell has started is a bridge quickshell does
-- not see until it restarts.
--
-- bin/theme.sh also builds it, and that runs above - but exec_cmd does not
-- wait, so the two would race. The symlinks survive a reboot, so in practice
-- only the very first login after an install would lose, which is exactly
-- the login where a missing icon looks like a broken install. `;` and not
-- `&&`: a bridge that cannot be built is not a reason to leave the desktop
-- without a shell.
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c '$HOME/.config/hypr/../bin/icon-bridge.sh >/dev/null 2>&1; qs -d'")
end)

-- Audio, on a system that does not start it for us.
--
-- FEDORA NEEDS NONE OF THIS and must not get it twice. There PipeWire and
-- WirePlumber are systemd user services, socket-activated and already running
-- before Hyprland does anything; launching a second pair would have two
-- daemons contending for the same devices. The pgrep guard is what makes this
-- safe to keep in a file every machine reads - it starts them only where
-- nothing already has.
--
-- FreeBSD is that somewhere: there is no systemd, no user session manager and
-- nothing that starts a sound server on login, so without this the bar loads
-- with its volume control connected to nothing. Measured on the T480's FreeBSD
-- install on 2026-09-23: quickshell logged "Failed to connect pipewire
-- context. Errno: 64" until these were running.
--
-- THE SESSION BUS IS NOT STARTED HERE, and cannot usefully be. Notifications
-- and PipeWire both want DBUS_SESSION_BUS_ADDRESS, and a bus launched after
-- the compositor is not in the environment the compositor hands to anything it
-- spawns. On FreeBSD start the whole session under one instead:
--
--     dbus-run-session Hyprland
--
-- which is what the systemd user bus does for us on Fedora.
--
-- THE pgrep GUARD ALONE WAS NOT ENOUGH, and a sweep on 2026-09-24 found out
-- how. It asks whether pipewire is running YET, not whether something else
-- is going to start it - and on Fedora that is a race with socket
-- activation. Hyprland got there first, started pipewire by hand, and when
-- the socket unit fired a moment later its service could not have the socket
-- and died: pipewire.service and pipewire.socket sat "failed" for fifteen
-- hours with working audio behind them, supervised by nothing.
--
-- So the question is now whether SYSTEMD OWNS IT, not whether it happens to
-- be up. `systemctl --user -q is-enabled` answers that, and fails on a
-- machine with no systemd at all - which is the case this exists for.
--
-- AND `pgrep -q` WAS NEVER A GUARD ON LINUX. procps-ng has no -q; it prints
-- its usage and exits non-zero, so the `||` fell through and this started a
-- second pipewire on every single login no matter what was already running.
-- FreeBSD's pgrep does have -q, which is where it will have come from - this
-- block exists for FreeBSD - and it looked right on both. `-x` with the
-- output thrown away is the spelling that works on either.
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c 'systemctl --user -q is-enabled pipewire.socket 2>/dev/null "
             .. "|| pgrep -x pipewire >/dev/null 2>&1    || pipewire &'")
    hl.exec_cmd("sh -c 'systemctl --user -q is-enabled wireplumber.service 2>/dev/null "
             .. "|| pgrep -x wireplumber >/dev/null 2>&1 || wireplumber &'")

    -- The idle daemon, on the same terms and for the same reason.
    --
    -- NOTHING IN THIS REPOSITORY STARTED IT UNTIL NOW, which went unnoticed
    -- because Fedora's hypridle package ships a user unit and it had been
    -- enabled here by hand - a state no checkout carries. nixpkgs ships the
    -- same unit with `preset: ignored`, so on the desktop it sat
    -- "inactive (dead)" with no journal entries at all and the screen never
    -- locked, for as long as that machine has existed. Found on 2026-09-24
    -- after more than half an hour of an idle desktop that stayed unlocked.
    --
    -- hypridle is NOT one of the binaries nixpkgs wraps - its comm is plain
    -- `hypridle`, read off the running process rather than assumed, unlike
    -- Hyprland and quickshell - so one spelling is enough here.
    hl.exec_cmd("sh -c 'systemctl --user -q is-enabled hypridle.service 2>/dev/null "
             .. "|| pgrep -x hypridle >/dev/null 2>&1   || hypridle &'")

    -- The EVO4's own output, which the card brings up at 0 - see
    -- bin/evo4-gain.sh. Nothing else sets it: WirePlumber is told to leave
    -- that control alone (wireplumber.conf.d/51-evo4-soft-mixer.conf) and
    -- this machine has no alsa-restore to carry it across a reboot, so the
    -- gaming desktop booted silent every time while every software indicator
    -- said 95%.
    --
    -- Here rather than in a unit of its own because it has to happen after
    -- the card exists and after PipeWire has claimed it, and it costs one
    -- `[[ -d /proc/asound/EVO4 ]]` on a machine that has no such card.
    hl.exec_cmd("$HOME/.config/hypr/../bin/evo4-gain.sh")
end)

-- NOTE: do not try to quit Plymouth from here.
--
-- Plymouth holds DRM master on the GPU, which is why plymouth-quit-wait.service
-- is ordered Before=getty@tty1.service: the display must be handed over before
-- any compositor starts. Masking those units so the splash outlives
-- graphical.target deadlocks the boot - Hyprland dies immediately with
-- "CBackend::create() failed!" because it cannot acquire DRM master, and then
-- nothing is left running to dismiss the splash.
