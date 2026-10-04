#!/usr/bin/env bash
# =========================================================================
# fedora_chroot.sh - make the bootstrapped Fedora actually bootable
# =========================================================================
#
# Usage:  sudo install/fedora_chroot.sh --disk <by-id path> [--go]
#
# Stage three of four. Stage two filled the root with packages; this writes the
# configuration a system needs to start, installs systemd-boot, and places the
# kernel. Stage four adds KDE and NVIDIA, after this one has been proved by
# actually booting it.
#
# WHY THE KERNEL IS NOT ALREADY IN /boot. kernel-core's %posttrans runs
# kernel-install, which asks the kernel which block device backs the filesystem
# and gets nowhere inside an installroot:
#
#   Failed to get block device path for 259:5: No such device
#
# So the kernel package landed its vmlinuz in /usr/lib/modules/<ver>/ and
# stopped. Running kernel-install here, in a chroot with /dev, /proc and /sys
# bound, is what builds the initramfs and writes the Boot Loader Specification
# entry. This is normal for every installroot bootstrap, not a fault.
#
# ORDER MATTERS AND IS NOT OBVIOUS: fstab before kernel-install, because dracut
# reads it to decide what the root filesystem is; bootctl before
# kernel-install, so there is a loader directory for the entry to land in.
#
# SELINUX. Packages installed through an installroot carry no labels - nothing
# relabelled them, because the policy was not loaded. /.autorelabel makes the
# first boot do it, which takes a few minutes and one extra reboot. Leaving it
# out gives a system that boots to a cascade of permission denials.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfedora:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

DISK=""; GO=0; MNT=/mnt/fedora
HOSTNAME_=fedora-gaming00
TIMEZONE=America/New_York
USERNAME=jc
USERUID=1000

while (( $# )); do
    case "$1" in
        --disk) DISK="${2-}"; shift 2 ;;
        --go) GO=1; shift ;;
        --hostname) HOSTNAME_="${2-}"; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

(( EUID == 0 )) || die "run this with sudo"
[[ -n $DISK && $DISK == /dev/disk/by-id/* ]] || die "--disk <by-id path> required"
TARGET="$(readlink -f "$DISK")"; ESP="${TARGET}p1"; ROOT="${TARGET}p2"

[[ -d $MNT/usr/lib/modules ]] || die "$MNT does not look bootstrapped - run stage two first"
findmnt -n "$MNT"      >/dev/null || die "$MNT is not mounted"
findmnt -n "$MNT/boot" >/dev/null || die "$MNT/boot is not mounted (the ESP)"

KVER="$(ls "$MNT/usr/lib/modules" | head -1)"
[[ -n $KVER ]] || die "no kernel in $MNT/usr/lib/modules"
ROOT_UUID="$(lsblk -no UUID "$ROOT")"
ESP_UUID="$(lsblk -no UUID "$ESP")"

note "plan"
printf '  %-12s %s\n' "kernel"   "$KVER"
printf '  %-12s %s\n' "hostname" "$HOSTNAME_"
printf '  %-12s %s (uid %s, wheel)\n' "user" "$USERNAME" "$USERUID"
printf '  %-12s %s\n' "timezone" "$TIMEZONE"
printf '  %-12s root=UUID=%s\n' "fstab" "$ROOT_UUID"
printf '  %-12s /boot=UUID=%s (the ESP)\n' "" "$ESP_UUID"
printf '  bootctl install, kernel-install add, /.autorelabel\n\n'
(( GO )) || { warn "DRY RUN. Re-run with --go."; exit 0; }

# --- the chroot needs a kernel's view of the world ---------------------------
note "binding /dev /proc /sys /run"
for d in dev dev/pts proc sys run; do
    mkdir -p "$MNT/$d"
    findmnt -n "$MNT/$d" >/dev/null 2>&1 || mount --rbind "/$d" "$MNT/$d"
done
cleanup() {
    note "unbinding"
    for d in run sys proc dev/pts dev; do
        mountpoint -q "$MNT/$d" && umount -R "$MNT/$d" 2>/dev/null || true
    done
}
trap cleanup EXIT

# --- fstab, BEFORE anything reads it -----------------------------------------
#
# BY UUID, like everything else here, and for the same reason the installer
# refuses /dev/nvmeXn1: the two drives in this machine swap names between boots.
note "writing /etc/fstab"
cat > "$MNT/etc/fstab" <<FSTAB
# Written by fd44_hyprdot install/fedora_chroot.sh
#
# /boot IS THE ESP. Fedora's kernel-install writes Boot Loader Specification
# entries to /boot/loader/entries, and systemd-boot reads them only from the
# EFI System Partition - so the two are the same filesystem here. This is the
# same arrangement as the NixOS install on the other disk.
UUID=$ROOT_UUID  /      ext4  defaults,noatime  0 1
UUID=$ESP_UUID   /boot  vfat  umask=0077,shortname=winnt  0 2
FSTAB
sed 's/^/  /' "$MNT/etc/fstab"

# --- identity ----------------------------------------------------------------
note "hostname, timezone, locale, machine-id"
echo "$HOSTNAME_" > "$MNT/etc/hostname"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$MNT/etc/localtime"
echo 'LANG="en_US.UTF-8"' > "$MNT/etc/locale.conf"
# An EMPTY machine-id, not a copied one: systemd generates a fresh one on first
# boot. Copying the host's would give two machines the same identity, which
# breaks journald, DHCP leases keyed on it, and systemd-boot's entry tokens.
: > "$MNT/etc/machine-id"

# --- the user ----------------------------------------------------------------
note "creating $USERNAME"
chroot "$MNT" /usr/sbin/groupadd -g "$USERUID" "$USERNAME" 2>/dev/null || true
chroot "$MNT" /usr/sbin/useradd -u "$USERUID" -g "$USERUID" -G wheel \
    -m -s /bin/bash "$USERNAME" 2>/dev/null || true
# The same key that reaches this machine now, so the new system is reachable
# before it has a display working - which is the whole point of installing
# openssh-server in stage two.
if [[ -f /home/$USERNAME/.ssh/authorized_keys ]]; then
    install -d -m700 -o "$USERUID" -g "$USERUID" "$MNT/home/$USERNAME/.ssh"
    install -m600 -o "$USERUID" -g "$USERUID" \
        "/home/$USERNAME/.ssh/authorized_keys" "$MNT/home/$USERNAME/.ssh/authorized_keys"
    note "copied authorized_keys"
fi

# --- bootloader, then the kernel ---------------------------------------------
note "installing systemd-boot to the ESP"
chroot "$MNT" bootctl install --esp-path=/boot

note "placing the kernel and building its initramfs"
chroot "$MNT" kernel-install add "$KVER" "/usr/lib/modules/$KVER/vmlinuz"

note "what landed on the ESP"
ls "$MNT/boot" | sed 's/^/  /'
ls "$MNT/boot/loader/entries" 2>/dev/null | sed 's/^/  entry: /' || warn "no loader entries - the kernel did not register"

# --- services and SELinux ----------------------------------------------------
note "enabling NetworkManager and sshd"
chroot "$MNT" systemctl enable NetworkManager sshd

note "scheduling the SELinux relabel for first boot"
: > "$MNT/.autorelabel"

printf '\n'
note "set a root password (you will need it if the network does not come up)"
chroot "$MNT" passwd root
note "and a password for $USERNAME"
chroot "$MNT" passwd "$USERNAME"

printf '\n'
note "done - this should now boot"
warn "the FIRST boot relabels SELinux and reboots itself once. That is expected."
