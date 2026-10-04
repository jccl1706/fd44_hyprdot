#!/usr/bin/env bash
# =========================================================================
# fedora_desktop.sh - NVIDIA and a minimal KDE, on a booted Fedora
# =========================================================================
#
# Usage:  sudo install/fedora_desktop.sh [--go]
#
# Stage four of four, and the first that runs ON the new machine rather than
# from the one beside it. Stages one to three were a chroot; this needs a
# running kernel to build a module against.
#
# ORDER IS DELIBERATE: RPM Fusion, then NVIDIA, then KDE, and a reboot to prove
# the driver before a display manager depends on it. The Gentoo install this
# disk used to carry was locked out of booting by exactly this module, and the
# difference between "no desktop" and "no machine" is worth one extra reboot.
#
# WEAK DEPENDENCIES ARE ON HERE, unlike the bootstrap. That was a deliberate
# "name everything"; akmod-nvidia genuinely needs its recommends to build and
# load, and a KDE missing its recommends is a desktop with no icons, no
# portals and no keyring. The minimalism in this file is the PACKAGE LIST, not
# the dependency resolver.

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
[[ -f /etc/fedora-release ]] || die "this runs ON the Fedora install, not from NixOS"
RELEASEVER="$(rpm -E %fedora)"
KVER="$(uname -r)"

note "this machine"
printf '  %-12s %s\n' "fedora"  "$RELEASEVER"
printf '  %-12s %s\n' "kernel"  "$KVER"
printf '  %-12s %s\n' "packages" "$(rpm -qa | wc -l)"
printf '  %-12s %s\n' "gpu"     "$(lspci -nn | grep -i 'VGA\|3D' | head -1 | cut -c1-70)"
printf '\n'

# THE KDE LIST, NAMED RATHER THAN GROUPED.
#
# @kde-desktop-environment is about 1800 packages. This is the set that makes a
# usable Plasma and stops: the shell, the display manager, a file manager, an
# archiver, a terminal, the settings panel. It mirrors what
# fd44_nixos/modules/desktop-plasma.nix keeps on the other disk, so the two
# machines feel the same.
#
# plasma-workspace brings kwin, the panel and the compositor. plasma-desktop is
# the desktop shell proper. xdg-desktop-portal-kde is NOT optional: without it
# file pickers and screen sharing fail in Wayland applications, and it fails
# quietly at the moment you try to use one.
KDE=(
    plasma-desktop plasma-workspace
    sddm sddm-breeze
    xdg-desktop-portal-kde
    dolphin ark konsole
    plasma-systemsettings
    plasma-nm plasma-pa
    kscreen
    breeze-gtk

    # DISCOVER, and only the backend this machine actually uses. Fedora splits
    # it into nine packages: plasma-discover is the shell, and each backend is
    # separate. packagekit is the one that talks to dnf.
    #
    # Deliberately NOT installed: -rpm-ostree (that is Silverblue, not this),
    # -snap (no snapd here), -kns (store content, wallpapers and widgets),
    # -flatpak (nothing uses flatpak on this machine - add it with flatpak
    # itself if that changes).
    #
    # -notifier is what tells you updates exist without opening anything, which
    # is the same job the fd44 bar's update box does on the Hyprland machines.
    plasma-discover plasma-discover-packagekit plasma-discover-notifier
    pipewire wireplumber pipewire-pulseaudio
)

# THE TOOLS A MACHINE NEEDS WHEN SOMETHING GOES WRONG, which is not the same
# list as the tools it needs to run. Every one of these was wanted at some point
# while building this install and was not there; none of them is bloat, and
# together they are a few MB.
TOOLS=(
    bash-completion       # dnf and systemctl are unusable without it
    lsof strace           # what is holding this file, what is this process doing
    wget                  # curl is in @core; wget is what half of every README uses
    git                   # this repository has to be clonable on the machine
    rsync                 # moving things between the two systems on this box
)

# THE BROWSERS. Chromium is in Fedora's own repositories; Brave is not and
# never will be, so it comes from its own.
#
# chromium-qt6-ui IS THE POINT OF SPLITTING THIS OUT. Fedora builds Chromium's
# toolkit layer as separate subpackages, and the default pulls the GTK one. On
# a Plasma desktop that means GTK file dialogs, GTK scrollbars and a browser
# that does not follow the system theme. The Qt6 build uses Plasma's own file
# picker and colours.
CHROMIUM=(
    chromium
    chromium-qt6-ui
)

if (( ! GO )); then
    note "would enable RPM Fusion free + nonfree for Fedora $RELEASEVER"
    note "would install akmod-nvidia xorg-x11-drv-nvidia-cuda"
    note "would install, with weak deps:"
    printf '    %s\n' "${KDE[@]}" "${TOOLS[@]}" "${CHROMIUM[@]}"
    note "would add Brave's repository and install brave-browser"
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

# --- RPM Fusion --------------------------------------------------------------
#
# BOTH REPOSITORIES. The NVIDIA driver is in nonfree; free is what nonfree's
# packages expect to resolve against, and installing one without the other
# produces dependency failures that name neither.
note "enabling RPM Fusion"
dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$RELEASEVER.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$RELEASEVER.noarch.rpm"

note "refreshing metadata"
dnf -y makecache

# --- NVIDIA ------------------------------------------------------------------
#
# akmod, NOT kmod: akmod rebuilds the module against each new kernel as it is
# installed. A kmod is built for one kernel and silently stops matching after
# the next update, which on this hardware means no display.
#
# THE KERNEL HEADERS MATTER and are not implied. akmods needs kernel-devel for
# the RUNNING kernel to build against; without it the build is skipped and the
# failure only appears at the next boot, as a black screen.
note "installing the NVIDIA driver"
dnf -y install kernel-devel-"$KVER" akmod-nvidia xorg-x11-drv-nvidia-cuda

note "building the module for $KVER now, rather than discovering it at boot"
akmods --kernels "$KVER" --force || warn "akmods reported a problem - check before rebooting"

# --- the kernel command line -------------------------------------------------
#
# nvidia_drm.modeset=1 AND fbdev=1. The first gives the driver kernel mode
# setting, which Wayland requires. The second gives it a framebuffer console -
# without it the machine boots to a black screen between the bootloader and the
# display manager, which looks exactly like a failed boot.
#
# This cost real time on the Gentoo install that used to be on this disk; the
# write-up is in install/gentoo_desktop.sh and the salvaged scripts on the T5.
note "adding the NVIDIA kernel parameters"
CMDLINE=/etc/kernel/cmdline
for arg in nvidia_drm.modeset=1 nvidia_drm.fbdev=1; do
    grep -qw -- "$arg" "$CMDLINE" || printf ' %s' "$arg" >> "$CMDLINE"
done
sed -i 's/[[:space:]]\+/ /g; s/[[:space:]]*$//' "$CMDLINE"
printf '  %s\n' "$(cat "$CMDLINE")"

note "rewriting the boot entry with the new command line"
kernel-install add "$KVER" "/usr/lib/modules/$KVER/vmlinuz"
grep -h ^options /boot/loader/entries/*.conf | sed 's/^/  /'

# --- KDE ---------------------------------------------------------------------
note "installing a minimal KDE (${#KDE[@]} packages named, plus their deps)"
dnf -y install "${KDE[@]}"

note "and the tools for when something goes wrong"
dnf -y install "${TOOLS[@]}"

note "Chromium, with the Qt6 UI so it matches Plasma"
dnf -y install "${CHROMIUM[@]}"

# --- Brave -------------------------------------------------------------------
#
# ITS OWN REPOSITORY, SIGNED WITH ITS OWN KEY. Brave publishes a .repo file that
# sets gpgcheck=1 and points at its key; importing the key first means the very
# first package is verified rather than trusted.
#
# NOT a flatpak, and not a tarball in $HOME: a browser gets security updates
# more often than anything else on the machine, and it should come through the
# same dnf that updates everything else.
note "adding Brave's repository"
rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-browser.asc
dnf -y config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
    || dnf -y config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

note "installing Brave"
dnf -y install brave-browser

note "enabling the display manager"
systemctl set-default graphical.target
systemctl enable sddm

printf '\n'
note "done"
printf '  %-12s %s\n' "packages" "$(rpm -qa | wc -l)"
printf '  %-12s %s\n' "root used" "$(df -h / | awk 'NR==2{print $3}')"
printf '\n'
warn "REBOOT NOW, and expect the first boot to take longer: akmod may rebuild."
warn "If it comes up to a black screen, the firmware menu still reaches NixOS."
