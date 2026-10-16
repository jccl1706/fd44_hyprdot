#!/usr/bin/env bash
# =========================================================================
# gentoo-partition.sh - lay out a disk for Gentoo, from a running system
# =========================================================================
#
# Usage:  bin/gentoo-partition.sh plan   <serial>          show what it would do
#         bin/gentoo-partition.sh wipe   <serial>          partition and format
#         bin/gentoo-partition.sh mount  <serial> [root]   mount for the chroot
#         bin/gentoo-partition.sh umount [root]            unmount, innermost first
#
# Run as root on the machine the disk is in. `wipe` destroys everything on it.
#
# IT TAKES A SERIAL, NOT A DEVICE PATH, AND THAT IS THE ENTIRE POINT. The two
# NVMe drives in the machine this was written for swap names between boots -
# the Samsung to be erased was nvme1n1 one day and nvme0n1 the next, with the
# running Fedora taking the other name. A script that took /dev/nvme0n1 would
# have destroyed a working system. Serials are printed on the drive and do not
# move.
#
# IT ALSO REFUSES A DISK THAT IS MOUNTED, or that holds the running root, which
# is the second line of defence if someone passes the wrong serial.
#
# THE LAYOUT
#   p1   1 GiB  vfat   ESP      - reused as-is if one is already there
#   p2   rest   btrfs  GENTOO   - subvolumes @root @home @snapshots
#
# btrfs with zstd:1 and noatime. PORTAGE_TMPDIR belongs on tmpfs, not here:
# copy-on-write is a poor fit for a build tree and the machine has the RAM.

set -euo pipefail

name="${0##*/}"
die()  { printf '%s: %s\n' "$name" "$*" >&2; exit 1; }
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

ESP_LABEL=GENTOOESP
FS_LABEL=GENTOO
SUBVOLS=(@root @home @snapshots)

[[ $EUID -eq 0 ]] || die "run as root"
for t in lsblk sgdisk mkfs.vfat mkfs.btrfs btrfs findmnt blockdev; do
    command -v "$t" >/dev/null || die "missing: $t"
done

# --- find the disk, the only way that is safe -----------------------------
find_disk() {
    local want="$1" n s
    local -a hits=()
    [[ -n $want ]] || return 1
    while read -r n s; do
        [[ "$s" == "$want" ]] && hits+=("/dev/$n")
    done < <(lsblk -dno NAME,SERIAL 2>/dev/null)
    (( ${#hits[@]} == 1 )) || return 1
    printf '%s\n' "${hits[0]}"
}

require_disk() {
    local serial="$1" disk root_disk
    disk="$(find_disk "$serial")" \
        || die "no single disk with serial $serial (attached? ambiguous?)"

    # REFUSE THE DISK THE RUNNING SYSTEM IS ON, whatever the serial says.
    #
    # `lsblk -no PKNAME` only climbs ONE level, which is enough when / is a
    # partition and useless when it is not: on a LUKS-over-LVM root it returns
    # the logical volume's parent, never the disk underneath. `lsblk -s` walks
    # the whole dependency chain, and its last line is the physical device.
    local src; src="$(findmnt -no SOURCE / | sed 's/\[.*//')"
    # STRIP THE TREE DRAWING, which is box-drawing UTF-8 and not ASCII dashes:
    # `tr -d '-'` leaves "\u2514\u2500nvme0n1" intact, the comparison never
    # matches, and a guard that never matches never refuses.
    root_disk="$(lsblk -nso NAME "$src" 2>/dev/null | tail -1 | sed 's/^[^a-zA-Z0-9]*//')"
    [[ -n $root_disk && "/dev/$root_disk" != "$disk" ]] \
        || die "$disk carries the RUNNING ROOT - refusing"

    if lsblk -nro MOUNTPOINT "$disk" | grep -q .; then
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$disk" >&2
        die "$disk has mounted partitions - unmount them first"
    fi
    printf '%s\n' "$disk"
}

partname() { # disk, number -> /dev/nvme0n1p2 or /dev/sda2
    local d="$1" n="$2"
    [[ $d == *[0-9] ]] && printf '%sp%s\n' "$d" "$n" || printf '%s%s\n' "$d" "$n"
}

show() {
    local disk="$1"
    printf '  %s  %s\n' "$disk" "$(lsblk -dno MODEL,SIZE,SERIAL "$disk" | tr -s ' ')"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$disk" | sed 's/^/    /'
}

cmd_plan() {
    local disk; disk="$(require_disk "$1")"
    say "target"
    show "$disk"
    printf '\n'
    say "what wipe would do"
    cat <<EOF
    1. destroy the existing partition table
    2. p1  1 GiB   vfat   label $ESP_LABEL   (the ESP)
    3. p2  rest    btrfs  label $FS_LABEL
    4. subvolumes: ${SUBVOLS[*]}
    5. nothing is mounted and nothing else on this machine is touched
EOF
    printf '\n  Everything currently on %s is lost.\n' "$disk"
}

cmd_wipe() {
    local disk typed; disk="$(require_disk "$1")"
    warn "This ERASES $disk completely."
    show "$disk"
    printf '\n  Type the serial to confirm: '
    read -r typed
    [[ "$typed" == "$1" ]] || die "that is not the serial - nothing was written"

    say "new GPT"
    sgdisk --zap-all "$disk" >/dev/null
    sgdisk -n1:0:+1G  -t1:ef00 -c1:"$ESP_LABEL" \
           -n2:0:0    -t2:8300 -c2:"$FS_LABEL"  "$disk" >/dev/null
    partprobe "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || sleep 2

    local esp root
    esp="$(partname "$disk" 1)"; root="$(partname "$disk" 2)"

    say "formatting $esp as vfat"
    mkfs.vfat -F32 -n "$ESP_LABEL" "$esp" >/dev/null

    say "formatting $root as btrfs"
    mkfs.btrfs -f -L "$FS_LABEL" "$root" >/dev/null

    say "creating subvolumes"
    local tmp; tmp="$(mktemp -d)"
    mount "$root" "$tmp"
    local v; for v in "${SUBVOLS[@]}"; do
        btrfs subvolume create "$tmp/$v" >/dev/null
        printf '    %s\n' "$v"
    done
    umount "$tmp"; rmdir "$tmp"

    say "done"
    show "$disk"
    printf '\n  Next:  %s mount %s\n' "$name" "$1"
}

cmd_mount() {
    local serial="$1" target="${2:-/mnt/gentoo}" disk esp root
    disk="$(require_disk "$serial")"
    esp="$(partname "$disk" 1)"; root="$(partname "$disk" 2)"
    [[ -b $root ]] || die "$root does not exist - run wipe first"

    # MOUNT WHAT THIS SCRIPT MADE, OR NOTHING. Running `mount` before `wipe`
    # is an easy slip, and the only thing that caught it the first time was
    # ext4 refusing a btrfs mount option. Had the old filesystem happened to be
    # btrfs, the install would have proceeded on top of it - so check the type
    # and the label rather than relying on an accident.
    local have_fs have_label
    have_fs="$(lsblk -dno FSTYPE "$root" 2>/dev/null)"
    have_label="$(lsblk -dno LABEL "$root" 2>/dev/null)"
    [[ $have_fs == btrfs ]] \
        || die "$root is $have_fs, not btrfs - run '$name wipe $serial' first"
    [[ $have_label == "$FS_LABEL" ]] \
        || die "$root is labelled '$have_label', not $FS_LABEL - this is not the filesystem this script made"

    local have_esp
    have_esp="$(lsblk -dno FSTYPE "$esp" 2>/dev/null)"
    [[ $have_esp == vfat ]] || die "$esp is $have_esp, not vfat"

    local opts="noatime,compress=zstd:1"
    mkdir -p "$target"
    say "mounting $root on $target"
    mount -o "$opts,subvol=@root" "$root" "$target"
    mkdir -p "$target/home" "$target/.snapshots" "$target/boot"
    mount -o "$opts,subvol=@home"      "$root" "$target/home"
    mount -o "$opts,subvol=@snapshots" "$root" "$target/.snapshots"
    mount "$esp" "$target/boot"

    say "mounted"
    findmnt -R "$target" -o TARGET,SOURCE,FSTYPE | sed 's/^/  /'
    printf '\n  The ESP is at %s/boot - grub-install --efi-directory must point THERE,\n' "$target"
    printf '  never at this system'"'"'s own /boot.\n'
}

cmd_umount() {
    local target="${1:-/mnt/gentoo}"
    findmnt -R "$target" >/dev/null 2>&1 || { say "nothing mounted at $target"; return 0; }
    say "unmounting $target, innermost first"
    local m
    while read -r m; do
        umount "$m" && printf '    %s\n' "$m"
    done < <(findmnt -Rno TARGET "$target" | tac)
    say "done"
}

case "${1:-}" in
    plan)   [[ $# -eq 2 ]] || die "usage: $name plan <serial>";  cmd_plan "$2" ;;
    wipe)   [[ $# -eq 2 ]] || die "usage: $name wipe <serial>";  cmd_wipe "$2" ;;
    mount)  [[ $# -ge 2 ]] || die "usage: $name mount <serial> [root]"; cmd_mount "$2" "${3:-}" ;;
    umount) cmd_umount "${2:-}" ;;
    *) die "usage: $name [plan|wipe|mount|umount] - see the header" ;;
esac
