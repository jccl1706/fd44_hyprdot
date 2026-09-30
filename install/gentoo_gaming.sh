#!/usr/bin/env bash
# =========================================================================
# gentoo_gaming.sh - Steam, Proton and the overlay tools, natively
# =========================================================================
#
# Usage:  sudo install/gentoo_gaming.sh [--dry-run]
#
# Run ON the Gentoo machine, after the NVIDIA driver is installed and
# nvidia-smi answers. Everything here depends on that.
#
# STEAM IS NOT IN ::gentoo, which surprises people who expect a distribution
# with this many packages to carry it. It lives in ::steam-overlay, which is
# an official-ish repository maintained in the Gentoo repository list - so
# this enables that repository rather than fetching an ebuild from anywhere
# interesting.
#
# THE 32-BIT PART IS NOT OPTIONAL. Steam's own client is 32-bit and so are
# many games, which is why a native Steam on Gentoo means a multilib system:
# nvidia-drivers has to be built with abi_x86_32 or Proton gets no GL and no
# Vulkan, and that single flag is the difference between games running and a
# black window.

set -euo pipefail

green=$'\033[1;32m'; bold=$'\033[1m'; red=$'\033[1;31m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
die()  { printf '%sgaming:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }

DRY=0
[[ ${1-} == --dry-run ]] && DRY=1
run() { if (( DRY )); then printf '%swould run:%s %s\n' "$dim" "$reset" "$*"; else "$@"; fi; }

(( EUID == 0 )) || die "must run as root"
[[ -f /etc/gentoo-release ]] || die "this is for the Gentoo install, not NixOS"

# --- the driver has to be there first -------------------------------------

command -v nvidia-smi >/dev/null 2>&1 \
    || die "no nvidia-smi - install x11-drivers/nvidia-drivers first"
nvidia-smi -L >/dev/null 2>&1 \
    || die "nvidia-smi cannot talk to the card - fix that before adding Steam on top"
note "driver answers: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader)"

# --- 32-bit, which Steam cannot do without --------------------------------

# THE WHOLE SYSTEM GOES MULTILIB, which is the documented way to run native
# Steam on Gentoo and the end of a losing game. Asking for abi_x86_32 on one
# package makes portage want it on everything that package links against, and
# on a systemd machine that reaches the bottom of the stack: nvidia-drivers,
# then egl-gbm, then pam, then systemd, then xwayland and
# xdg-desktop-portal - six rounds of adding one name and re-running.
#
# ABI_X86="64 32" says it once. Every multilib-capable package builds both,
# no future dependency can surprise us, and the cost is one large rebuild
# rather than an unbounded number of small ones.
# A CIRCULAR DEPENDENCY, BROKEN WHERE PORTAGE POINTS. Going multilib makes
# ncurses want a 32-bit build, and its optional gpm support - a mouse daemon
# for the text console - depends on ncurses in turn:
#
#   * Error: circular dependencies:
#   - sys-libs/ncurses (Change USE: -gpm)
#
# gpm is of no use on a machine whose console exists to launch a compositor,
# so this is off rather than temporarily off.
note "breaking the ncurses/gpm circle"
mkdir -p /etc/portage/package.use
printf 'sys-libs/ncurses -gpm\n' > /etc/portage/package.use/ncurses

note "making the system multilib"
if ! grep -q '^ABI_X86=' /etc/portage/make.conf; then
    printf '\n# Native Steam needs a 32-bit userland; see install/gentoo_gaming.sh.\nABI_X86="64 32"\n' \
        >> /etc/portage/make.conf
    note 'ABI_X86="64 32" added to make.conf'
else
    note "ABI_X86 already set: $(grep '^ABI_X86=' /etc/portage/make.conf)"
fi

note "rebuilding what that changes - this is the long part"
run emerge --getbinpkg --update --deep --newuse --backtrack=100 --autounmask \
    --autounmask-continue --autounmask-keep-keywords=n @world

note "asking for the 32-bit halves that Steam and Proton need"
if (( ! DRY )); then
    mkdir -p /etc/portage/package.use /etc/portage/package.accept_keywords
    cat > /etc/portage/package.use/gaming <<'CONF'
# Steam's client is 32-bit, and so is a great deal of what Proton runs. The
# driver has to provide a 32-bit GL and Vulkan or games start and draw
# nothing.
x11-drivers/nvidia-drivers abi_x86_32
media-libs/mesa abi_x86_32
media-libs/vulkan-loader abi_x86_32
media-libs/libglvnd abi_x86_32

# MangoHud and GameMode are asked for on both ABIs for the same reason: a
# 32-bit game loads the 32-bit overlay or none at all.
games-util/mangohud abi_x86_32
games-util/gamemode abi_x86_32

# THE DRIVER'S OWN DEPENDENCIES NEED IT TOO, which is the part that turns
# this into whack-a-mole: nvidia-drivers[abi_x86_32] requires its EGL
# libraries on the same ABI, and asking for one without the others produces
#
#   - gui-libs/egl-gbm (Change USE: +abi_x86_32)
#   - x11-drivers/nvidia-drivers (Change USE: -abi_x86_32)
#
# which is portage offering to solve it by giving up.
gui-libs/egl-gbm abi_x86_32
gui-libs/egl-wayland abi_x86_32
media-libs/libva abi_x86_32

# AND THE CASCADE BENEATH THEM. A 32-bit library wants 32-bit versions of
# what IT links against, which on a systemd machine reaches the bottom of the
# stack quickly:
#
#   sys-libs/pam (Change USE: +abi_x86_32)
#     required by systemd[abi_x86_32], required by networkmanager
#
# These are the ones that Steam's tree reaches on this profile. They are
# libraries rather than programs: building a second ABI of them costs disk
# and build time, not behaviour.
sys-libs/pam abi_x86_32
sys-apps/systemd abi_x86_32
sys-libs/libcap abi_x86_32
sys-apps/util-linux abi_x86_32
dev-libs/libgcrypt abi_x86_32
dev-libs/libgpg-error abi_x86_32
app-arch/zstd abi_x86_32
sys-libs/libseccomp abi_x86_32
dev-libs/openssl abi_x86_32
sys-apps/dbus abi_x86_32
CONF

    # STEAM'S LICENCE, ACCEPTED BY NAME. Gentoo will not install it silently,
    # and the failure looks like any other mask:
    #
    #   games-util/steam-launcher-1.0.0.87 (masked by: ValveSteamLicense)
    #
    # The same rule as the NVIDIA licence: named per package, so agreeing to
    # Valve's terms does not quietly agree to everything else non-free.
    cat > /etc/portage/package.license/steam <<'CONF'
games-util/steam-launcher ValveSteamLicense
games-util/steam-meta ValveSteamLicense
CONF

    cat > /etc/portage/package.accept_keywords/steam <<'CONF'
# The overlay keeps Steam on ~amd64; this is the package itself rather than a
# blanket ~amd64 for the system.
# ALL FOUR, not just Steam. gamemode and mangohud are ~amd64 too, and
# discovering that one package at a time cost three re-runs:
#
#   !!! All ebuilds that could satisfy "games-util/gamemode" have been
#   !!! masked ... (masked by: ~amd64 keyword)
#
# Still named individually rather than a blanket ACCEPT_KEYWORDS, so the rest
# of the system stays on stable.
games-util/steam-launcher ~amd64
games-util/steam-meta ~amd64
games-util/gamemode ~amd64
games-util/mangohud ~amd64
CONF
fi

# --- the overlay ----------------------------------------------------------

note "enabling ::steam-overlay"
run emerge --getbinpkg --noreplace app-eselect/eselect-repository
if (( ! DRY )); then
    eselect repository list -i | grep -q steam-overlay \
        || eselect repository enable steam-overlay
    emaint sync --repo steam-overlay
fi

if (( ! DRY )); then
    note "what the overlay provides"
    ls /var/db/repos/steam-overlay/games-util/ 2>/dev/null | sed 's/^/    /' || true
fi

# --- the stack ------------------------------------------------------------
#
# REBUILD FIRST, THEN STEAM. nvidia-drivers is already installed without its
# 32-bit half; asking for Steam without rebuilding it produces a working
# install of everything except the part that draws.
note "rebuilding the driver with its 32-bit libraries"
run emerge --getbinpkg --newuse --oneshot --autounmask-continue x11-drivers/nvidia-drivers

# WHAT IS ACTUALLY IN THE ENABLED REPOSITORIES. mangohud is in neither
# ::gentoo nor ::steam-overlay - it lives in GURU, which the desktop stage
# enables - and because portage resolves a list as one graph, that single
# absent package took Steam and GameMode down with it:
#
#   emerge: there are no ebuilds to satisfy "games-util/mangohud".
#
# So the list is filtered to what exists, and what does not is named rather
# than silently dropped.
wanted=(games-util/steam-launcher games-util/gamemode games-util/mangohud)
present=(); absent=()
for pkg in "${wanted[@]}"; do
    if ls -d /var/db/repos/*/"$pkg" >/dev/null 2>&1; then present+=("$pkg"); else absent+=("$pkg"); fi
done
(( ${#absent[@]} )) && warn "not in the enabled repos, skipping: ${absent[*]}"

note "Steam, and what else is available beside it"
# --autounmask-continue, WHICH IS NOT THE DEFAULT AND SHOULD NOT BE. It lets
# portage write the remaining USE changes itself and carry on, rather than
# stopping to be told about each one - and the 32-bit dependency tree under
# Steam is deep enough that doing it by hand is an evening of re-running the
# same command. The flags it writes land in /etc/portage where they can be
# read afterwards; what it must never be allowed near is keywords or masks,
# and it is not: those are set explicitly above.
# KEYWORDS RESOLVED BY PORTAGE, LICENCES BY HAND, and the split is
# deliberate. Steam's dependency tree reaches into ~amd64 in places nobody
# can predict from the outside - sys-libs/libudev-compat was the fifth such
# discovery in a row, each costing a re-run - so --autounmask-keep-keywords=n
# lets portage write those itself and carry on.
#
# Licences are NOT included in that: --autounmask-license stays off, and the
# two non-free ones here (NVIDIA-2025, ValveSteamLicense) are named above.
# Accepting a keyword is a statement about stability; accepting a licence is
# a statement on the user's behalf, and a script should not make the second
# one quietly.
run emerge --getbinpkg --autounmask --autounmask-continue \
    --autounmask-keep-keywords=n "${present[@]}"

# --- the controller ---------------------------------------------------------
#
# A CONNECTED PAD THAT STEAM CANNOT USE. The kernel end needs nothing: xpad
# binds an Xbox Series controller by itself and the evdev and js nodes get a
# uaccess ACL for whoever is logged in at the seat. What Steam cannot do is
# CREATE a device - Steam Input works by writing a virtual pad to /dev/uinput
# and feeding games from that, so with no write access it detects a controller
# and can do nothing with it.
#
# WHY THE EXISTING RULE IS NOT ENOUGH. games-util/game-device-udev-rules ships
#
#   KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
#
# and static_node creates /dev/uinput early as root:root 0600. The uaccess tag
# is only applied when udev processes an ADD event for the device, which never
# happens until the uinput module loads - and nothing on a stock Gentoo loads
# it. So the node sits there with no ACL indefinitely, which is how a pad that
# works perfectly at kernel level is unusable in Steam.
#
# Both halves are written deliberately: the module load is what makes uaccess
# fire, and the group is what covers the case where it does not - a session
# logind does not treat as seat-active, or anything reading the node before the
# module is up.
note "uinput, which is how Steam Input publishes a controller"
if (( DRY )); then
    printf '%swould write:%s /etc/modules-load.d/uinput.conf, /etc/udev/rules.d/99-uinput-input-group.rules\n' "$dim" "$reset"
else
    cat > /etc/modules-load.d/uinput.conf <<'UINPUT'
# Steam Input writes a virtual pad to /dev/uinput. The uaccess tag on that
# node is only applied once udev sees the module add the device, so the module
# has to load for the permissions to ever be right.
uinput
UINPUT
    cat > /etc/udev/rules.d/99-uinput-input-group.rules <<'UINPUTRULE'
# The backstop for /dev/uinput, beside the uaccess tag in 60-game-input.rules:
# group input works even before the module loads, and from a session logind
# does not consider seat-active.
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
UINPUTRULE
fi

# The rule is worth nothing if the person playing is not in the group.
if [[ -n ${SUDO_USER-} ]] && ! id -nG "$SUDO_USER" 2>/dev/null | grep -qw input; then
    note "adding $SUDO_USER to the input group"
    run gpasswd -a "$SUDO_USER" input
fi

run modprobe uinput
run udevadm control --reload
run udevadm trigger --subsystem-match=misc --action=add
if (( ! DRY )); then
    perms=$(stat -c '%U:%G %a' /dev/uinput 2>/dev/null || echo "absent")
    if [[ $perms == "absent" ]]; then
        warn "/dev/uinput is not there at all - Steam Input will not work"
    else
        note "/dev/uinput is $perms"
        [[ $perms == root:input* ]] \
            || warn "expected root:input - Steam Input may still be locked out"
    fi
fi

# --- GameMode's hooks -------------------------------------------------------
#
# The same arrangement bin/gaming-setup.sh makes on Fedora and modules/gaming.nix
# makes on NixOS: the CPU governor while a game runs, the energy preference put
# back afterwards, and notifications silenced in between.
#
# GENTOO SHIPS NO /usr/share/gamemode/gamemode.ini for gamemoded to merge over,
# unlike Fedora, so the governor settings have to be named rather than inherited.
# Measured before this existed: GameMode activated, reported itself active, and
# left the governor at powersave for a whole ELDEN RING session - MangoHud's log
# recorded cpuscheduler=powersave.
#
# defaultgov IS NAMED, and deliberately. Under amd-pstate-epp the only governors
# that exist are performance and powersave; a defaultgov naming ondemand or
# schedutil - as most examples do - would fail to restore on this machine.
note "GameMode: the governor, the energy preference and do-not-disturb"

if (( DRY )); then
    printf '%swould write:%s /etc/gamemode.ini, /usr/local/bin/fd44-epp, fd44-game-end, /etc/tmpfiles.d/fd44-cpu-epp.conf\n' "$dim" "$reset"
else
    # THE GROUP OWNS BOTH PERMISSIONS: GameMode's own polkit rule trusts it with
    # the governor, and the tmpfiles rule below trusts it with the energy
    # preference. ::gentoo's gamemode also ships
    # /etc/security/limits.d/10-gamemode.conf granting it nice -10.
    if [[ -n ${SUDO_USER-} ]] && ! id -nG "$SUDO_USER" 2>/dev/null | grep -qw gamemode; then
        note "adding $SUDO_USER to the gamemode group"
        run gpasswd -a "$SUDO_USER" gamemode
        # NOT effective in the running session, and no logout will help: pam_limits
        # sets RLIMIT_NICE at login and the systemd user manager that runs
        # gamemoded keeps the group list and limits it had at boot. Until a reboot,
        # expect "Failed to renice client: Permission denied" in its log - the
        # governor still switches, because that goes through polkit rather than
        # the group.
        warn "reboot before the renice takes effect - see the comment here for why"
    fi

    install -d /etc/tmpfiles.d /usr/local/bin
    cat > /etc/tmpfiles.d/fd44-cpu-epp.conf <<'RULE'
# Written by install/gentoo_gaming.sh (fd44_hyprdot). Lets the gamemode group set
# the CPU energy preference, so GameMode's end hook can put it back after a game.
z /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 0664 root gamemode -
RULE

    # On amd-pstate-epp the performance governor FORCES the energy preference to
    # "performance", and putting the governor back does NOT restore it - it stays
    # until a reboot, so one game would leave the CPU in performance mode for the
    # rest of the day. GameMode 1.8.2 has no setting for this.
    cat > /usr/local/bin/fd44-epp <<'HOOK'
#!/bin/sh
# Written by install/gentoo_gaming.sh (fd44_hyprdot). GameMode end hook:
#   fd44-epp <preference>
# The value is FIXED rather than saved at game start: nothing documents whether
# gamemoded runs start hooks before or after it switches the governor, and a hook
# that saved afterwards would faithfully restore "performance".
want="${1:-balance_performance}"
cpu="${CPU_ROOT:-/sys/devices/system/cpu}"      # test prefix; the real tree by default

# gamemoded's group list is older than this group membership - it is started by
# the systemd user manager, which a logout does not restart - and sysfs checks the
# writing process's groups. sg reads the group database instead, with no password
# for a listed member.
case " $(id -Gn) " in
    *" gamemode "*) ;;
    *) exec sg gamemode -c "'$0' '$want'" </dev/null ;;
esac

# Returns at once and restores from a background child that waits for the governor
# to leave performance: the kernel refuses an EPP change while that governor holds
# it, and gamemoded waits for end scripts - so a hook that waited inline could be
# the very thing the governor reset was queued behind.
(
    n=0
    while [ "$n" -lt 50 ] && [ "$(cat "$cpu/cpu0/cpufreq/scaling_governor" 2>/dev/null)" = performance ]; do
        sleep 0.2
        n=$((n + 1))
    done
    for f in "$cpu"/cpu*/cpufreq/energy_performance_preference; do
        printf '%s' "$want" > "$f" 2>/dev/null
    done
) </dev/null >/dev/null 2>&1 &
exit 0
HOOK
    chmod 0755 /usr/local/bin/fd44-epp

    # GameMode allows ONE command per hook, so the end hook runs both things.
    # Separate lines rather than `&&`: a failure in the first must not swallow the
    # second - a desktop left permanently silent because a sysfs write failed
    # would be a poor trade.
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cat > /usr/local/bin/fd44-game-end <<HOOK
#!/bin/sh
# Written by install/gentoo_gaming.sh (fd44_hyprdot). GameMode end hook.
/usr/local/bin/fd44-epp balance_performance || true
"$repo_dir/bin/game-dnd.sh" off || true
exit 0
HOOK
    chmod 0755 /usr/local/bin/fd44-game-end

    # GAMEMODE DOES NOT SURVIVE PROTON WITHOUT THIS. gamemoderun works by putting
    # libgamemodeauto.so.0 in LD_PRELOAD; the library registers with gamemoded when
    # it loads and deregisters when it unloads. That survives an ordinary fork - a
    # launcher that spawns the game and exits keeps GameMode on, because the child
    # inherited the preload. It does NOT survive pressure-vessel, which EMPTIES
    # LD_PRELOAD and replaces LD_LIBRARY_PATH at the container boundary: the library
    # unloads and deregisters there, and the process carries on as the game with
    # GameMode already gone. Measured on the NixOS side with ARC Raiders - activated
    # and released inside the same second, 45 s before the session started.
    #
    # MangoHud is unaffected because it enters as a Vulkan layer, which
    # pressure-vessel imports on purpose. GameMode has no such route, so the
    # registration is held by a process that never enters the container.
    #
    # This is what bin/steam-launch-options.sh puts on every game, and it is why
    # that line says fd44-gamemode-hold rather than gamemoderun.
    cat > /usr/local/bin/fd44-gamemode-hold <<'HOLD'
#!/bin/sh
# Written by install/gentoo_gaming.sh (fd44_hyprdot). GameMode that survives
# pressure-vessel - see the comment in that script for why gamemoderun does not.
#
# The holder sits on the host with the preload intact for as long as this wrapper
# lives, and this wrapper lives as long as the game: Steam's reaper waits for the
# whole process tree, so "$@" does not return until the session ends.
#
# It watches THIS process rather than sleeping forever, so a wrapper killed
# outright cannot leave GameMode latched on: it notices within two seconds and
# exits, which releases it.
gamemoderun sh -c "while kill -0 $$ 2>/dev/null; do sleep 2; done" &
holder=$!
trap 'kill "$holder" 2>/dev/null || true' EXIT HUP INT TERM

"$@"
HOLD
    chmod 0755 /usr/local/bin/fd44-gamemode-hold

    if [[ -f /etc/gamemode.ini ]] && ! grep -q fd44 /etc/gamemode.ini; then
        cp -a /etc/gamemode.ini "/etc/gamemode.ini.before-fd44-$(date +%F)"
        note "kept the previous gamemode.ini beside it"
    fi
    cat > /etc/gamemode.ini <<INI
; Written by install/gentoo_gaming.sh (fd44_hyprdot). Gentoo ships no
; /usr/share/gamemode/gamemode.ini to merge over, so [general] is spelled out.
[general]
desiredgov=performance
; ONLY performance and powersave exist under amd-pstate-epp.
defaultgov=powersave
renice=10
inhibit_screensaver=1

[custom]
; A toast over a fullscreen game is a surface the compositor has to put above it,
; and with some titles that is a visible hitch. Critical messages from this
; repository's own scripts still get through; see quickshell/NotificationService.qml.
start=$repo_dir/bin/game-dnd.sh on
; The energy preference back, and notifications with it.
end=/usr/local/bin/fd44-game-end
INI

    systemd-tmpfiles --create /etc/tmpfiles.d/fd44-cpu-epp.conf
    note "EPP is $(stat -c '%U:%G %a' /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo 'not exposed by this driver')"
fi

note "gamemode needs its daemon"
run systemctl --global enable gamemoded 2>/dev/null || true

note "done"
printf '\n  %sstart Steam as your user, not as root:%s  steam\n' "$dim" "$reset"
printf '  %sthe first run downloads its own runtime, which takes a while%s\n\n' "$dim" "$reset"
