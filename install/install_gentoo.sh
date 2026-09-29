#!/usr/bin/env bash
# =========================================================================
# install_gentoo.sh - Gentoo onto a second disk, from a running Linux
# =========================================================================
#
# Usage:  sudo install/install_gentoo.sh --disk <by-id path> [--dry-run]
#
# Stage one of two: partition, fetch and unpack a stage3, write the config a
# chroot needs, and leave you inside that chroot. Stage two happens in there -
# profile, kernel, bootloader, drivers - and is a separate script so that a
# mistake in it costs a chroot rather than a disk.
#
# NO INSTALL MEDIUM. Gentoo is unusual in being installable from any running
# Linux: everything here is a partition table, a tarball and a chroot. The
# machine keeps running NixOS the whole time, which also means the thing you
# are installing from cannot be the thing you are installing over - checked
# below rather than assumed.
#
# THE DISK IS NAMED BY ID, NEVER BY /dev/nvmeXn1, AND THAT IS NOT PEDANTRY ON
# THIS MACHINE: the two NVMe drives swapped names between two boots on the
# same day.
#
#   this morning   /dev/nvme1n1p2 was the NixOS root
#   this evening   /dev/nvme0n1p2 is the NixOS root
#
# A script that partitioned "the second drive" by name would have destroyed
# the running system on one of those two days. /dev/disk/by-id carries the
# model and serial, which do not move.
#
# WHAT IT DOES TO THE TARGET: everything on it is destroyed. The confirmation
# is the disk's serial, typed out - not "yes", which is what people type
# without reading.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sgentoo:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

DISK=""
DRY=0
SWAP_GIB=16
ESP_GIB=1
MNT=/mnt/gentoo
STAGE_FLAVOUR="desktop-systemd"
MIRROR="https://distfiles.gentoo.org"

while (( $# )); do
    case "$1" in
        --disk)     DISK="${2:?--disk needs a path}"; shift 2 ;;
        --dry-run)  DRY=1; shift ;;
        --no-swap)  SWAP_GIB=0; shift ;;
        --swap)     SWAP_GIB="${2:?--swap needs GiB}"; shift 2 ;;
        --mnt)      MNT="${2:?--mnt needs a path}"; shift 2 ;;
        -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

run() { if (( DRY )); then printf '%swould run:%s %s\n' "$dim" "$reset" "$*"; else "$@"; fi; }

(( EUID == 0 )) || die "must run as root - try: sudo $0 --disk ... "
[[ -n $DISK ]] || die "which disk? give a /dev/disk/by-id path (ls /dev/disk/by-id/)"

# --- the target, and every reason it might be the wrong one ---------------

[[ $DISK == /dev/disk/by-id/* ]] \
    || die "name the disk by id, not as $DISK - see the comment at the top of this script"
[[ -e $DISK ]] || die "$DISK does not exist"

target="$(readlink -f "$DISK")"
[[ -b $target ]] || die "$DISK does not resolve to a block device"

# The disk the running system is on, resolved the same way. Comparing whole
# devices rather than partitions, because "not the root partition" is not the
# same as "not the root disk".
running_root="$(findmnt -no SOURCE / | sed 's/[0-9]*$//; s/p$//')"
running_home="$(findmnt -no SOURCE /home 2>/dev/null | sed 's/[0-9]*$//; s/p$//' || true)"
for d in "$running_root" "$running_home"; do
    [[ -n $d ]] || continue
    [[ "$(readlink -f "$d")" == "$target" ]] \
        && die "$DISK is the disk this system is running from - refusing"
done

mounted="$(lsblk -nro MOUNTPOINT "$target" | grep -c . || true)"
(( mounted == 0 )) || {
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$target"
    die "something on $DISK is mounted - unmount it first"
}

model="$(lsblk -dno MODEL "$target" | sed 's/ *$//')"
serial="$(lsblk -dno SERIAL "$target")"
size="$(lsblk -dno SIZE "$target")"

printf '\n%sAbout to ERASE this disk completely%s\n\n' "$bold" "$reset"
printf '   %-10s %s\n' "by-id" "$DISK"
printf '   %-10s %s\n' "device" "$target  (which may be a different name after a reboot)"
printf '   %-10s %s\n' "model" "$model"
printf '   %-10s %s\n' "serial" "$serial"
printf '   %-10s %s\n' "size" "$size"
printf '\n   %scurrent contents, all of which will be gone:%s\n' "$dim" "$reset"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$target" | sed 's/^/     /'

printf '\n   %sthe system you are running stays on:%s %s\n' "$dim" "$reset" "$(readlink -f "$running_root")"

if (( ! DRY )); then
    printf '\nType the disk SERIAL to confirm (%s): ' "$serial"
    read -r typed
    [[ $typed == "$serial" ]] || die "that is not the serial - nothing has been touched"
fi

# --- partitions -----------------------------------------------------------
#
# GPT, three partitions, and the ESP is its own rather than shared with NixOS:
# the two systems then know nothing about each other, a broken Gentoo cannot
# make NixOS unbootable, and a NixOS rebuild cannot overwrite Gentoo's boot
# entry. The firmware's own boot menu chooses between the disks.

note "wiping signatures"
run wipefs -a "$target"

note "writing a new GPT"
layout="label: gpt
size=${ESP_GIB}GiB, type=uefi, name=GENTOOESP"
(( SWAP_GIB > 0 )) && layout+="
size=${SWAP_GIB}GiB, type=swap, name=GENTOOSWAP"
layout+="
type=linux, name=GENTOOROOT"

if (( DRY )); then
    printf '%swould write this layout to %s:%s\n%s\n' "$dim" "$target" "$reset" "$layout"
else
    printf '%s\n' "$layout" | sfdisk --wipe always --wipe-partitions always "$target"
    udevadm settle 2>/dev/null || sleep 2
fi

esp="${DISK}-part1"
if (( SWAP_GIB > 0 )); then swap="${DISK}-part2"; root="${DISK}-part3"
else swap=""; root="${DISK}-part2"; fi

note "making filesystems"
run mkfs.vfat -F32 -n GENTOOESP "$esp"
[[ -n $swap ]] && { run mkswap -L GENTOOSWAP "$swap"; run swapon "$swap"; }
run mkfs.ext4 -q -L GENTOOROOT "$root"

note "mounting at $MNT"
run mkdir -p "$MNT"
run mount "$root" "$MNT"
run mkdir -p "$MNT/efi"
run mount "$esp" "$MNT/efi"

# --- stage3 ---------------------------------------------------------------

note "finding the current $STAGE_FLAVOUR stage3"
# amd64 APPEARS TWICE in that path and both are load-bearing: the directory
# is the architecture and so is the filename. Without the second one the URL
# is a 404, which the dry run printed happily because a dry run fetches
# nothing - the first thing a real run would have done is fail.
latest_url="$MIRROR/releases/amd64/autobuilds/latest-stage3-amd64-$STAGE_FLAVOUR.txt"
if (( DRY )); then
    printf '%swould fetch:%s %s\n' "$dim" "$reset" "$latest_url"
    stage_rel="<current>/stage3-amd64-$STAGE_FLAVOUR-<stamp>.tar.xz"
else
    # THE INDEX IS PGP-SIGNED, so it opens with armour rather than with data:
    #
    #   -----BEGIN PGP SIGNED MESSAGE-----
    #   Hash: SHA256
    #
    #   # Latest as of Tue, 29 Sep 2026 12:00:00 +0000
    #   20260913T163055Z/stage3-amd64-desktop-systemd-....tar.xz 753542880
    #   -----BEGIN PGP SIGNATURE-----
    #
    # "the first line that is not a comment" is therefore the armour header,
    # not the tarball. Match the line that actually names a tarball.
    stage_rel="$(curl -fsSL "$latest_url" \
        | awk '/^[0-9]+T[0-9]+Z\/stage3-.*\.tar\.xz/ { print $1; exit }')"
    [[ -n $stage_rel ]] || die "could not find a stage3 in $latest_url"
fi
stage_url="$MIRROR/releases/amd64/autobuilds/$stage_rel"
note "stage3: ${stage_rel##*/}"

if (( ! DRY )); then
    cd "$MNT"
    curl -fL --progress-bar -o stage3.tar.xz "$stage_url"

    # VERIFIED BEFORE IT IS UNPACKED. The DIGESTS file sits beside the tarball
    # on the same server, so this proves the download arrived intact rather
    # than proving who made it - a gpg check against Gentoo's release key is
    # the stronger statement and needs a keyring this machine does not have.
    # Stated plainly rather than skipped silently.
    curl -fsSL -o stage3.DIGESTS "$stage_url.DIGESTS" || warn "no DIGESTS file - skipping the checksum"
    if [[ -s stage3.DIGESTS ]]; then
        # MATCHED ON THE FILENAME, not "the first SHA512 in the file": the
        # DIGESTS lists several artefacts - the tarball, its CONTENTS
        # listing - each with its own hashes, and taking the first one
        # happens to be right today and would be wrong the day the order
        # changes.
        want="$(awk -v f="${stage_rel##*/}" '
            /^# SHA512/ { want_sha = 1; next }
            want_sha && $2 == f { print $1; exit }
            { want_sha = 0 }' stage3.DIGESTS)"
        got="$(sha512sum stage3.tar.xz | awk '{print $1}')"
        [[ $want == "$got" ]] || die "stage3 checksum mismatch - refusing to unpack"
        note "checksum matches"
    fi

    note "unpacking"
    # --xattrs and --numeric-owner, which the handbook insists on: capabilities
    # on files like ping are xattrs, and the names in the tarball mean nothing
    # on this machine's passwd.
    tar xpf stage3.tar.xz --xattrs-include='*.*' --numeric-owner
    rm -f stage3.tar.xz stage3.DIGESTS
fi

note "stage one finished"
printf '\n  %sthe disk is partitioned and a stage3 is unpacked at %s%s\n' "$dim" "$MNT" "$reset"
printf '  %snext: install/gentoo_chroot.sh, which configures and enters it%s\n\n' "$dim" "$reset"
