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

note "gamemode needs its daemon"
run systemctl --global enable gamemoded 2>/dev/null || true

note "done"
printf '\n  %sstart Steam as your user, not as root:%s  steam\n' "$dim" "$reset"
printf '  %sthe first run downloads its own runtime, which takes a while%s\n\n' "$dim" "$reset"
