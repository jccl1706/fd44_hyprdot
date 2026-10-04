#!/usr/bin/env bash
# =========================================================================
# fedora_bootstrap.sh - a bootable minimal Fedora, from a running Linux
# =========================================================================
#
# Usage:  sudo install/fedora_bootstrap.sh --disk <by-id path> [--go]
#
# Stage two of three. Stage one (install_fedora_desktop.sh) partitioned and
# formatted; this fills the root with a @core Fedora, a kernel and
# systemd-boot, and stops there. Stage three adds KDE and NVIDIA.
#
# IT STOPS AT "BOOTABLE" ON PURPOSE. The Gentoo install on this same disk was
# locked out of booting by the NVIDIA module, and the lesson is to prove the
# machine starts BEFORE adding the thing most likely to stop it starting.
#
# THE ESP IS MOUNTED AT /boot, NOT /boot/efi, and that is the one real design
# decision here. Fedora's kernel-install writes Boot Loader Specification
# snippets to /boot/loader/entries; systemd-boot reads those natively, but only
# from the EFI System Partition. Mount the ESP at /boot and the two agree with
# no glue - which is exactly how NixOS is arranged on the disk beside this one.
# The alternative, Fedora's traditional separate /boot plus /boot/efi, needs
# sdubby to copy entries across and is one more thing to go wrong.
#
# 1 GiB is ample: a Fedora kernel plus its initramfs is about 70 MiB.
#
# NO WEAK DEPENDENCIES, which is most of what "no bloat" means in practice.
# install_weak_deps=False turns a @core install from several hundred packages
# into the mandatory set. Anything genuinely wanted gets named.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfedora:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }
run()  { if (( GO )); then "$@"; else printf '  %swould run:%s %s\n' "$dim" "$reset" "$*"; fi; }

DISK=""; GO=0; RELEASEVER=44; MNT=/mnt/fedora
HOSTNAME_=fedora-gaming00
TIMEZONE=America/New_York
USERNAME=jc
USERUID=1000

while (( $# )); do
    case "$1" in
        --disk) DISK="${2-}"; shift 2 ;;
        --go) GO=1; shift ;;
        --releasever) RELEASEVER="${2-}"; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

(( EUID == 0 )) || die "run this with sudo"
[[ -n $DISK ]]  || die "no --disk"
[[ $DISK == /dev/disk/by-id/* ]] || die "name the disk by /dev/disk/by-id/..."
TARGET="$(readlink -f "$DISK")"
ESP="${TARGET}p1"; ROOT="${TARGET}p2"

missing=""
need() { command -v "$1" >/dev/null 2>&1 || missing+="    $1  (nixpkgs: $2)"$'\n'; }
need dnf5 dnf5; need curl curl; need lsblk util-linux; need findmnt util-linux
[[ -n $missing ]] && { warn "missing tools:"; printf '%s' "$missing" >&2; \
    die "on NixOS:  nix-shell -p dnf5 --run 'sudo $0 ...'"; }

# --- the target must be the one stage one prepared ---------------------------
#
# CHECKED BY LABEL, not by trusting the argument. Stage one wrote FEDESP and
# FEDROOT; if they are not there, either the wrong disk was named or stage one
# did not finish, and both are reasons to stop rather than to format something.
[[ "$(lsblk -no LABEL "$ESP"  2>/dev/null | xargs)" == FEDESP  ]] \
    || die "$ESP is not labelled FEDESP - run stage one first, or check the disk"
[[ "$(lsblk -no LABEL "$ROOT" 2>/dev/null | xargs)" == FEDROOT ]] \
    || die "$ROOT is not labelled FEDROOT - run stage one first, or check the disk"

ROOT_UUID="$(lsblk -no UUID "$ROOT")"
ESP_UUID="$(lsblk -no UUID "$ESP")"

note "target"
printf '  %-10s %s  (%s)\n' "root"  "$ROOT" "$ROOT_UUID"
printf '  %-10s %s  (%s)\n' "esp"   "$ESP"  "$ESP_UUID"
printf '  %-10s %s\n'       "mount" "$MNT"
printf '  %-10s Fedora %s, hostname %s\n' "install" "$RELEASEVER" "$HOSTNAME_"
printf '\n'

if (( ! GO )); then warn "DRY RUN. Re-run with --go."; exit 0; fi

# --- mount, idempotently -----------------------------------------------------
note "mounting"
findmnt -n "$MNT"      >/dev/null 2>&1 || { mkdir -p "$MNT";      mount "$ROOT" "$MNT"; }
findmnt -n "$MNT/boot" >/dev/null 2>&1 || { mkdir -p "$MNT/boot"; mount "$ESP"  "$MNT/boot"; }
findmnt -R "$MNT" -o TARGET,SOURCE | sed 's/^/  /'

# --- the repositories, with real signature checking --------------------------
#
# THE KEY IS FETCHED FIRST so that gpgcheck can stay ON. The lazy bootstrap is
# --nogpgcheck, which means the first thing a new system does is trust several
# hundred unverified packages over the network. Fedora publishes every release
# key in one file; pointing gpgkey at it costs one curl.
note "fetching Fedora's signing keys"
KEYDIR="$MNT/etc/pki/rpm-gpg"
mkdir -p "$KEYDIR"
curl -fsSL -o "$KEYDIR/fedora.gpg" https://fedoraproject.org/fedora.gpg \
    || die "could not fetch https://fedoraproject.org/fedora.gpg"
printf '  %s bytes\n' "$(stat -c %s "$KEYDIR/fedora.gpg")"

BASE="https://download.fedoraproject.org/pub/fedora/linux"
REPOARGS=(
    --repofrompath="fedora,$BASE/releases/$RELEASEVER/Everything/x86_64/os/"
    --repofrompath="updates,$BASE/updates/$RELEASEVER/Everything/x86_64/"
    --setopt=fedora.gpgkey=file://"$KEYDIR/fedora.gpg"
    --setopt=updates.gpgkey=file://"$KEYDIR/fedora.gpg"
    # AND gpgcheck ON, EXPLICITLY. A repo created with --repofrompath defaults
    # to gpgcheck=0, so pointing gpgkey at a real key does nothing by itself -
    # the first run of this script fetched the key, set gpgkey, and still
    # finished with "skipped OpenPGP checks for 273 packages". Setting the key
    # without setting this is worse than not bothering, because it reads as
    # though verification is happening.
    --setopt=fedora.gpgcheck=True
    --setopt=updates.gpgcheck=True
    --repo=fedora --repo=updates
)

# --- the base system ---------------------------------------------------------
#
# NAMED, NOT ASSUMED. @core is the smallest group Fedora ships; everything
# beyond it here is something this machine genuinely needs to boot and be
# reachable, and each is worth a word:
#
#   kernel, kernel-modules-core   the kernel and the modules to find a disk
#   dracut, dracut-config-generic a generic initramfs - NOT host-only, because
#                                 a host-only image built in a chroot describes
#                                 the chroot's hardware, not the machine's
#   systemd-boot-unsigned         the EFI binary bootctl installs
#   systemd-udev                  bootctl itself, and kernel-install
#   NetworkManager                how the machine gets back on the network
#   openssh-server                how you reach it if the display does not work
#   sudo, passwd, util-linux      a usable first boot
#   glibc-langpack-en             locale; without it everything is C
#   zram-generator-defaults       the swap, in place of a partition
PKGS=(
    @core
    kernel kernel-modules-core
    dracut dracut-config-generic
    systemd-boot-unsigned systemd-udev
    NetworkManager
    openssh-server
    sudo passwd util-linux
    glibc-langpack-en
    zram-generator-defaults
    vim-minimal
)

note "installing the base system (no weak dependencies)"
dnf5 -y --installroot="$MNT" --releasever="$RELEASEVER" --forcearch=x86_64 \
    --setopt=install_weak_deps=False \
    "${REPOARGS[@]}" \
    install "${PKGS[@]}"

# COUNTED BY FILES, NOT BY rpm. `rpm --root` from the host reported 0 packages
# for a 773 MB tree: Fedora keeps its database at /usr/lib/sysimage/rpm, and a
# host rpm of a different version cannot necessarily read it anyway. A number
# that is confidently wrong is worse than no number.
note "base system installed"
printf '  %s in %s, %s binaries in /usr/bin\n' \
    "$(du -sh "$MNT" 2>/dev/null | cut -f1)" "$MNT" \
    "$(find "$MNT/usr/bin" -maxdepth 1 -type f 2>/dev/null | wc -l)"
printf '\n'
note "next: stage three configures and installs the bootloader in the chroot"
