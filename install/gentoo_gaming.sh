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

green=$'\033[1;32m'; red=$'\033[1;31m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
die()  { printf '%sgaming:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

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
CONF

    cat > /etc/portage/package.accept_keywords/steam <<'CONF'
# The overlay keeps Steam on ~amd64; this is the package itself rather than a
# blanket ~amd64 for the system.
games-util/steam-launcher ~amd64
games-util/steam-meta ~amd64
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
run emerge --getbinpkg --newuse --oneshot x11-drivers/nvidia-drivers

note "Steam, and the two things worth having beside it"
run emerge --getbinpkg games-util/steam-launcher games-util/gamemode games-util/mangohud

note "gamemode needs its daemon"
run systemctl --global enable gamemoded 2>/dev/null || true

note "done"
printf '\n  %sstart Steam as your user, not as root:%s  steam\n' "$dim" "$reset"
printf '  %sthe first run downloads its own runtime, which takes a while%s\n\n' "$dim" "$reset"
