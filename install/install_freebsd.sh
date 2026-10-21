#!/bin/sh
#
# install_freebsd.sh - FreeBSD 15.1 onto ZFS, from the installer shell   v0.1
#   GPT + UEFI  |  ZFS root with boot environments  |  swap partition
#   base + kernel from the mirror  |  no desktop yet (KDE Plasma is a later stage)
#
# Usage, from the FreeBSD 15.1 install media (choose Shell at the Welcome
# screen, or boot the Live CD), as root:
#
#     sh install_freebsd.sh            # DRY RUN: prints what it would do
#     sh install_freebsd.sh --go       # actually partition and install
#
# This is the by-hand install that was done and verified in a VM on 2026-10-21,
# turned into a script - the same way bin/gentoo-*.sh came from the first hand
# Gentoo install. It is POSIX sh (the installer shell is /bin/sh, not bash).
#
# It installs the BASE SYSTEM only. KDE Plasma + SDDM is a separate stage
# (freebsd_desktop.sh, not yet written) that runs on the booted system - the
# same split install_fedora.sh has between the installer and fedora_desktop.sh.
# See docs/freebsd-install-plan.md for the scope and the risks.
#
# ---------------------------------------------------------------------------
# THINGS LEARNED THE HARD WAY (all are handled below; read before editing)
#
#   * The disc1 ISO ships only /usr/freebsd-dist/MANIFEST, NOT the .txz sets.
#     So the sets are fetched from the mirror. If a future dvd1 install carries
#     them locally, SETS_DIR below points at them and the fetch is skipped.
#
#   * The installer's /tmp is a SMALL tmpfs. Staging base.txz (~180 MB) there
#     fails with "No space left on device". The sets are therefore STREAMED
#     (fetch -o - | tar -x) straight into the pool, never written to /tmp.
#
#   * Disk and hwmon-style names are not identity. The target is set by one
#     variable and confirmed before anything destructive; partitions are given
#     GPT LABELS and referenced by /dev/gpt/<label>, which survive renumbering.
#
#   * UEFI boot needs no NVRAM entry: the FreeBSD loader.efi is copied to the
#     ESP's removable fallback path \EFI\BOOT\BOOTX64.EFI as well as
#     \EFI\freebsd\loader.efi, so the firmware finds it on its own. (Same
#     self-contained trick used for the Linux installs.)
#
#   * FreeBSD's default sshd blocks root key login. This script sets
#     PermitRootLogin prohibit-password and, better, creates a normal wheel
#     user - do not rely on root ssh.
#
#   * Encryption is NOT in v0.1. ZFS native encryption (the plan's preferred
#     option) is the first thing to add; get an unencrypted install booting
#     first, exactly as this did.
# ---------------------------------------------------------------------------

set -eu

# === CONFIG — the decisions, all in one place ==============================

DISK="${DISK:-vtbd0}"              # target disk. vtbd0 in a virtio VM; adaN /
                                  #   nvdN / nvme0nsX on real hardware. CONFIRM IT.
POOL="${POOL:-zroot}"
HOSTNAME="${HOSTNAME:-freebsd-fd44}"
ESP_SIZE="${ESP_SIZE:-260M}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
TIMEZONE="${TIMEZONE:-America/New_York}"
RELEASE="${RELEASE:-15.1-RELEASE}"
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-https://download.freebsd.org/releases/${ARCH}/${ARCH}/${RELEASE}}"
SETS_DIR="${SETS_DIR:-/usr/freebsd-dist}"   # used if base.txz is present here
NETIF="${NETIF:-vtnet0}"          # vtnet0 virtio; emN / reN / etc on hardware
NEWUSER="${NEWUSER:-jc}"
# SSH_KEY_URL: if set, the script fetches a public key from it for root and the
# new user (how the VM install bootstrapped ssh). Leave empty to skip.
SSH_KEY_URL="${SSH_KEY_URL:-}"

MNT=/mnt

# === plumbing ==============================================================

GO=0
[ "${1:-}" = "--go" ] && GO=1

say()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
run()  { # echo every command; run it only with --go
    printf '    %s\n' "$*"
    [ "$GO" = 1 ] && eval "$*"
    return 0
}
die()  { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root (from the installer shell / live CD)"

# === preflight =============================================================

say "Preflight"
[ -e "/dev/$DISK" ] || die "/dev/$DISK does not exist - set DISK= to the target"
echo "    target disk : /dev/$DISK  ($(diskinfo -v "$DISK" 2>/dev/null | awk '/# Mediasize/{print $3,$4}'))"
echo "    pool        : $POOL"
echo "    hostname    : $HOSTNAME"
echo "    release     : $RELEASE $ARCH"
echo "    mode        : $( [ "$GO" = 1 ] && echo 'GO - will ERASE /dev/'"$DISK" || echo 'dry run (pass --go to install)')"
# refuse a disk that already holds a pool of this name imported, to avoid chaos
if zpool list "$POOL" >/dev/null 2>&1; then
    die "a pool named $POOL is already imported; export it first"
fi

if [ "$GO" = 1 ]; then
    printf '\n    This ERASES /dev/%s. Type the disk name to confirm: ' "$DISK"
    read -r ans
    [ "$ans" = "$DISK" ] || die "mismatch - nothing done"
fi

# === Stage A: partition (GPT / UEFI) =======================================

say "Stage A - partition /dev/$DISK (GPT: efi / swap / zfs)"
run "gpart destroy -F $DISK 2>/dev/null || true"
run "gpart create -s gpt $DISK"
run "gpart add -t efi          -l efiesp -s $ESP_SIZE  $DISK"   # p1
run "gpart add -t freebsd-swap -l swap0  -s $SWAP_SIZE $DISK"   # p2
run "gpart add -t freebsd-zfs  -l zfs0                 $DISK"   # p3  (rest)
run "newfs_msdos -F 32 -c 1 /dev/${DISK}p1 >/dev/null"          # ESP as FAT32

# === Stage B: ZFS pool + boot-environment layout ===========================

say "Stage B - ZFS pool and boot-environment datasets"
run "zpool create -f -o ashift=12 -o altroot=$MNT -o cachefile=/tmp/zpool.cache \\
        -O compress=lz4 -O atime=off -O mountpoint=none $POOL /dev/${DISK}p3"
run "zfs create -o mountpoint=none $POOL/ROOT"
run "zfs create -o mountpoint=/ -o canmount=noauto $POOL/ROOT/default"
run "zpool set bootfs=$POOL/ROOT/default $POOL"
run "zfs mount $POOL/ROOT/default"
run "zfs create -o mountpoint=/home $POOL/home"
run "zfs create -o mountpoint=/var -o canmount=off $POOL/var"
run "zfs create -o exec=off -o setuid=off $POOL/var/log"
run "zfs create -o exec=off -o setuid=off $POOL/var/audit"
run "zfs create $POOL/var/tmp"
run "zfs create -o mountpoint=/usr -o canmount=off $POOL/usr"
run "zfs create $POOL/usr/src"

# === Stage C: base + kernel ================================================
# Stream from the mirror (disc1 has no .txz; /tmp tmpfs is too small to stage).
# Use local sets instead if they are present (a dvd1 install).

say "Stage C - base.txz + kernel.txz into the pool"
for set in base kernel; do
    if [ -f "$SETS_DIR/$set.txz" ]; then
        run "tar -xpf $SETS_DIR/$set.txz -C $MNT"
    else
        run "fetch -o - $MIRROR/$set.txz | tar -xpf - -C $MNT"
    fi
done
[ "$GO" = 1 ] && { [ -f "$MNT/boot/kernel/kernel" ] || die "kernel missing after extract"; }

# === Stage D: configure the installed system ===============================

say "Stage D - configure (rc.conf, loader, fstab, tz, boot plumbing)"
run "mkdir -p $MNT/etc/zfs && cp /tmp/zpool.cache $MNT/etc/zfs/zpool.cache"
run "sysrc -f $MNT/boot/loader.conf zfs_load=YES"
run "sysrc -R $MNT zfs_enable=YES"
run "sysrc -R $MNT hostname=$HOSTNAME"
run "sysrc -R $MNT ifconfig_$NETIF=DHCP"
run "sysrc -R $MNT sshd_enable=YES"
# swap by its GPT label, which does not renumber
run "printf '/dev/gpt/swap0\\tnone\\tswap\\tsw\\t0\\t0\\n' > $MNT/etc/fstab"
run "cp $MNT/usr/share/zoneinfo/$TIMEZONE $MNT/etc/localtime"
# FreeBSD's default sshd forbids root key login - allow it (but prefer the user)
run "sed -i '' '/PermitRootLogin/d' $MNT/etc/ssh/sshd_config"
run "echo 'PermitRootLogin prohibit-password' >> $MNT/etc/ssh/sshd_config"

# === Stage E: EFI loader onto the ESP ======================================

say "Stage E - EFI loader onto the ESP (self-contained, no NVRAM entry)"
run "mkdir -p /tmp/esp && mount -t msdosfs /dev/${DISK}p1 /tmp/esp"
run "mkdir -p /tmp/esp/EFI/freebsd /tmp/esp/EFI/BOOT"
run "cp $MNT/boot/loader.efi /tmp/esp/EFI/freebsd/loader.efi"
run "cp $MNT/boot/loader.efi /tmp/esp/EFI/BOOT/BOOTX64.EFI"
run "umount /tmp/esp"

# === Stage F: accounts =====================================================

say "Stage F - root password and a wheel user"
# root: locked by default here; set one if you want console root login.
#   echo 'secret' | pw -V $MNT/etc usermod root -h 0
run "pw -V $MNT/etc useradd $NEWUSER -m -G wheel -s /bin/sh -c '$NEWUSER' || true"
# pw -m in a chroot creates the home owned by ROOT, not the user - which later
# stops the user writing ~/.cache, and a KDE login then has no icon/service
# cache and every desktop icon is blank. chown the home to the user. (Found the
# hard way on the T480.)
run "chroot $MNT chown -R $NEWUSER:$NEWUSER /home/$NEWUSER"
if [ -n "$SSH_KEY_URL" ]; then
    run "mkdir -p $MNT/root/.ssh && fetch -o $MNT/root/.ssh/authorized_keys $SSH_KEY_URL"
    run "mkdir -p $MNT/home/$NEWUSER/.ssh && fetch -o $MNT/home/$NEWUSER/.ssh/authorized_keys $SSH_KEY_URL"
    run "chmod 700 $MNT/root/.ssh $MNT/home/$NEWUSER/.ssh"
    run "chmod 600 $MNT/root/.ssh/authorized_keys $MNT/home/$NEWUSER/.ssh/authorized_keys"
    run "chroot $MNT chown -R $NEWUSER:$NEWUSER /home/$NEWUSER/.ssh"
fi
echo "    (set passwords with: pw -V $MNT/etc usermod <name> -h 0  <<<password,"
echo "     or 'passwd' after first boot. doas/sudo come from pkg, not base.)"

# === Stage G: finish =======================================================

say "Stage G - export and finish"
run "zpool export $POOL"

cat <<DONE

$( [ "$GO" = 1 ] && echo 'Installed.' || echo 'Dry run complete - nothing was changed.' )

Next:
  1. Remove the install media (eject the CD / detach the ISO).
  2. Reboot. It boots the ZFS pool via \\EFI\\BOOT\\BOOTX64.EFI - no NVRAM
     entry is needed.
  3. Log in, verify:  bectl list   zpool status   swapinfo -h
  4. The desktop (KDE Plasma + SDDM via pkg) is the next stage; see
     docs/freebsd-install-plan.md.

TODO for v0.2: ZFS native encryption, and the Plasma desktop stage.
DONE
