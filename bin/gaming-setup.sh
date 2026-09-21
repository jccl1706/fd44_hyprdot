#!/usr/bin/env bash
# =========================================================================
# gaming-setup.sh - turn this machine into a Steam gaming machine
# =========================================================================
#
# Usage:  sudo bin/gaming-setup.sh [--dry-run] [--proton-ge] [-y]
#
# DELIBERATELY NOT PART OF THE INSTALLER. install_fedora.sh builds the
# same minimal base on every machine and only installs what the system is
# broken without. Steam is not that: it is a feature set that one machine
# wants - the ASRock B650I / RX 9070 XT desktop - and the laptop does not.
# Folding it in would put a third-party repo and a few hundred 32-bit
# packages on every install to serve one of them. So it lives here, is opt
# in, and is run by hand on the machine that wants it.
#
# Everything below is reversible with `dnf history undo`.
#
# WHAT THIS TOUCHES
#   - enables the RPM Fusion free and nonfree repositories (Steam is not in
#     Fedora's own repos, and never will be - it is proprietary)
#   - adds Bazzite's COPR for MangoHud only - Fedora's 0.8.3-rc1 aborts a game
#     when logging stops
#   - installs steam, and the tools that make it usable on Hyprland
#   - swaps Mesa's VA-API driver for RPM Fusion's, which has the H.264 and
#     HEVC paths compiled in
#   - marks the Steam library nodatacow on Btrfs
#   - caps Proton games at 120 fps through the session environment
#   - limits the AMD GPU to 250 W, at boot and after every resume
#   - adds you to the gamemode group, so GameMode can switch the CPU governor
#   - restores the CPU energy preference after every GameMode session
#   - links the MangoHud overlay config from this repo (mangohud/), and lets
#     the gamemode group read the CPU energy counter so it can show CPU power
#   - verifies all of it, including running the tools rather than only
#     asking rpm whether they are installed
#
# WHAT IT DOES NOT DO. No Lutris, no Heroic, no emulators, no Flatpak
# runtime, no kernel tuning, no "optimisation" tweaks copied off a forum.
# Fedora 44 already sets vm.max_map_count to 1048576 in
# /usr/lib/sysctl.d/10-map-count.conf - the sysctl every gaming guide tells
# you to write by hand - so this checks it rather than writing it again.

set -euo pipefail

DRY=0
PROTON_GE=0
ASSUME_YES=()

while (( $# )); do
    case "$1" in
        --dry-run)   DRY=1 ;;
        --proton-ge) PROTON_GE=1 ;;
        -y|--yes)    ASSUME_YES=(-y) ;;
        -h|--help)
            sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf 'gaming-setup: unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }


# -------------------------------------------------------------------------
# This is the Fedora setup script
# -------------------------------------------------------------------------
# It installs packages with dnf and writes to /usr and /etc, none of which
# exists in that form on NixOS. Without this check the failure arrives several
# steps in as `dnf: command not found` or a write to a directory that is not
# there, which reads like a broken script rather than the wrong machine.
#
# ID_LIKE is accepted too, so Fedora derivatives (Nobara, Bazzite) still work.
# FD44_SKIP_DISTRO_CHECK=1 overrides it for anyone who knows better.
require_fedora() {
    [[ -n ${FD44_SKIP_DISTRO_CHECK:-} ]] && return 0
    # --help always works, wherever you are. Two of these scripts parse their
    # arguments AFTER this point, and a help text you cannot read on the wrong
    # machine is exactly the sort of small obstruction this check exists to
    # remove rather than add.
    case "${1:-}" in -h|--help) return 0 ;; esac
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
        like="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}")"
    fi
    [[ $id == fedora || " $like " == *" fedora "* ]] && return 0
    printf '\033[1;31merror:\033[0m %s is the Fedora setup script; this system reports ID=%s.\n' \
        "$(basename "$0")" "${id:-unknown}" >&2
    printf '       %s\n' "On NixOS this work is declarative: see modules/gaming.nix in fd44_nixos." >&2
    printf '       Override with FD44_SKIP_DISTRO_CHECK=1 if you are sure.\n' >&2
    exit 1
}
require_fedora "$@"

run() {
    if (( DRY )); then
        printf '\033[1;34mwould run:\033[0m %s\n' "$*"
    else
        "$@"
    fi
}

(( EUID == 0 )) || die "must run as root - try: sudo $0"

# The user who invoked sudo. The package half of this needs root; the Steam
# library and Proton-GE halves must NOT be done as root, or Steam spends its
# first run repairing permissions on a directory it cannot write to.
target_user="${SUDO_USER:-}"
[[ -n $target_user ]] || die "run this with sudo from your own account, not as a root login -
  the Steam directory has to be created as you, not as root."
target_home="$(getent passwd "$target_user" | cut -d: -f6)"
[[ -d $target_home ]] || die "no home directory for $target_user"

fedora="$(rpm -E %fedora)"


# -------------------------------------------------------------------------
# What is this machine
# -------------------------------------------------------------------------
log "machine"
gpu="$(lspci -nn 2>/dev/null | grep -iE 'vga|display|3d' | head -1 || true)"
printf '    gpu    : %s\n' "${gpu:-unknown}"
printf '    fedora : %s\n' "$fedora"
printf '    kernel : %s\n' "$(uname -r)"

# amdgpu is the only GPU path this project supports - the installer dropped
# the Nvidia branch entirely rather than carry it as dead code. Saying so
# here is cheaper than letting someone discover it after a 2 GB download.
# Here-string, not `lsmod | grep -q`: under pipefail grep's early exit kills
# lsmod with SIGPIPE and a LOADED amdgpu reads as missing. Measured with the
# same pattern in cooling-setup.sh: exit 141, five runs out of five.
if ! grep -q '^amdgpu' <<<"$(lsmod)"; then
    warn "the amdgpu kernel module is not loaded."
    warn "  This script assumes Mesa's RADV driver. On Nvidia you would need"
    warn "  akmod-nvidia as well, which nothing in this repository sets up."
fi


# -------------------------------------------------------------------------
# RPM Fusion
# -------------------------------------------------------------------------
# The installer's changelog says RPM Fusion is deliberately excluded because
# "nothing is broken without them and they mean a permanent third-party
# repo". That reasoning does not survive contact with Steam: steam ships
# nowhere else. Enabling it here, on one machine, by explicit request, is
# the whole point of this script being separate.
log "RPM Fusion"
for kind in free nonfree; do
    if rpm -q "rpmfusion-$kind-release" >/dev/null 2>&1; then
        printf '    %-8s already enabled\n' "$kind"
    else
        printf '    %-8s enabling\n' "$kind"
        run dnf install "${ASSUME_YES[@]}" \
            "https://mirrors.rpmfusion.org/$kind/fedora/rpmfusion-$kind-release-$fedora.noarch.rpm"
    fi
done


# -------------------------------------------------------------------------
# Packages
# -------------------------------------------------------------------------
# THE FOOTPRINT IS LARGE AND THAT IS EXPECTED. The Steam client is a 32-bit
# binary - `steam` exists only as .i686 - so installing it brings in a
# parallel i686 stack: mesa-dri-drivers, mesa-vulkan-drivers, vulkan-loader,
# SDL2, gtk2, nss, pulseaudio-libs and so on. That is not bloat that can be
# trimmed; it is what the client links against. Expect a few hundred
# packages on a machine that has never had any 32-bit libraries.
#
# Two of steam's dependencies are worth knowing about before they surprise
# you:
#   firewalld-filesystem  - directory ownership only. It is NOT firewalld,
#                           and no firewall daemon gets installed or started.
#   ntsync-autoload       - loads the kernel's ntsync module, which Proton
#                           uses for Win32 sync primitives. This is wanted.
#
# What is NOT listed here is everything `steam` already Requires. Listing
# mesa-vulkan-drivers or vulkan-loader again would be noise.
packages=(
    steam

    # Explicit, even though `steam` only RECOMMENDS them. A Recommends is
    # not a guarantee, and this project has already been bitten once by
    # depending on a package that was only ever present as somebody else's
    # weak dependency: playerctl vanished the day the package that pulled it
    # in was removed, and nothing pointed at the cause. Both architectures,
    # because a 32-bit game preloads the 32-bit libgamemodeauto.
    #
    # BOTH ARCHITECTURES SPELLED OUT, x86_64 included. This list used to say
    # `gamemode gamemode.i686`, and dnf5 installed ONLY the i686 package -
    # the transaction's own record reads "Install gamemode...i686" and
    # nothing else. A bare name next to the same name with an explicit arch
    # does not get you both. The result was that `gamemoderun` failed on
    # every 64-bit game, which is nearly all of them:
    #   ld.so: object 'libgamemodeauto.so.0' from LD_PRELOAD cannot be
    #   preloaded (cannot open shared object file): ignored.
    # while the verification pass reported ok, because `rpm -q gamemode` is
    # satisfied by the i686 package and a 32-bit gamemoded runs fine.
    gamemode.x86_64
    gamemode.i686

    # The performance overlay, with the same fix for the same reason.
    mangohud.x86_64
    mangohud.i686

    # A nested compositor to run a game inside. This matters more here than
    # on a desktop environment: a game that wants an odd resolution, or that
    # misbehaves when the compositor resizes it, can be handed a fixed-size
    # world of its own with
    #   gamescope -W 2560 -H 1440 -f -- %command%
    # in the title's Steam launch options, instead of fighting Hyprland.
    gamescope

    # vulkaninfo. The verification pass below uses it to prove RADV is the
    # driver actually in use - which is not something rpm can answer, and is
    # the single most useful thing to know when a game refuses to start.
    vulkan-tools
)

log "installing (${#packages[@]} requested, plus their 32-bit stack)"
run dnf install "${ASSUME_YES[@]}" "${packages[@]}"

# MangoHud from Bazzite's COPR, and nothing else from it.
#
# WHY. Fedora 44 ships MangoHud 0.8.3-rc1 - Rawhide too, with no update queued.
# Stopping a log (Left Shift+F2) makes it draw a results window whose graph has
# an empty ImGui label, and that build keeps ImGui's assertions on, so the game
# aborts: Cyberpunk 2077 did, mid-session. Upstream fixed it in 0.8.3 (commit
# 9400280e).
#
# WHICH REPO. Bazzite (Universal Blue) builds upstream 0.8.4 from a spec that is
# Fedora's plus one patch for mangoapp - the gamescope variant this machine does
# not use - signed with the COPR project key. Tried first in a Fedora 44 live VM:
# 0.8.3-rc1 aborted when logging stopped; 0.8.4 from this repo showed "Logging
# Finished" and kept running.
#
# MANGOHUD ONLY. The same COPR carries Bazzite's NetworkManager, bluez, Xwayland
# and more. includepkgs keeps all of that out of reach - today those builds are
# older than Fedora's, but nothing guarantees they stay that way.
#
# TWO SECTIONS. The COPR builds i686 in a separate chroot, and the 32-bit half
# Steam's 32-bit games load has to match the 64-bit one or dnf refuses.
#
# Back to Fedora's build: delete the repo file, then  sudo dnf distro-sync mangohud
mh_repo="/etc/yum.repos.d/fd44-bazzite-mangohud.repo"
log "MangoHud from Bazzite's COPR"
if (( DRY )); then
    printf '\033[1;34mwould write:\033[0m %s\n' "$mh_repo"
else
    copr="https://download.copr.fedorainfracloud.org/results/ublue-os/bazzite-multilib"
    cat > "$mh_repo" <<REPO
# Written by bin/gaming-setup.sh (fd44_hyprdot). MangoHud only, from Bazzite's
# COPR (ublue-os/bazzite-multilib): Fedora's 0.8.3-rc1 aborts a game when
# logging stops. includepkgs keeps every other package in that repository out.
[fd44-bazzite-mangohud]
name=Bazzite MangoHud (COPR ublue-os/bazzite-multilib, mangohud only)
baseurl=$copr/fedora-\$releasever-\$basearch/
type=rpm-md
gpgcheck=1
gpgkey=$copr/pubkey.gpg
repo_gpgcheck=0
enabled=1
includepkgs=mangohud*

[fd44-bazzite-mangohud-i386]
name=Bazzite MangoHud i386 (COPR ublue-os/bazzite-multilib, mangohud only)
baseurl=$copr/fedora-\$releasever-i386/
type=rpm-md
gpgcheck=1
gpgkey=$copr/pubkey.gpg
repo_gpgcheck=0
enabled=1
includepkgs=mangohud*
REPO
    chmod 0644 "$mh_repo"
    printf '    %s\n' "$mh_repo"
fi
run dnf upgrade "${ASSUME_YES[@]}" --refresh mangohud

# ntsync, loaded now rather than at the next boot.
#
# steam Recommends ntsync-autoload, which ships exactly one file:
# /usr/lib/modules-load.d/ntsync.conf. That is read by
# systemd-modules-load.service at BOOT, so installing the package leaves
# /dev/ntsync absent until the machine is restarted - and nothing says so.
# The first Proton session after a fresh setup then silently falls back to
# fsync, which is the slower path, and looks like nothing at all.
#
# ntsync implements Windows' synchronisation primitives (events, semaphores,
# mutexes) in the kernel, so Wine stops emulating them in userspace. It is
# the single largest free win available to Proton on a modern kernel.
#
# Best-effort: a kernel without the module is not a failure, and the
# verification pass reports the outcome either way.
if (( ! DRY )) && [[ ! -e /dev/ntsync ]]; then
    log "ntsync"
    if modprobe ntsync 2>/dev/null && [[ -e /dev/ntsync ]]; then
        printf '    loaded now (modules-load.d would otherwise wait for a reboot)\n'
    else
        printf '    not available in this kernel - Proton will use fsync\n'
    fi
fi

# VA-API, swapped for the RPM Fusion build.
#
# Fedora's mesa-va-drivers has the H.264 and HEVC code compiled OUT for
# patent reasons, so hardware video decode and encode silently do nothing.
# That shows up in Steam as Remote Play encoding on the CPU and in-client
# video stuttering. The freeworld build is the same driver with those paths
# enabled.
#
# Done AFTER the install above, not before: the i686 half only exists once
# steam has dragged in the 32-bit Mesa stack. Each swap is guarded on the
# package actually being installed, because `dnf swap` on an absent package
# is an error and would abort the script under `set -e`.
#
# There is no mesa-vdpau-drivers-freeworld any more - Mesa dropped VDPAU
# entirely. Guides that still tell you to swap it are out of date.
# A SWAP IS NOT ALWAYS WHAT IS NEEDED. A machine built by this project's
# installer has no mesa-va-drivers at all - nothing in the minimal package
# set pulls it, and steam only Requires libva, which is the loader and not a
# driver. Treating this purely as a swap would skip the whole step on
# exactly the machines the script is written for, and the verification below
# would then report a failure the script itself had caused.
#
# 64-bit gets the driver installed outright if it is missing. 32-bit only
# gets SWAPPED if Fedora's build is already there: a 32-bit VA driver that
# nothing asked for is one more package for a codec path almost no 32-bit
# title uses.
log "VA-API (hardware video decode)"
for arch in x86_64 i686; do
    if rpm -q "mesa-va-drivers-freeworld.$arch" >/dev/null 2>&1; then
        printf '    %-7s already the freeworld build\n' "$arch"
    elif rpm -q "mesa-va-drivers.$arch" >/dev/null 2>&1; then
        printf '    %-7s swapping to the freeworld build\n' "$arch"
        run dnf swap "${ASSUME_YES[@]}" \
            "mesa-va-drivers.$arch" "mesa-va-drivers-freeworld.$arch"
    elif [[ $arch == x86_64 ]]; then
        printf '    %-7s no Mesa VA driver at all - installing the freeworld build\n' "$arch"
        run dnf install "${ASSUME_YES[@]}" "mesa-va-drivers-freeworld.$arch"
    else
        printf '    %-7s no 32-bit VA driver, and not adding one\n' "$arch"
    fi
done

# GameMode's reason for existing, switching the CPU governor to performance
# while a game runs, is done by a root helper through pkexec - and the polkit
# rule gamemode ships allows it ONLY for members of the `gamemode` group.
# Installing the package adds nobody to that group.
#
# Without it `gamemoderun %command%` still starts the game, the daemon still
# runs and logs a client, and pkexec answers "Not authorized" in the journal:
# the game plays in the default balance_performance EPP and nothing on screen
# says so. Found on the desktop, where both games had gamemoderun in their
# launch options and `gamemoded -t` failed "Verifying CPU governor setting".
log "GameMode permissions"
if grep -qx gamemode <<<"$(id -nG "$target_user" | tr ' ' '\n')"; then
    printf '    %s is already in the gamemode group\n' "$target_user"
else
    printf '    adding %s to the gamemode group (lets GameMode switch the CPU governor)\n' "$target_user"
    run usermod -aG gamemode "$target_user"
fi


# -------------------------------------------------------------------------
# The Steam library, on Btrfs
# -------------------------------------------------------------------------
# COPY-ON-WRITE AND GAME FILES ARE A BAD COMBINATION. A Btrfs file written
# in place - a shader cache, a Proton prefix, a save, an update patching a
# 60 GB pak in the middle - allocates new extents for every changed block
# instead of overwriting. Game directories fragment badly and stay that way,
# and the write amplification is real on an NVMe you paid for.
#
# `chattr +C` only takes effect on a directory that is still EMPTY: the flag
# is inherited by files created afterwards and cannot be applied to files
# that already exist. So this has to happen before Steam's first run, which
# is exactly why it is here and not in a "tips" section of the README.
#
# Created as the invoking user. A steamapps owned by root is a first-run
# failure that Steam reports as a vague "disk write error".
log "Steam library"
steam_lib="$target_home/.local/share/Steam/steamapps"
fstype="$(stat -f -c %T "$target_home" 2>/dev/null || echo unknown)"
printf '    home filesystem: %s\n' "$fstype"

if [[ $fstype != btrfs ]]; then
    printf '    not Btrfs - nothing to do\n'
elif [[ -d $steam_lib ]] && [[ -n "$(ls -A "$steam_lib" 2>/dev/null)" ]]; then
    warn "$steam_lib already exists and has files in it."
    warn "  chattr +C cannot be applied retroactively. Leaving it alone."
    warn "  To convert it you would have to move the games out and back in."
elif (( DRY )); then
    printf '\033[1;34mwould run:\033[0m runuser -u %s -- mkdir -p %s && chattr +C %s\n' \
        "$target_user" "$steam_lib" "$steam_lib"
else
    # CREATED AS THE USER, EVERY COMPONENT OF IT.
    #
    # This was `install -d -o jc -g jc .../Steam/steamapps`, which looks like
    # it does the right thing and does not: install -d creates the missing
    # parents too, but applies the ownership only to the final component. So
    # ~/.local/share/Steam came out root:root with a correctly-owned
    # steamapps inside it, and Steam's first run died extracting its own
    # bootstrap:
    #
    #   tar: clientui: Cannot mkdir: Permission denied
    #   tar: ubuntu12_32: Cannot mkdir: Permission denied
    #   Failed to extract bootstraplinux_ubuntu12_32.tar.xz, aborting
    #
    # Which is not a permissions message anyone would trace back to here.
    # Worse, the state is not self-repairing: the user cannot delete the
    # directory to start over, because removing steamapps needs write
    # permission on the root-owned parent. It takes a root chown to undo.
    #
    # mkdir -p as the user cannot get this wrong - every directory it
    # creates is owned by whoever ran it. chattr likewise runs as the user,
    # who owns the directory and does not need root to set a flag on it.
    runuser -u "$target_user" -- mkdir -p "$steam_lib"
    if runuser -u "$target_user" -- chattr +C "$steam_lib" 2>/dev/null; then
        printf '    nodatacow set on %s\n' "$steam_lib"
    else
        warn "could not set nodatacow on $steam_lib (non-fatal)"
    fi
fi


# -------------------------------------------------------------------------
# Frame cap
# -------------------------------------------------------------------------
# Every game run through Proton is capped at FRAME_CAP, by the translation
# layer itself - no overlay, no per-game launch options, nothing to install.
#
#   VKD3D_FRAME_RATE  read by vkd3d-proton, which is what DX12 games load
#   DXVK_CONFIG       read by DXVK, which is what DX9/10/11 games load
#
# Both names were checked against the DLLs Proton actually ships rather than
# taken from a guide: `grep -a` finds VKD3D_FRAME_RATE in d3d12core.dll, and
# DXVK_CONFIG / dxgi.maxFrameRate / d3d9.maxFrameRate in DXVK's dxgi, d3d11
# and d3d9. Native Linux games are not affected; they read neither.
#
# WHY A CAP AT ALL. With nothing limiting it, the RX 9070 XT rendered ARC
# Raiders at 99-100% utilisation and 304 W - its full power limit, 94 C at
# the junction - on a 144 Hz monitor. Frames past the refresh rate are never
# shown; they are just heat.
#
# WHY 120, NOT 144. 144 was tried first and measured with MangoHud, in 5-second
# windows. In lighter scenes it held exactly - median 144.0 fps, GPU 86-88%,
# 177-247 W. In heavy ones the card was already rendering BELOW it, 136-141 fps
# at 100% and 302-304 W, so the cap never acted and the heat stayed. 120 sits
# under what the GPU manages in heavy scenes too, so it saves power in both.
# It also keeps frames inside the monitor's VRR range (48-144 Hz): a cap at the
# very top - 144 on a 143.97 Hz panel - parks frames at the ceiling, where
# adaptive sync drops out.
#
# WHERE IT LIVES. uwsm sources ~/.config/uwsm/env.d/* when the session
# starts and exports the result to systemd and D-Bus, so everything launched
# in the session - the Steam client, and every game it starts - inherits it.
# It is a file in THIS machine's home rather than in the repository on
# purpose: the laptop shares the repo and does not game. Takes effect at the
# next login.
FRAME_CAP=120
log "frame cap"
cap_dir="$target_home/.config/uwsm/env.d"
cap_file="$cap_dir/gaming"
if (( DRY )); then
    printf '\033[1;34mwould write:\033[0m %s (cap %s fps)\n' "$cap_file" "$FRAME_CAP"
else
    # As the user, every component - the lesson from the Steam library.
    runuser -u "$target_user" -- mkdir -p "$cap_dir"
    runuser -u "$target_user" -- tee "$cap_file" >/dev/null <<EOF
# Written by bin/gaming-setup.sh. Sourced by uwsm at login.
# Caps games run through Proton at $FRAME_CAP fps. Delete this file to remove
# the cap; edit the numbers to change it. Both take effect at the next login.
export VKD3D_FRAME_RATE=$FRAME_CAP
export DXVK_CONFIG="dxgi.maxFrameRate = $FRAME_CAP; d3d9.maxFrameRate = $FRAME_CAP"
EOF
    printf '    %s fps, from the next login - %s\n' "$FRAME_CAP" "$cap_file"
fi


# -------------------------------------------------------------------------
# GPU power limit
# -------------------------------------------------------------------------
# WHY. With the 120 fps cap in place, heavy scenes still held the RX 9070 XT at
# its 304 W default limit - below 120 fps, so the cap never acted - and that is
# where its own fans got loud. Measured in two 20-35 minute ARC Raiders
# sessions, comparing only the stretches where the GPU was maxed out:
#
#                          304 W          250 W
#   GPU fans, median     2012 rpm       1653 rpm
#   GPU fans, peak       2134 rpm       1791 rpm
#   junction, median/max  93 / 97 C      88 / 91 C
#   junction >= 95 C      6.7% of play   0%
#
# with the CPU fan, case fans, CPU and case air unchanged. The frame cost was
# not measured. Under sustained load this card holds about 5% above whatever
# limit is set (the PPT reading sat near 264 W at 250 W), so set a lower
# number if the reading itself must stay under a figure.
#
# HOW. A small helper writes power1_cap; a oneshot unit runs it at boot and
# again after resume - After= plus WantedBy= the sleep targets is what fires
# a unit on the way back up. It deliberately has no RemainAfterExit, or it
# would stay "active" from boot and never run again. Whether amdgpu keeps the
# limit across suspend was not verified; reapplying it is harmless either way.
#
# The helper changes EVERY amdgpu hwmon that exposes power1_cap and nothing
# else - a 9700X has an integrated GPU, which amdgpu would also bind if it
# were enabled, and it has no power cap to set. The value is checked against
# the card's own power1_cap_min/max, and read back after writing.
#
# GPU_POWER_LIMIT is the one line to change. Delete the unit to remove it:
#   systemctl disable --now fd44-gpu-power-limit.service
GPU_POWER_LIMIT=250
R="${FD44_ROOT:-}"                                      # test prefix; empty for real
pl_helper="$R/usr/local/sbin/fd44-gpu-power-limit"
pl_unit="$R/etc/systemd/system/fd44-gpu-power-limit.service"
log "GPU power limit (${GPU_POWER_LIMIT} W)"
if (( DRY )); then
    printf '\033[1;34mwould write:\033[0m %s and %s, then enable and start it\n' "$pl_helper" "$pl_unit"
else
    install -d "$(dirname "$pl_helper")" "$(dirname "$pl_unit")"
    cat > "$pl_helper" <<'HELPER'
#!/bin/sh
# Written by bin/gaming-setup.sh (fd44_hyprdot). Sets the AMD GPU power limit.
# WATTS comes from fd44-gpu-power-limit.service. Applies to every amdgpu hwmon
# that exposes power1_cap, checks the card's allowed range, reads back.
set -eu
W="${WATTS:?WATTS not set}"
ROOT="${HWMON_ROOT:-/sys/class/hwmon}"
TRIES="${TRIES:-30}"
want=$((W * 1000000))
n=0
while [ "$n" -lt "$TRIES" ]; do
    applied=0
    for h in "$ROOT"/hwmon*; do
        [ "$(cat "$h/name" 2>/dev/null)" = amdgpu ] || continue
        [ -e "$h/power1_cap" ] || continue
        min=$(cat "$h/power1_cap_min"); max=$(cat "$h/power1_cap_max")
        if [ "$want" -lt "$min" ] || [ "$want" -gt "$max" ]; then
            echo "fd44-gpu-power-limit: $W W is outside $((min / 1000000))-$((max / 1000000)) W for $h - not applied" >&2
            exit 1
        fi
        echo "$want" > "$h/power1_cap"
        got=$(cat "$h/power1_cap")
        if [ "$got" != "$want" ]; then
            echo "fd44-gpu-power-limit: wrote $want to $h/power1_cap but it reads $got" >&2
            exit 1
        fi
        echo "fd44-gpu-power-limit: $h power limit $W W"
        applied=$((applied + 1))
    done
    [ "$applied" -gt 0 ] && exit 0
    n=$((n + 1)); sleep 1
done
echo "fd44-gpu-power-limit: no amdgpu device with a power limit found" >&2
exit 1
HELPER
    chmod 0755 "$pl_helper"
    cat > "$pl_unit" <<UNIT
# Written by bin/gaming-setup.sh (fd44_hyprdot).
[Unit]
Description=AMD GPU power limit (${GPU_POWER_LIMIT} W) - boot and resume
After=systemd-modules-load.service suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
Environment=WATTS=${GPU_POWER_LIMIT}
ExecStart=/usr/local/sbin/fd44-gpu-power-limit

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
UNIT
    systemctl daemon-reload
    systemctl enable fd44-gpu-power-limit.service
    systemctl start fd44-gpu-power-limit.service
    printf '    applied now, and at every boot and resume\n'
fi


# -------------------------------------------------------------------------
# CPU energy preference after GameMode
# -------------------------------------------------------------------------
# WHY. GameMode switches the CPU governor to performance while a game runs and
# back to powersave afterwards. On amd-pstate-epp the performance governor also
# forces the energy_performance_preference (EPP) to "performance" - and
# switching the governor back does NOT restore it. Measured on the 9700X:
# balance_performance on all 16 threads before a `gamemoded -t`, governor back
# to powersave after it, EPP still "performance", and it stays there until a
# reboot. So the first game after boot left the CPU in performance mode for
# the rest of the day. GameMode 1.8.2 has no setting for EPP.
#
# HOW. A GameMode end hook in /etc/gamemode.ini (gamemoded merges it over its
# own defaults) writes EPP_DEFAULT back. The hook runs as the player and EPP is
# root-only in sysfs, so a tmpfiles.d rule makes it writable by the gamemode
# group - the group GameMode's own polkit rule already trusts with the
# governor, and which the step above put the player in.
#
# The value is FIXED, not saved when a game starts: nothing records whether
# gamemoded runs start hooks before or after it switches the governor, and a
# hook saving afterwards would faithfully restore "performance".
#
# The hook returns at once and restores from a background child that waits
# for the governor to leave performance first: the kernel refuses an EPP change
# while the performance governor holds it, and gamemoded waits for end scripts
# (up to script_timeout) - a hook that waited inline could be what the governor
# reset was waiting behind.
#
# NO RELOGIN NEEDED, and none would help. sysfs checks the writing PROCESS's
# groups, and gamemoded - with every other app in the session - is started by
# the systemd user manager, which keeps the group list it had at boot. Logging
# out does not refresh it: autologin returns faster than logind's user-stop
# delay, so the manager never stops. Measured on the desktop after a logout:
# user@1000 still up since boot, and a Hyprland started 15:48:30 still without
# the gamemode group. So the hook re-runs itself through `sg gamemode`, which
# reads the group database instead - no password for a listed member.
EPP_DEFAULT=balance_performance
epp_file=/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
epp_rule="$R/etc/tmpfiles.d/fd44-cpu-epp.conf"
epp_hook="$R/usr/local/bin/fd44-epp"
gm_ini="$R/etc/gamemode.ini"
log "CPU energy preference after GameMode"
if [[ ! -e $epp_file ]]; then
    printf '    this CPU driver exposes no energy preference - nothing to restore\n'
elif (( DRY )); then
    printf '\033[1;34mwould write:\033[0m %s, %s and %s, apply the rule, set EPP to %s\n' \
        "$epp_rule" "$epp_hook" "$gm_ini" "$EPP_DEFAULT"
else
    install -d "$(dirname "$epp_rule")" "$(dirname "$epp_hook")" "$(dirname "$gm_ini")"
    cat > "$epp_rule" <<'RULE'
# Written by bin/gaming-setup.sh (fd44_hyprdot). Lets the gamemode group set
# the CPU energy preference, so GameMode's end hook can put it back after a
# game - the performance governor forces it to "performance" and leaving that
# governor does not restore it.
z /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 0664 root gamemode -
RULE
    cat > "$epp_hook" <<'HOOK'
#!/bin/sh
# Written by bin/gaming-setup.sh (fd44_hyprdot). GameMode end hook:
#   fd44-epp <preference>     e.g. fd44-epp balance_performance
# Returns immediately; a background child waits (up to 10 s) for the governor
# to leave "performance" - the kernel will not change EPP under it - then
# writes the preference to every CPU.
want="${1:-balance_performance}"
cpu="${CPU_ROOT:-/sys/devices/system/cpu}"      # test prefix; the real tree by default

# gamemoded usually runs with a group list older than the player's gamemode
# membership - it is started by the systemd user manager, which a logout does
# not restart - and sysfs checks this process's groups. sg takes the group
# from the group database instead, without a password for a listed member.
case " $(id -Gn) " in
    *" gamemode "*) ;;
    *) exec sg gamemode -c "'$0' '$want'" </dev/null ;;
esac
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
    chmod 0755 "$epp_hook"

    # Not over someone else's GameMode config: say what to add instead.
    if [[ -f $gm_ini ]] && ! grep -q 'fd44-epp' "$gm_ini"; then
        warn "$gm_ini exists and was not written by this script - add to its [custom] section:"
        warn "  end=/usr/local/bin/fd44-epp $EPP_DEFAULT"
    else
        cat > "$gm_ini" <<INI
; Written by bin/gaming-setup.sh (fd44_hyprdot). gamemoded merges this over
; /usr/share/gamemode/gamemode.ini, so only what differs is here.
[custom]
; Put the CPU energy preference back after a game - see fd44-epp.
end=/usr/local/bin/fd44-epp $EPP_DEFAULT
INI
    fi

    # The rule now, not only from the next boot, and the preference back to its
    # default in case an earlier game already left it at performance.
    systemd-tmpfiles --create "$epp_rule"
    if [[ $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) != performance ]]; then
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            printf '%s' "$EPP_DEFAULT" > "$f"
        done
    fi
    printf '    restored to %s after every game\n' "$EPP_DEFAULT"
fi


# -------------------------------------------------------------------------
# MangoHud overlay
# -------------------------------------------------------------------------
# The overlay's two layouts live in this repo (mangohud/), linked rather than
# copied, so an edit in the repo is what the next game shows. The two files,
# not the directory: MangoHud may keep state beside its config, and that has
# no business in a git checkout.
#
# As the player, like everything else in their home. A file already there that
# is not this link is moved aside, not overwritten.
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mh_dir="$target_home/.config/MangoHud"
log "MangoHud overlay"
if [[ ! -f $repo/mangohud/MangoHud.conf || ! -f $repo/mangohud/presets.conf ]]; then
    warn "no mangohud/ configs in $repo - skipping the overlay"
elif (( DRY )); then
    printf '\033[1;34mwould link:\033[0m %s/MangoHud.conf and presets.conf -> %s/mangohud/\n' "$mh_dir" "$repo"
else
    runuser -u "$target_user" -- mkdir -p "$mh_dir"
    for f in MangoHud.conf presets.conf; do
        src="$repo/mangohud/$f"
        dst="$mh_dir/$f"
        if [[ -L $dst && $(readlink "$dst") == "$src" ]]; then
            continue
        fi
        if [[ -e $dst || -L $dst ]]; then
            runuser -u "$target_user" -- mv "$dst" "$dst.before-fd44-$(date +%Y%m%d-%H%M%S)"
            printf '    kept the previous %s beside it\n' "$f"
        fi
        runuser -u "$target_user" -- ln -s "$src" "$dst"
    done
    printf '    %s -> %s/mangohud/\n' "$mh_dir" "$repo"
fi


# -------------------------------------------------------------------------
# CPU power for the overlay
# -------------------------------------------------------------------------
# WHY. MangoHud reads CPU power from the RAPL energy counter,
# /sys/class/powercap/intel-rapl:0/energy_uj - Intel's name, but the same
# interface serves AMD Zen. The kernel makes that file root-only because
# fine-grained energy readings are a side channel (PLATYPUS, CVE-2020-8694):
# an unprivileged process can learn about work another user's processes do.
# Measured on the 9700X: -r-------- root root, and MangoHud's library carries
# "Rapl: energy_uj is not accessible" - CPU power was blank in the overlay.
#
# HOW. A udev rule gives the gamemode group read access to package-0's counter,
# the one MangoHud reads: one group, one file, never world-readable. The player
# is that group's only member, and anything running as the player can already
# read the player's own data directly, so the side channel opens to nobody new.
#
# udev rather than tmpfiles.d, unlike the EPP rule above: the rapl modules are
# loaded by udev, and a tmpfiles line can run before the file exists.
rapl_zone=/sys/class/powercap/intel-rapl:0
rapl_rule="$R/etc/udev/rules.d/60-fd44-rapl-read.rules"
log "CPU power for the overlay"
if [[ ! -e $rapl_zone/energy_uj ]]; then
    printf '    this CPU exposes no RAPL energy counter - CPU power stays blank\n'
elif (( DRY )); then
    printf '\033[1;34mwould write:\033[0m %s, and apply it now\n' "$rapl_rule"
else
    install -d "$(dirname "$rapl_rule")"
    cat > "$rapl_rule" <<'RULE'
# Written by bin/gaming-setup.sh (fd44_hyprdot). Lets the gamemode group read the
# CPU package energy counter, so MangoHud can show CPU power. Root-only by
# default because energy readings are a side channel: one group, one file.
SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0", RUN+="/usr/bin/chgrp gamemode /sys%p/energy_uj", RUN+="/usr/bin/chmod 0440 /sys%p/energy_uj"
RULE
    # Applied through the rule itself rather than a separate chmod, so a rule
    # that does not work shows up now instead of after the next boot.
    udevadm control --reload
    udevadm trigger --action=change --settle "$rapl_zone"
    printf '    %s\n' "$(stat -c '%A %U:%G' "$rapl_zone/energy_uj")"
fi


# -------------------------------------------------------------------------
# Proton-GE (optional)
# -------------------------------------------------------------------------
# Valve's Proton covers most of the catalogue. GE-Proton is a community
# build carrying extra media codecs and per-game patches, and it is the
# usual answer when a specific title will not run. Off by default: it is a
# tarball from GitHub rather than a package, so nothing updates it for you.
if (( PROTON_GE )); then
    log "Proton-GE"
    tools_dir="$target_home/.steam/root/compatibilitytools.d"
    if (( DRY )); then
        printf '\033[1;34mwould run:\033[0m fetch latest GE-Proton into %s\n' "$tools_dir"
    else
        api="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
        tag="$(curl -fsSL --max-time 30 "$api" \
               | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1 || true)"
        [[ -n $tag ]] || die "could not find the latest GE-Proton release - check the network"
        # The tag becomes a path and part of a URL, and it came from a web API.
        [[ $tag =~ ^GE-Proton[0-9]+-[0-9]+$ ]] || die "unexpected GE-Proton release name: $tag"

        # Releases are published per architecture now: GE-Proton11-6-x86_64.tar.gz
        # beside GE-Proton11-6-x86_64.sha512sum, unpacking into a folder of the
        # same name. The bare "$tag.tar.gz" this used to fetch is a 404.
        asset="$tag-x86_64"

        # Either folder name counts - older releases unpacked without the suffix.
        if [[ -d "$tools_dir/$asset" || -d "$tools_dir/$tag" ]]; then
            printf '    %s already installed\n' "$tag"
        else
            printf '    installing %s\n' "$tag"
            # As the user, for the same reason as the Steam library above:
            # install -d would leave the intermediate ~/.steam and
            # ~/.steam/root owned by root.
            runuser -u "$target_user" -- mkdir -p "$tools_dir"
            # The temp directory, the download and the extraction are all the
            # user's. A root mktemp -d is mode 0700, so the user-side tar below
            # could not even open the tarball - --proton-ge always died at
            # "could not extract" before this.
            tmp="$(runuser -u "$target_user" -- mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            base="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$tag"
            # Saved under its published name: the checksum file refers to it by
            # that name, so sha512sum --check finds it only if it matches.
            runuser -u "$target_user" -- curl -fsSL --retry 2 --max-time 900 \
                "$base/$asset.tar.gz" -o "$tmp/$asset.tar.gz" \
                || die "download failed: $base/$asset.tar.gz"
            # Verified against the checksum the release publishes beside it,
            # so a truncated or swapped download is refused rather than
            # unpacked into Steam.
            runuser -u "$target_user" -- curl -fsSL --retry 2 --max-time 60 \
                "$base/$asset.sha512sum" -o "$tmp/$asset.sha512sum" \
                || die "could not fetch the checksum: $base/$asset.sha512sum"
            ( cd "$tmp" && runuser -u "$target_user" -- sha512sum --check --status "$asset.sha512sum" ) \
                || die "$asset.tar.gz does not match its published sha512 - not installing"
            # As the user, so every extracted file is owned by them - Steam
            # will not load a compatibility tool it cannot read.
            runuser -u "$target_user" -- tar -xzf "$tmp/$asset.tar.gz" -C "$tools_dir" \
                || die "could not extract $tag"
            printf '    installed - restart Steam, then pick it in a game'\''s\n'
            printf '    Properties -> Compatibility\n'
        fi
    fi
fi


# -------------------------------------------------------------------------
# Verification
# -------------------------------------------------------------------------
# Same idea as the installer's final pass, and for the same reason: every
# check that only asks rpm whether a package is installed has a blind spot.
# The ones that matter RUN the thing. `powerprofilesctl` was installed and
# on $PATH and broken for a whole day on the laptop because its python
# dependency was missing and no check ever executed it.
if (( DRY )); then
    log "dry run - skipping verification"
    exit 0
fi

printf '\n'
log "verification"
pass=0; fail=0
ok()   { printf '    \033[1;32mok\033[0m   %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '    \033[1;31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }

# Repos
for kind in free nonfree; do
    rpm -q "rpmfusion-$kind-release" >/dev/null 2>&1 \
        && ok "rpmfusion-$kind enabled" || bad "rpmfusion-$kind missing"
done

# Packages, both architectures where it matters
rpm -q steam >/dev/null 2>&1 && ok "steam $(rpm -q --qf '%{version}' steam)" || bad "steam not installed"
# By architecture. A bare `rpm -q mangohud` is satisfied by either one, which
# is exactly how a missing x86_64 half passed this check once.
for p in gamemode.x86_64 gamemode.i686 mangohud.x86_64 mangohud.i686 gamescope vulkan-tools; do
    rpm -q "$p" >/dev/null 2>&1 && ok "$p" || bad "$p not installed"
done

# MangoHud from the COPR, both halves, new enough to have the logging fix.
# rpm's own vercmp, so 0.8.3~rc1 counts as older than 0.8.3.
for arch in x86_64 i686; do
    evr="$(rpm -q --qf '%{evr}' "mangohud.$arch" 2>/dev/null || true)"
    from="$(dnf5 repoquery -q --installed --qf '%{from_repo}' "mangohud.$arch" 2>/dev/null || true)"
    cmp="$(rpm --eval "%{lua: print(rpm.vercmp('${evr%%-*}', '0.8.3'))}" 2>/dev/null || true)"
    if [[ $from == fd44-bazzite-mangohud* && ${cmp:--1} -ge 0 ]]; then
        ok "mangohud.$arch $evr from $from (logging no longer crashes games)"
    else
        bad "mangohud.$arch is ${evr:-missing} from ${from:-?} - expected 0.8.3 or newer from fd44-bazzite-mangohud"
    fi
done

# Controller support. steam Requires steam-devices, which is the udev rules
# for every controller Steam Input understands - without them a DualSense or
# an Xbox pad over USB is visible to the kernel but not writable by your
# user, so it appears in Steam and does nothing.
if compgen -G '/usr/lib/udev/rules.d/*steam*' >/dev/null; then
    ok "controller udev rules ($(compgen -G '/usr/lib/udev/rules.d/*steam*' | wc -l) files)"
else
    bad "no steam udev rules in /usr/lib/udev/rules.d - controllers will not work"
fi

# RADV, actually loaded - AS THE USER WHO PLAYS, not as root.
#
# This used to run vulkaninfo as root, straight from the sudo'd script. On the
# RX 9070 XT desktop that reported no Vulkan device at all, while the same two
# lines run as jc a minute later - same pipeline, same shell options, even with
# the stripped environment sudo leaves - found RADV eight times out of eight,
# and the kernel logged no GPU fault. Root's Vulkan view is not what a game
# gets, so it was never the right thing to test. The player's is.
#
# RADV SPECIFICALLY, not "a device". Mesa also ships llvmpipe, a CPU renderer
# that enumerates as a Vulkan device too; a machine where only llvmpipe loads
# used to pass this check with a warning, and would run games at a few frames
# a second. vulkaninfo now runs once, and its own messages are kept, so a
# failure says why instead of only that. vulkaninfo is x86_64, so this answers
# for 64-bit.
vk="$(runuser -u "$target_user" -- vulkaninfo --summary 2>&1 || true)"
radv="$(printf '%s\n' "$vk" | grep -m1 'deviceName.*RADV' | sed 's/.*deviceName *= *//' || true)"
if [[ -n $radv ]]; then
    ok "Vulkan (as $target_user): $radv"
else
    found="$(printf '%s\n' "$vk" | sed -n 's/.*deviceName *= *//p' | paste -sd, - || true)"
    bad "no RADV device for $target_user - found: ${found:-nothing}"
    printf '%s\n' "$vk" | grep -iE 'error|fail|cannot' | head -5 | sed 's/^/         /' || true
fi

# 32-bit Vulkan cannot be probed with the 64-bit vulkaninfo, so check that
# the i686 ICD and driver are on disk. A missing one is why a 32-bit title
# starts, shows a black window and exits.
icd32="$(ls /usr/share/vulkan/icd.d/radeon_icd.i686.json 2>/dev/null || true)"
lib32="$(ls /usr/lib/libvulkan_radeon.so 2>/dev/null || true)"
if [[ -n $icd32 && -n $lib32 ]]; then
    ok "32-bit Vulkan ICD present (radeon_icd.i686.json)"
else
    bad "32-bit Vulkan ICD or driver missing - 32-bit games will not render"
fi

# VA-API, by which driver is installed rather than by running vainfo -
# vainfo means installing libva-utils, and one more package for one line of
# output is not the trade this project makes.
if rpm -q mesa-va-drivers-freeworld.x86_64 >/dev/null 2>&1; then
    ok "VA-API: freeworld driver (H.264/HEVC enabled)"
elif rpm -q mesa-va-drivers.x86_64 >/dev/null 2>&1; then
    bad "VA-API: Fedora's mesa-va-drivers - no H.264/HEVC"
else
    bad "VA-API: no Mesa VA driver at all"
fi

# gamemoded, RUN. It talks over D-Bus and needs its python and glib pieces
# present; `rpm -q gamemode` says nothing about whether it works.
if gamemoded --version >/dev/null 2>&1; then
    ok "gamemoded runs ($(gamemoded --version 2>&1 | head -1))"
else
    bad "gamemoded is installed but will not run"
fi

# gamemoderun, RUN, from a 64-bit program. The daemon starting proves nothing
# about the client library a game preloads, and a missing one is not fatal -
# ld.so prints an error and the game runs WITHOUT GameMode, silently.
preload="$(gamemoderun /usr/bin/true 2>&1 || true)"
if [[ $preload == *"cannot be preloaded"* ]]; then
    bad "gamemoderun cannot preload into 64-bit programs (libgamemodeauto missing)"
else
    ok "gamemoderun preloads into 64-bit programs"
fi

# The permission GameMode needs for the one thing it is mostly used for - see
# "GameMode permissions" above. Membership first, because it is the cause...
if grep -qx gamemode <<<"$(id -nG "$target_user" | tr ' ' '\n')"; then
    ok "$target_user is in the gamemode group"
else
    bad "$target_user is not in the gamemode group - GameMode cannot switch the CPU governor"
fi

# ...and then the effect, RUN: gamemoded's own self-test switches the governor
# to performance and back, as the player, over the player's session bus.
# Membership alone was not proof enough to stop here - the polkit rule could
# change under it - and a passing test is exactly what a game will get.
gm_uid="$(id -u "$target_user")"
gm_test="$(runuser -u "$target_user" -- env XDG_RUNTIME_DIR="/run/user/$gm_uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$gm_uid/bus" gamemoded -t 2>&1 || true)"
#
# The test RE-EXECS ITSELF, so its output holds several rounds, each with its
# own "Verifying CPU governor setting" line followed by Passed or Failed. Pass
# only if every round reported and none failed.
gov_results="$(grep -A1 'Verifying CPU governor setting' <<<"$gm_test" | grep -vE 'Verifying|^--$' || true)"
if [[ -n $gov_results ]] && ! grep -q 'Failed' <<<"$gov_results" \
   && ! grep -q 'Governor was not set' <<<"$gm_test"; then
    ok "GameMode switches the CPU governor (gamemoded -t)"
else
    bad "GameMode could not switch the CPU governor (gamemoded -t) - games run without it"
fi

# The energy preference comes back after GameMode - see "CPU energy preference
# after GameMode". The self-test just above ran a full GameMode session, so its
# end hook has already fired.
if [[ -e $epp_file ]]; then
    if [[ -f /etc/tmpfiles.d/fd44-cpu-epp.conf && $(stat -c '%a %G' "$epp_file") == "664 gamemode" ]]; then
        ok "CPU energy preference writable by the gamemode group"
    else
        bad "CPU energy preference is $(stat -c '%a %G' "$epp_file") - the tmpfiles rule is missing or not applied"
    fi

    if [[ -x /usr/local/bin/fd44-epp ]] && grep -q '^end=/usr/local/bin/fd44-epp' /etc/gamemode.ini 2>/dev/null; then
        ok "GameMode end hook restores the energy preference"
    else
        bad "GameMode end hook missing (/usr/local/bin/fd44-epp or its line in /etc/gamemode.ini)"
    fi

    # RUN. Give the hook's background child its few seconds, then read it back.
    for _ in $(seq 1 25); do
        [[ $(cat "$epp_file") == "$EPP_DEFAULT" ]] && break
        sleep 0.2
    done
    epp_now="$(cat "$epp_file")"
    if [[ $epp_now == "$EPP_DEFAULT" ]]; then
        ok "energy preference is back to $EPP_DEFAULT after a GameMode session"
    else
        bad "energy preference is $epp_now after a GameMode session, expected $EPP_DEFAULT"
    fi
fi

# gamescope, RUN. --help needs no display, so this works over ssh.
gamescope --help >/dev/null 2>&1 \
    && ok "gamescope runs" || bad "gamescope is installed but will not run"

# Xwayland. The Steam client is X11; without Xwayland it cannot open a
# window at all, and Hyprland reports xwayland:enabled = true regardless.
command -v Xwayland >/dev/null 2>&1 \
    && ok "Xwayland present (the Steam client is X11)" \
    || bad "Xwayland missing - the Steam client cannot start"

# ntsync, which Proton uses for Win32 sync primitives. Not fatal; Proton
# falls back to esync/fsync.
if [[ -e /dev/ntsync ]]; then
    ok "/dev/ntsync present (Proton uses it for Win32 sync)"
else
    printf '    \033[1;33mnote\033[0m /dev/ntsync absent - Proton will fall back to fsync\n'
fi

# The sysctl every guide tells you to set. Fedora already does.
mmc="$(cat /proc/sys/vm/max_map_count)"
(( mmc >= 1048576 )) \
    && ok "vm.max_map_count = $mmc (already high enough; do not set it again)" \
    || bad "vm.max_map_count = $mmc - too low for some Proton titles"

# The frame cap file, and that it says what it should.
if [[ -f $cap_file ]] && grep -q "^export VKD3D_FRAME_RATE=$FRAME_CAP$" "$cap_file" \
   && [[ $(stat -c %U "$cap_file") == "$target_user" ]]; then
    ok "frame cap $FRAME_CAP fps in $cap_file (applies from next login)"
else
    bad "frame cap file missing, wrong, or not owned by $target_user: $cap_file"
fi

# GPU power limit: installed, enabled for boot AND resume, and in effect now.
if [[ -x /usr/local/sbin/fd44-gpu-power-limit && -f /etc/systemd/system/fd44-gpu-power-limit.service ]]; then
    ok "GPU power-limit helper and unit installed"
else
    bad "GPU power-limit helper or unit missing"
fi
[[ $(systemctl is-enabled fd44-gpu-power-limit.service 2>/dev/null) == enabled ]] \
    && ok "GPU power-limit unit enabled at boot" || bad "GPU power-limit unit not enabled"
[[ -L /etc/systemd/system/suspend.target.wants/fd44-gpu-power-limit.service ]] \
    && ok "GPU power-limit unit reapplies after resume" || bad "GPU power-limit unit not hooked to suspend.target"
pl_now=""
for h in /sys/class/hwmon/hwmon*; do
    [[ $(cat "$h/name" 2>/dev/null) == amdgpu && -e $h/power1_cap ]] && pl_now=$(( $(cat "$h/power1_cap") / 1000000 ))
done
[[ $pl_now == "$GPU_POWER_LIMIT" ]] \
    && ok "GPU power limit is ${GPU_POWER_LIMIT} W now" || bad "GPU power limit reads ${pl_now:-nothing}, expected ${GPU_POWER_LIMIT} W"

# MangoHud: both layouts linked into the player's home, and CPU power readable
# AS THE PLAYER - root being able to read the counter proves nothing.
mh_links=0
for f in MangoHud.conf presets.conf; do
    if [[ $(readlink "$target_home/.config/MangoHud/$f" 2>/dev/null) == "$repo/mangohud/$f" ]]; then
        mh_links=$((mh_links + 1))
    fi
done
(( mh_links == 2 )) \
    && ok "MangoHud overlay config linked from $repo/mangohud" \
    || bad "MangoHud config not linked into $target_home/.config/MangoHud ($mh_links of 2)"
if [[ -e /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
    if runuser -u "$target_user" -- cat /sys/class/powercap/intel-rapl:0/energy_uj >/dev/null 2>&1; then
        ok "CPU energy counter readable by $target_user (MangoHud CPU power)"
    else
        bad "CPU energy counter not readable by $target_user - MangoHud CPU power will be blank"
    fi
fi

# OWNERSHIP OF THE WHOLE STEAM TREE, not just the leaf. A root-owned
# directory anywhere in here stops Steam extracting its bootstrap, and the
# error it prints names tar, not permissions.
steam_root="$target_home/.local/share/Steam"
if [[ -d $steam_root ]]; then
    bad_owner="$(find "$steam_root" -maxdepth 1 ! -user "$target_user" -printf '%p ' 2>/dev/null || true)"
    if [[ -z $bad_owner ]]; then
        ok "Steam tree is owned by $target_user"
    else
        bad "not owned by $target_user: $bad_owner"
    fi
fi

# Btrfs nodatacow on the library
if [[ $fstype == btrfs && -d $steam_lib ]]; then
    if grep -q C <<<"$(lsattr -d "$steam_lib" 2>/dev/null | cut -d' ' -f1)"; then
        ok "Steam library is nodatacow"
    else
        bad "Steam library is NOT nodatacow ($steam_lib)"
    fi
fi

printf '\n'
if (( fail )); then
    printf '\033[1;31m%d check(s) failed\033[0m, %d passed\n' "$fail" "$pass"
    exit 1
fi
log "all $pass checks passed"
printf '\n'
printf 'Next, as %s:\n' "$target_user"
printf '  1. run  steam  once and log in; it downloads its own runtime\n'
printf '  2. Settings -> Compatibility -> "Enable Steam Play for all other titles"\n'
printf '  3. per-title launch options, if a game needs them:\n'
printf '       gamemoderun %%command%%\n'
printf '       mangohud gamemoderun %%command%%\n'
printf '         (Right Shift+F12 shows/hides the overlay, Right Shift+F10 switches layout)\n'
printf '       gamescope -W 2560 -H 1440 -f -- %%command%%\n'
