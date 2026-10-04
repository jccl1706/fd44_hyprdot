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

# REMOUNT THE ESP WITH umask=0077 to match the fstab written below. bootctl
# writes a random seed there and refuses to be quiet about a world-readable
# one - correctly, since that seed feeds the kernel's entropy pool at boot.
# Stage two mounted it with vfat defaults, which are world-readable.
mount -o remount,umask=0077,shortname=winnt "$MNT/boot" 2>/dev/null || true

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

# --- running things inside -----------------------------------------------------
#
# PATH HAS TO BE SET, and forgetting it fails in a way that reads as a missing
# package. `chroot` passes the caller's environment straight through, so inside
# the chroot PATH still points at /run/current-system/sw/bin and the rest of
# NixOS - none of which exists there. The first run died on
#
#   chroot: failed to run command 'bootctl': No such file or directory
#
# with /mnt/fedora/usr/bin/bootctl sitting right there. The groupadd and useradd
# calls above happened to work only because they were written as absolute paths.
#
# env -i rather than appending: the host's LD_LIBRARY_PATH, LOCALE_ARCHIVE and
# the rest of NixOS's environment have no meaning inside and some of it actively
# misleads glibc.
inch() {
    chroot "$MNT" /usr/bin/env -i \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        HOME=/root TERM="${TERM:-linux}" \
        "$@"
}

# --- the chroot needs a kernel's view of the world ---------------------------
# --rbind THEN --make-rslave, AND THE SECOND HALF IS NOT OPTIONAL.
#
# A plain --rbind inherits SHARED propagation, so a later `umount -R` on the
# copy travels back along the peer group and unmounts the ORIGINALS. The first
# run of this script did exactly that to the machine it was running on:
#
#   /sys/firmware/efi/efivars  gone  (efibootmgr: "EFI variables are not
#                                     supported on this system")
#   /sys/fs/bpf, /sys/kernel/debug, /sys/kernel/tracing, /sys/fs/pstore  gone
#
# The host survived, but a script that quietly dismantles the running system's
# /sys while installing another one is not acceptable. --make-rslave keeps
# mounts propagating INTO the chroot and nothing propagating back out.
note "binding /dev /proc /sys /run"
for d in dev dev/pts proc sys run; do
    mkdir -p "$MNT/$d"
    findmnt -n "$MNT/$d" >/dev/null 2>&1 || mount --rbind "/$d" "$MNT/$d"
    # UNCONDITIONALLY, not only for mounts this run created. A bind left behind
    # by an earlier, failed run is SHARED, and skipping it because it is already
    # mounted leaves exactly the propagation this fix exists to prevent. That is
    # what happened: the run that first carried --make-rslave still unmounted
    # /run/wrappers from the host, because the bind was inherited from the
    # previous attempt and never re-slaved. /run/wrappers holds NixOS's setuid
    # wrappers, including the unix_chkpwd that pam_unix executes, so every ssh
    # login after that point failed with
    #
    #   fatal: Access denied for user jc by PAM account configuration
    #
    # on a machine whose account database was perfectly fine.
    mount --make-rslave "$MNT/$d"
done
cleanup() {
    note "unbinding"
    # Reverse order, and lazy: anything still open inside the chroot detaches
    # rather than wedging the unmount. With --make-rslave above, none of this
    # reaches the host's own mounts.
    for d in run sys proc dev/pts dev; do
        mountpoint -q "$MNT/$d" && umount -R -l "$MNT/$d" 2>/dev/null || true
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
# A REAL machine-id, GENERATED HERE - not copied, and not left empty.
#
# Copying the host's would give two machines one identity, which breaks
# journald, DHCP leases keyed on it, and systemd-boot's entry tokens.
#
# But leaving it EMPTY, which was the first attempt, breaks kernel-install:
# Fedora's rescue hook builds a path from the machine-id and got
#
#   /usr/lib/kernel/install.d/51-dracut-rescue.install: line 91:
#   /boot/fedora/0-rescue/loader/entries/<id>-0-rescue.conf: No such file
#   or directory
#
# "systemd makes one on first boot" is true for a golden image that is never
# booted here; this disk is a one-off install, and generating it now is what
# Anaconda does too.
inch systemd-machine-id-setup

# --- the user ----------------------------------------------------------------
note "creating $USERNAME"
inch groupadd -g "$USERUID" "$USERNAME" 2>/dev/null || true
inch useradd -u "$USERUID" -g "$USERUID" -G wheel \
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
# NO RESCUE KERNEL, which is a size decision and also removes the hook that
# failed above. The rescue image is a ~100 MiB host-only initramfs built once
# and never updated; on a machine that dual-boots a working NixOS beside it,
# the rescue system IS the other disk. Delete this file to get it back.
note "turning off the rescue image"
mkdir -p "$MNT/etc/kernel"
printf 'dracut_rescue_image=no\n' > "$MNT/etc/kernel/install.conf"
rm -rf "$MNT/boot/fedora/0-rescue"

# --no-variables, AND THAT IS THE WHOLE POINT OF THIS COMMENT.
#
# Without it, bootctl writes a firmware boot entry AND PUTS ITSELF FIRST. Run
# against a tree that has no kernel yet - which is exactly what this script is
# doing at this moment - the next boot hands control to a systemd-boot with an
# empty loader/entries, and the machine reaches no operating system at all.
# That happened: the install left BootOrder as 0002,0001,... with 0002 being
# this half-finished Fedora, and the box had to be rescued through the
# firmware's boot menu.
#
# The loader is still installed to the ESP; only NVRAM is left alone. The entry
# gets added deliberately in stage four, after there is something to boot, and
# the order is set explicitly then.
note "installing systemd-boot to the ESP (not touching firmware variables)"
inch bootctl install --esp-path=/boot --no-variables

note "placing the kernel and building its initramfs"
inch kernel-install add "$KVER" "/usr/lib/modules/$KVER/vmlinuz"

note "what landed on the ESP"
ls "$MNT/boot" | sed 's/^/  /'
ls "$MNT/boot/loader/entries" 2>/dev/null | sed 's/^/  entry: /' || warn "no loader entries - the kernel did not register"

# --- services and SELinux ----------------------------------------------------
note "enabling NetworkManager and sshd"
inch systemctl enable NetworkManager sshd

note "scheduling the SELinux relabel for first boot"
: > "$MNT/.autorelabel"

printf '\n'
note "set a root password (you will need it if the network does not come up)"
inch passwd root
note "and a password for $USERNAME"
inch passwd "$USERNAME"

printf '\n'
note "done - this should now boot"
warn "the FIRST boot relabels SELinux and reboots itself once. That is expected."
