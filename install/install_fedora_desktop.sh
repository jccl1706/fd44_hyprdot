#!/usr/bin/env bash
# =========================================================================
# install_fedora_desktop.sh - Fedora onto a second disk, from a running Linux
# =========================================================================
#
# Usage:  sudo install/install_fedora_desktop.sh --disk <by-id path> [--go]
#
# Stage one of two: partition, format, and bootstrap a Fedora @core into a
# chroot. Stage two - KDE, systemd-boot, NVIDIA, the user - is a separate
# script, so that a mistake in it costs a chroot rather than a disk.
#
# NO INSTALL MEDIUM, the same trick install_gentoo.sh used on this machine:
# everything here is a partition table, dnf5 with --installroot, and a chroot.
# The machine keeps running NixOS throughout, which also means the thing you
# are installing FROM cannot be the thing you are installing OVER - checked
# below rather than assumed.
#
# WHY NOT ANACONDA. Two of the three requirements are awkward there and free
# here. "No bloat" means naming every package rather than pruning a spin's
# fixed set. systemd-boot means `bootctl install`, one command, instead of
# betting on an installer option that could not be verified. The third, no
# LUKS, is free either way.
#
# THE DISK IS NAMED BY ID, NEVER BY /dev/nvmeXn1, AND ON THIS MACHINE THAT IS
# NOT PEDANTRY: the two NVMe drives swapped names between two boots on the
# same day, and did it again on 2026-10-04.
#
#   morning   /dev/nvme0n1 was the NixOS root
#   afternoon /dev/nvme1n1 is the NixOS root
#
# Both are 4 TB, so size does not disambiguate them either. /dev/disk/by-id
# carries the model and serial, which do not move.
#
# WHAT IT DOES TO THE TARGET: everything on it is destroyed. The confirmation
# is the disk's SERIAL, typed out - not "yes", which is what people type
# without reading.
#
# DRY BY DEFAULT. It prints the plan and changes nothing unless --go is given.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfedora:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }
run()  { if (( GO )); then "$@"; else printf '  %swould run:%s %s\n' "$dim" "$reset" "$*"; fi; }

DISK=""
GO=0
RELEASEVER=44
ESP_GIB=1
MNT=/mnt/fedora

while (( $# )); do
    case "$1" in
        --disk) DISK="${2-}"; shift 2 ;;
        --go)   GO=1; shift ;;
        --releasever) RELEASEVER="${2-}"; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

(( EUID == 0 )) || die "run this with sudo - it partitions a disk"
[[ -n $DISK ]]  || die "no --disk. Pick one from: ls -l /dev/disk/by-id/nvme-*"

# --- the target, and the thing it must not be --------------------------------
#
# THREE SEPARATE CHECKS, because this is the step with no undo. A by-id path
# that is not a disk, a disk that is not whole, and above all a disk the
# RUNNING SYSTEM lives on.
[[ $DISK == /dev/disk/by-id/* ]] || die "name the disk by /dev/disk/by-id/... , not $DISK"
[[ -b $DISK ]] || die "$DISK is not a block device"

TARGET="$(readlink -f "$DISK")"
[[ -b $TARGET ]] || die "$DISK does not resolve to a block device"

# The running system's disks, by kernel name, from what is actually mounted.
# Not from fstab, not from a guess: from /proc, now.
mapfile -t IN_USE < <(findmnt -no SOURCE --real 2>/dev/null \
    | sed 's/\[.*\]//' | xargs -r -n1 lsblk -nso PKNAME 2>/dev/null | sort -u)
for d in "${IN_USE[@]}"; do
    [[ -n $d ]] || continue
    [[ "/dev/$d" == "$TARGET" ]] && die "$TARGET carries a mounted filesystem of the RUNNING system. Refusing."
done

MODEL="$(lsblk -dno MODEL "$TARGET" | xargs)"
SERIAL="$(lsblk -dno SERIAL "$TARGET" | xargs)"
SIZE="$(lsblk -dno SIZE "$TARGET" | xargs)"
[[ -n $SERIAL ]] || die "could not read a serial for $TARGET - refusing to guess"

printf '\n'
note "target"
printf '  %-10s %s\n' "by-id"  "$DISK"
printf '  %-10s %s\n' "device" "$TARGET"
printf '  %-10s %s\n' "model"  "$MODEL"
printf '  %-10s %s\n' "serial" "$SERIAL"
printf '  %-10s %s\n' "size"   "$SIZE"
printf '\n  it currently holds:\n'
lsblk -no NAME,SIZE,FSTYPE,LABEL "$TARGET" | sed 's/^/    /'
printf '\n'

# --- the plan ----------------------------------------------------------------
#
# TWO PARTITIONS, NO SWAP PARTITION. Gentoo had a 16 GiB swap partition here and
# it was never the right answer on a machine with 30 GiB of RAM: Fedora enables
# zram by default, which is faster and costs no disk. Nothing hibernates on this
# machine either - see the Framework's note about hibernation being deliberately
# off - so there is no resume image to hold.
#
# A 1 GiB ESP, matching NIXESP. Fedora's own default is 600 MiB, which is tight
# once a few kernels and their initramfs land in it, and this disk has 4 TB.
#
# ITS OWN ESP, NOT THE NIXOS ONE. The two systems each own a bootloader on their
# own disk and the firmware menu picks between them. Sharing one ESP is how a
# Fedora kernel update ends up breaking NixOS's boot entries.
note "plan"
cat <<PLAN
    ${TARGET}p1   ${ESP_GIB} GiB   vfat   FEDESP    -> /boot/efi   (its own ESP)
    ${TARGET}p2   rest          ext4   FEDROOT   -> /
    no swap partition - zram, as Fedora defaults to
    no LUKS       - as asked, and matching the NixOS disk beside it
PLAN
printf '\n'

if (( ! GO )); then
    warn "DRY RUN. Nothing has been changed. Re-run with --go to do it."
    exit 0
fi

# --- confirmation ------------------------------------------------------------
warn "EVERYTHING ON $TARGET ($MODEL) WILL BE DESTROYED."
printf '  Type the disk serial to confirm: '
read -r typed
[[ $typed == "$SERIAL" ]] || die "that is not the serial. Nothing was changed."

# --- partition ---------------------------------------------------------------
note "wiping the old table"
run wipefs -a "$TARGET"
run sgdisk --zap-all "$TARGET"

note "partitioning"
run sgdisk \
    -n 1:0:+${ESP_GIB}G -t 1:ef00 -c 1:"FEDESP" \
    -n 2:0:0            -t 2:8300 -c 2:"FEDROOT" \
    "$TARGET"
run partprobe "$TARGET"
run udevadm settle

note "formatting"
run mkfs.vfat -F32 -n FEDESP  "${TARGET}p1"
run mkfs.ext4 -F  -L FEDROOT  "${TARGET}p2"

note "mounting at $MNT"
run mkdir -p "$MNT"
run mount "${TARGET}p2" "$MNT"
run mkdir -p "$MNT/boot/efi"
run mount "${TARGET}p1" "$MNT/boot/efi"

printf '\n'
note "done - partitioned, formatted and mounted"
lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$TARGET" | sed 's/^/  /'
printf '\n'
note "next: stage two bootstraps @core into $MNT"
