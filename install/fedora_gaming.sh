#!/usr/bin/env bash
# =========================================================================
# fedora_gaming.sh - Steam, GameMode and fan control, on fedora-gaming00
# =========================================================================
#
# Usage:  sudo install/fedora_gaming.sh [--go]
#
# Stage five, opt-in, run ON the Fedora install. Separate from stage four for
# the reason bin/gaming-setup.sh gives: Steam is a feature set one machine
# wants, not something every install is broken without.
#
# NOT bin/gaming-setup.sh, WHICH IS FOR A MACHINE THAT IS GONE. That script
# targets the previous desktop - ASRock B650I, Radeon RX 9070 XT, Btrfs - and
# does three things that are wrong here: it swaps Mesa's VA-API driver for
# RPM Fusion's AMD build, caps an AMD GPU at 250 W, and marks a Btrfs Steam
# library nodatacow. This machine is NVIDIA on ext4. The lessons carry over;
# the script does not.
#
# RPM Fusion is assumed - stage four enables it for the NVIDIA driver.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfedora:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

GO=0
while (( $# )); do
    case "$1" in
        --go) GO=1; shift ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done
(( EUID == 0 )) || die "run this with sudo"
[[ -f /etc/fedora-release ]] || die "this runs on the Fedora install"
rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 \
    || die "RPM Fusion is not enabled - run install/fedora_desktop.sh first"

TARGET_USER="${SUDO_USER:-jc}"

# BY ARCHITECTURE, SPELLED OUT, and this is not decoration. A bare `gamemode`
# next to `gamemode.i686` once installed ONLY the i686 package - dnf's own
# transaction record said "Install gamemode...i686" and nothing else. The result
# was that gamemoderun failed on every 64-bit game, which is nearly all of them:
#
#   ld.so: object 'libgamemodeauto.so.0' from LD_PRELOAD cannot be preloaded
#
# while `rpm -q gamemode` reported success, because the i686 package satisfies
# it. The same trap applies to mangohud: a 32-bit game preloads the 32-bit half.
PKGS=(
    steam steam-devices
    gamemode.x86_64 gamemode.i686
    mangohud.x86_64 mangohud.i686
    gamescope
    vulkan-tools
)

if (( ! GO )); then
    note "would install:"; printf '    %s\n' "${PKGS[@]}"
    note "would add the CoolerControl COPR and install coolercontrol"
    note "would add $TARGET_USER to the gamemode group"
    note "would write the /dev/uinput rule Steam Input needs"
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

# --- Steam and the gaming stack ----------------------------------------------
note "installing Steam and the gaming stack"
dnf -y install "${PKGS[@]}"

# --- Steam Input -------------------------------------------------------------
#
# /dev/uinput, WITHOUT WHICH CONTROLLERS DO NOT WORK IN STEAM. Steam Input
# creates a virtual device there to present any pad as an Xbox controller; with
# no access the pad is visible to the system and invisible to the game, which
# is a confusing way to fail - jstest sees it, the game does not.
#
# The module is not loaded at boot by default, and udev's default owner is root.
# Both halves are needed. Found on the Gentoo install that used to be here; the
# original script is on the T5 under gentoo-keepsakes/setup/fix-uinput.sh.
note "giving Steam Input access to /dev/uinput"
printf 'uinput\n' > /etc/modules-load.d/uinput.conf
printf 'KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"\n' \
    > /etc/udev/rules.d/60-steam-uinput.rules
modprobe uinput || warn "could not load uinput now; it will load at boot"
udevadm control --reload-rules && udevadm trigger --subsystem-match=misc || true
usermod -aG input "$TARGET_USER"

# --- GameMode ----------------------------------------------------------------
#
# The group is what lets gamemoded change the CPU governor on request. Without
# it GameMode runs, reports success, and silently changes nothing.
note "adding $TARGET_USER to the gamemode group"
getent group gamemode >/dev/null || groupadd gamemode
usermod -aG gamemode "$TARGET_USER"

# --- CoolerControl -----------------------------------------------------------
#
# NOT IN FEDORA, and never will be - it needs a daemon with direct hardware
# access. The project's own COPR is the supported route and is signed with its
# own key (gpgcheck=1 in the repo file it ships).
#
# THE FAN CURVES ARE NOT INSTALLED BY THIS. CoolerControl keeps them in
# /etc/coolercontrol/config.toml, which its daemon rewrites at runtime, so they
# cannot be a file in this repository. What IS in the repository is a backup:
# cooling/coolercontrol-backup-gaming00/ and -nixos/ and -gentoo/. Importing one
# is a deliberate act, done through the UI, after checking it describes THIS
# hardware - a curve written for a different cooler is a quiet way to cook a CPU.
note "adding the CoolerControl COPR"
dnf -y copr enable codifryed/CoolerControl

note "installing coolercontrol"
dnf -y install coolercontrol

note "enabling coolercontrold"
systemctl enable --now coolercontrold

printf '\n'
note "done"
printf '  %-14s %s\n' "steam"          "$(rpm -q --qf '%{VERSION}' steam 2>/dev/null)"
printf '  %-14s %s / %s\n' "gamemode"  "$(rpm -q --qf '%{ARCH}' gamemode.x86_64 2>/dev/null)" "$(rpm -q --qf '%{ARCH}' gamemode.i686 2>/dev/null)"
printf '  %-14s %s\n' "coolercontrold" "$(systemctl is-active coolercontrold)"
printf '  %-14s %s\n' "uinput"         "$(ls -l /dev/uinput 2>/dev/null | awk '{print $1, $3":"$4}')"
printf '\n'
warn "LOG OUT AND BACK IN before launching Steam - the input and gamemode"
warn "groups only reach a session that started after they existed."
printf '\n'
note "MangoHud note: Fedora ships 0.8.3~rc1, which aborts a game when logging"
note "stops. bin/gaming-setup.sh documents Bazzite's COPR as the fix; add it if"
note "you use the overlay's logging."
