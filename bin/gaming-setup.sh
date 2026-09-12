#!/usr/bin/env bash
# =========================================================================
# gaming-setup.sh - turn this machine into a Steam gaming machine
# =========================================================================
#
# Usage:  sudo bin/gaming-setup.sh [--dry-run] [--proton-ge] [-y]
#
# DELIBERATELY NOT PART OF THE INSTALLER. install_fedora_v1_11.sh builds the
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
#   - installs steam, and the tools that make it usable on Hyprland
#   - swaps Mesa's VA-API driver for RPM Fusion's, which has the H.264 and
#     HEVC paths compiled in
#   - marks the Steam library nodatacow on Btrfs
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
            sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf 'gaming-setup: unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }

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
if ! lsmod | grep -q '^amdgpu'; then
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
    gamemode
    gamemode.i686

    # The performance overlay. Same reasoning for the second architecture.
    mangohud
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
    printf '\033[1;34mwould run:\033[0m install -d -o %s -g %s %s && chattr +C %s\n' \
        "$target_user" "$target_user" "$steam_lib" "$steam_lib"
else
    install -d -o "$target_user" -g "$target_user" "$steam_lib"
    if chattr +C "$steam_lib" 2>/dev/null; then
        printf '    nodatacow set on %s\n' "$steam_lib"
    else
        warn "could not set nodatacow on $steam_lib (non-fatal)"
    fi
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

        if [[ -d "$tools_dir/$tag" ]]; then
            printf '    %s already installed\n' "$tag"
        else
            printf '    installing %s\n' "$tag"
            install -d -o "$target_user" -g "$target_user" "$tools_dir"
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$tag/$tag.tar.gz"
            curl -fsSL --retry 2 --max-time 900 "$url" -o "$tmp/ge.tar.gz" \
                || die "download failed: $url"
            # As the user, so every extracted file is owned by them - Steam
            # will not load a compatibility tool it cannot read.
            runuser -u "$target_user" -- tar -xzf "$tmp/ge.tar.gz" -C "$tools_dir" \
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
for p in gamemode gamemode.i686 mangohud mangohud.i686 gamescope vulkan-tools; do
    rpm -q "$p" >/dev/null 2>&1 && ok "$p" || bad "$p not installed"
done

# Controller support. steam Requires steam-devices, which is the udev rules
# for every controller Steam Input understands - without them a DualSense or
# an Xbox pad over USB is visible to the kernel but not writable by your
# user, so it appears in Steam and does nothing.
if ls /usr/lib/udev/rules.d/*steam* >/dev/null 2>&1; then
    ok "controller udev rules ($(ls /usr/lib/udev/rules.d/*steam* | wc -l) files)"
else
    bad "no steam udev rules in /usr/lib/udev/rules.d - controllers will not work"
fi

# RADV, actually loaded. vulkaninfo is x86_64, so this answers for 64-bit.
radv="$(vulkaninfo --summary 2>/dev/null | sed -n 's/.*deviceName *= *//p' | head -1 || true)"
drv="$(vulkaninfo --summary 2>/dev/null | sed -n 's/.*driverName *= *//p' | head -1 || true)"
if [[ -n $radv ]]; then
    ok "Vulkan: $radv (${drv:-unknown driver})"
    [[ $drv == *radv* ]] || warn "  expected the radv driver on AMD"
else
    bad "vulkaninfo reports no Vulkan device - RADV is not loading"
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

# Btrfs nodatacow on the library
if [[ $fstype == btrfs && -d $steam_lib ]]; then
    if lsattr -d "$steam_lib" 2>/dev/null | cut -d' ' -f1 | grep -q C; then
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
printf '       gamescope -W 2560 -H 1440 -f -- %%command%%\n'
