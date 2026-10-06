#!/usr/bin/env bash
# =========================================================================
# install_fedora_desktop.sh - Fedora onto a second disk, from a running Linux
# =========================================================================
#
# Usage:  sudo install/install_fedora_desktop.sh --disk <by-id path> [--go]
#
# Stage one of four, plus two opt-in stages. Partition, format, and bootstrap
# a Fedora @core into a
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

# --- every tool, checked BEFORE anything is touched --------------------------
#
# THIS CHECK EXISTS BECAUSE IT WAS MISSING ONCE. The first real run wiped the
# partition table and then died on `sgdisk: command not found`, leaving the disk
# with no table and no new one - survivable only because that disk was being
# destroyed anyway. A destructive script must establish it can finish before it
# starts.
#
# NixOS is the reason, and it is not a NixOS fault: it installs nothing it was
# not asked for, so gptfdisk and parted are simply absent unless named.
# packages.nix in fd44_nixos carries neither. The hint names the nixpkgs attrs
# rather than the binaries, because that is what has to be installed.
missing=""
need() { command -v "$1" >/dev/null 2>&1 || missing+="    $1  (nixpkgs: $2)"$'\n'; }
need wipefs    util-linux
need sgdisk    gptfdisk
need partprobe parted
need udevadm   systemd
need mkfs.vfat  dosfstools
need mkfs.btrfs btrfs-progs
need btrfs      btrfs-progs
need lsblk     util-linux
need findmnt   util-linux
if [[ -n $missing ]]; then
    warn "missing tools, and this script will not start without them:"
    printf '%s' "$missing" >&2
    die "on NixOS:  nix-shell -p gptfdisk parted dosfstools --run 'sudo $0 ...'"
fi

# --- the target, and the thing it must not be --------------------------------
#
# THREE SEPARATE CHECKS, because this is the step with no undo. A by-id path
# that is not a disk, a disk that is not whole, and above all a disk the
# RUNNING SYSTEM lives on.
[[ $DISK == /dev/disk/by-id/* ]] || die "name the disk by /dev/disk/by-id/... , not $DISK"
[[ -b $DISK ]] || die "$DISK is not a block device"

TARGET="$(readlink -f "$DISK")"
[[ -b $TARGET ]] || die "$DISK does not resolve to a block device"

# ANY mounted filesystem on the target disk, by kernel name, read from /proc
# now - not from fstab, not from a guess.
#
# AND IT NAMES THE MOUNTPOINT, because the refusal is otherwise unactionable.
# Two quite different things land here: the running system's own root, which
# means you have picked the wrong disk and must stop; and a read-only
# inspection mount of the disk you really do mean to wipe, which just needs
# unmounting. Both must refuse - but you need to know which one you are
# looking at. Found immediately: /mnt/g, a read-only look at the old Gentoo
# root, was still mounted when this was first run.
busy=""
while read -r src tgt; do
    [[ -n $src ]] || continue
    parent="$(lsblk -nso PKNAME "${src%%[*}" 2>/dev/null | tail -1)"
    [[ -n $parent && "/dev/$parent" == "$TARGET" ]] && busy+="    $tgt  <- $src"$'\n'
done < <(findmnt -no SOURCE,TARGET --real 2>/dev/null)

if [[ -n $busy ]]; then
    warn "$TARGET has mounted filesystems:"
    printf '%s' "$busy" >&2

    # TELLING SOMEONE TO UNMOUNT / IS NOT ADVICE. The first version of this
    # ended with "unmount them first, or you have picked the wrong disk", which
    # is sound for a stray inspection mount and dangerous nonsense for the
    # running root. The two cases get different endings, because the right next
    # move is opposite in each.
    if [[ $busy == *" / "* || $busy == *$'\n    /  <-'* || $busy == "    /  <-"* ]]; then
        die "that is the RUNNING SYSTEM's root. You have picked the wrong disk - stop."
    fi
    die "unmount those first if this really is the disk you mean to destroy."
fi

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
    ${TARGET}p1   ${ESP_GIB} GiB   vfat   FEDESP    -> /boot       (its own ESP)
    ${TARGET}p2   rest          btrfs  FEDROOT   -> subvol=root at /, subvol=home at /home
    no swap partition - zram, as Fedora defaults to
    no LUKS       - as asked, and matching the NixOS disk beside it
PLAN
printf '\n'

if (( ! GO )); then
    warn "DRY RUN. Nothing has been changed. Re-run with --go to do it."
    exit 0
fi

# --- confirmation ------------------------------------------------------------
# THE SERIAL, NOT THE MODEL, AND THE PROMPT HAS TO SAY SO. The target block
# above prints both, they are both opaque strings of letters and digits, and
# the first real run typed the model - which is the ONE string that does not
# identify a single disk, since two drives of the same part number share it.
# That is exactly why the serial is the confirmation. The prompt now names the
# field and says which is wrong, and a mistyped answer says what it got.
warn "EVERYTHING ON $TARGET ($MODEL) WILL BE DESTROYED."
printf '  To confirm, type its SERIAL - the %sserial%s line above, not the model.\n' "$bold" "$reset"
printf '  serial> '
read -r typed
if [[ $typed != "$SERIAL" ]]; then
    [[ $typed == "$MODEL" ]] && warn "that is the model. Two disks can share a model; the serial is what picks one."
    die "'$typed' is not the serial of $TARGET. Nothing was changed."
fi

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
run mkfs.vfat -F32 -n FEDESP "${TARGET}p1"
# BTRFS, AND THE SUBVOLUMES ARE THE REASON. ext4 worked and gave up nothing
# except the one thing this machine now wants: a system that can be rolled back
# to what it was before an update. btrfs-patrol, which this repository also
# carries, expects exactly Fedora's installer layout - a 'root' subvolume and a
# 'home' subvolume on one filesystem - and gets it here without configuration.
run mkfs.btrfs -f -L FEDROOT "${TARGET}p2"

# THE TOP LEVEL IS MOUNTED ONCE, TO MAKE THE SUBVOLUMES, AND THEN LET GO. What
# gets mounted at / afterwards is subvol=root, never subvolid=5 - a system
# installed onto the top level cannot be rolled back, because the thing you
# would replace is the thing everything else lives inside.
note "creating the subvolumes"
run mkdir -p "$MNT"
run mount "${TARGET}p2" "$MNT"
run btrfs subvolume create "$MNT/root"
run btrfs subvolume create "$MNT/home"
run umount "$MNT"

# NO 'snapshots' SUBVOLUME HERE, DELIBERATELY. `btrfs-patrol setup` creates it,
# mounts it at /.snapshots, writes the fstab line, sets it 0700 and adds the
# SELinux exclusion - five things that have to agree. Doing half of them here
# would mean maintaining the other half in two places.

# COMPRESSION ON FROM THE FIRST FILE. Setting compress on an existing
# filesystem only affects what is written afterwards, so it belongs here rather
# than in a later tidy-up: everything dnf unpacks in stage two is compressed.
note "mounting at $MNT"
run mount -o subvol=root,compress=zstd:1,noatime "${TARGET}p2" "$MNT"
run mkdir -p "$MNT/home"
run mount -o subvol=home,compress=zstd:1,noatime "${TARGET}p2" "$MNT/home"
# /boot, NOT /boot/efi. Fedora's kernel-install writes Boot Loader Specification
# entries to /boot/loader/entries and systemd-boot reads them only from the ESP,
# so the two are one filesystem here - which is what the fstab stage three writes
# says, and where stage two expects to find it. Mounting it at /boot/efi as well
# left the ESP mounted twice and an empty /boot/efi in the installed system.
run mkdir -p "$MNT/boot"
run mount "${TARGET}p1" "$MNT/boot"

printf '\n'
note "done - partitioned, formatted and mounted"
lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$TARGET" | sed 's/^/  /'
printf '\n'
note "next: stage two bootstraps @core into $MNT"
