#!/usr/bin/env bash
# =========================================================================
# gentoo_enter.sh - mount the Gentoo install and work inside it, from NixOS
# =========================================================================
#
# Usage:  sudo install/gentoo_enter.sh                 a shell in the chroot
#         sudo install/gentoo_enter.sh -- <command>    run one thing and leave
#         sudo install/gentoo_enter.sh --umount        put it all back
#
# The two systems share a machine, so whichever is running can repair the
# other. This is the way in from the NixOS side: mount Gentoo's root and ESP
# by LABEL, bind the kernel filesystems, chroot.
#
# BY LABEL, not by /dev/nvmeXn1: the two NVMe drives on this machine swap
# kernel names between boots, and GENTOOROOT is the same partition whatever
# the kernel decided to call it this morning.
#
# IT UNDOES ITSELF. Leaving /mnt/gentoo mounted after a repair means the next
# NixOS boot has a foreign root bind-mounted under it, and `umount -R` on the
# way out costs nothing.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
die()  { printf '%sgentoo:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

MNT=/mnt/gentoo
ROOT_LABEL=GENTOOROOT
ESP_LABEL=GENTOOESP
UMOUNT_ONLY=0
CMD=()

while (( $# )); do
    case "$1" in
        --umount) UMOUNT_ONLY=1; shift ;;
        --mnt)    MNT="${2:?}"; shift 2 ;;
        --)       shift; CMD=("$@"); break ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

(( EUID == 0 )) || die "must run as root"

unmount_all() {
    # Deepest first, and -R so the rbind mounts under /dev and /sys go too.
    mountpoint -q "$MNT" || { note "nothing mounted at $MNT"; return 0; }
    note "unmounting $MNT"
    umount -R "$MNT"
}

if (( UMOUNT_ONLY )); then unmount_all; exit 0; fi

root_dev="/dev/disk/by-label/$ROOT_LABEL"
esp_dev="/dev/disk/by-label/$ESP_LABEL"
[[ -e $root_dev ]] || die "no partition labelled $ROOT_LABEL - is the Gentoo disk attached?"
[[ -e $esp_dev ]]  || die "no partition labelled $ESP_LABEL"

note "$ROOT_LABEL is $(readlink -f "$root_dev"), $ESP_LABEL is $(readlink -f "$esp_dev")"

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$root_dev" "$MNT"
mkdir -p "$MNT/efi"
mountpoint -q "$MNT/efi" || mount "$esp_dev" "$MNT/efi"
mountpoint -q "$MNT/proc" || mount --types proc /proc "$MNT/proc"
for d in sys dev run; do
    mountpoint -q "$MNT/$d" || { mount --rbind "/$d" "$MNT/$d"; mount --make-rslave "$MNT/$d"; }
done
# So emerge and curl work in there.
cp --dereference /etc/resolv.conf "$MNT/etc/resolv.conf"

if (( ${#CMD[@]} )); then
    note "running: ${CMD[*]}"
    # set +e around it: a failing command inside should still unmount.
    set +e
    chroot "$MNT" /bin/bash -lc "export SYSTEMD_IGNORE_CHROOT=1; ${CMD[*]}"
    status=$?
    set -e
    unmount_all
    exit "$status"
fi

note "entering the chroot - exit when done and it unmounts itself"
set +e
chroot "$MNT" /bin/bash -l
set -e
unmount_all
