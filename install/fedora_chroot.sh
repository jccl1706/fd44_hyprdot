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

# MOUNT IF NEEDED rather than refusing. This is stage three of a sequence that
# has had to be re-run several times, and a clean-up between attempts leaves the
# filesystems unmounted - which is the correct state to clean up TO. Refusing
# then makes the operator run two commands where one would do, and hand-typing
# mount lines for the disk you are installing to is exactly where a wrong device
# gets typed.
findmnt -n "$MNT"      >/dev/null 2>&1 || { mkdir -p "$MNT";      mount "$ROOT" "$MNT"; }
findmnt -n "$MNT/boot" >/dev/null 2>&1 || { mkdir -p "$MNT/boot"; mount "$ESP"  "$MNT/boot"; }

# CHECKED AFTER MOUNTING, not before - which is the order it has to be. An
# unmounted /mnt/fedora is an empty directory, so testing it first reports "not
# bootstrapped" for a perfectly good install and sends you looking for a problem
# that is not there.
[[ -d $MNT/usr/lib/modules ]] || die "$MNT does not look bootstrapped - run stage two first"

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
printf '  bootctl install, loader.conf, kernel-install add, /.autorelabel\n\n'
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
# THE RESCUE HOOK IS MASKED, NOT ASKED. dracut_rescue_image=no in
# /etc/kernel/install.conf was the polite way and it is ignored: the hook runs
# regardless, and then fails, and because one plugin failing aborts the whole
# transaction it takes the GOOD initramfs down with it -
#
#   50-dracut.install succeeded.
#   51-dracut-rescue.install: /boot/fedora/0-rescue/loader/entries/<id>-0-rescue.conf:
#                             No such file or directory
#   (plugins) failed with exit status 1.
#
# The path is nonsense because Fedora sets entry-token=fedora, so entries live
# under /boot/fedora/<version>/ and the rescue hook derives a boot root from
# that layout incorrectly.
#
# kernel-install reads /etc/kernel/install.d before /usr/lib/kernel/install.d
# and a symlink to /dev/null there disables a plugin outright - the same
# convention systemd uses for masking units. The setting is kept too, since it
# is correct even if it is not sufficient.
note "masking the rescue-image hook"
mkdir -p "$MNT/etc/kernel" "$MNT/etc/kernel/install.d"
ln -sf /dev/null "$MNT/etc/kernel/install.d/51-dracut-rescue.install"
rm -rf "$MNT/boot/fedora/0-rescue"

# --- THE KERNEL COMMAND LINE, WRITTEN DOWN -----------------------------------
#
# WITHOUT THIS THE NEW SYSTEM INHERITS THE OLD ONE'S. 90-loaderentry.install
# falls back to the RUNNING kernel's /proc/cmdline when /etc/kernel/cmdline is
# absent - and /proc here is bind-mounted from the host, so the first entry this
# script produced read:
#
#   options init=/nix/store/x3y0srd8q4a3...-nixos-system-.../init quiet ...
#           root=fstab splash loglevel=0 lsm=landlock,yama,bpf
#
# Fedora booting with NixOS's init= and root=fstab is a panic, and a baffling
# one: the entry looks perfect, the files it names exist, and the failure says
# nothing about where the line came from.
#
# WHAT IS ON IT. root by UUID, for the reason everything here is by UUID. ro
# because the initramfs mounts read-only and systemd remounts rw - mounting rw
# in the initramfs skips the fsck. Nothing else: no quiet, no splash. A machine
# being installed for the first time should say what it is doing, and these are
# one edit away once it is known to work.
printf 'root=UUID=%s ro\n' "$ROOT_UUID" > "$MNT/etc/kernel/cmdline"
printf '  cmdline: %s' "$(cat "$MNT/etc/kernel/cmdline")"

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

# THE MENU, WHICH bootctl LEAVES SWITCHED OFF. `bootctl install` writes a
# loader.conf whose every line is a comment:
#
#     #timeout 3
#     #console-mode keep
#
# and with no timeout set, systemd-boot's default is 0 - it boots the default
# entry at once and shows the menu only while a key is held. That is not a
# broken install and it produces no message, which is why it took a while to
# notice that Fedora came up with no menu while NixOS on the other disk showed
# one: NixOS sets boot.loader.timeout = 3, and nothing here set Fedora's.
#
# WHAT THE MENU IS FOR ON THIS MACHINE, given it lists one entry. Type #1
# entries are read only from the ESP the loader was started from, and the NixOS
# entries live on NIXESP, so this menu will never show the other system -
# choosing between the two disks is the firmware's job. What it does give is a
# way in when the single entry will not boot: the rescue entry, an older kernel
# after an update, and "Reboot Into Firmware Interface" without timing a key
# press against a one-second window.
note "switching the systemd-boot menu on"
printf 'timeout 5\nconsole-mode keep\n' > "$MNT/boot/loader/loader.conf"
printf '  %s\n' "$(tr '\n' ' ' < "$MNT/boot/loader/loader.conf")"

note "placing the kernel and building its initramfs"
inch kernel-install add "$KVER" "/usr/lib/modules/$KVER/vmlinuz"

note "what landed on the ESP"
ls "$MNT/boot" | sed 's/^/  /'
ls "$MNT/boot/loader/entries" 2>/dev/null | sed 's/^/  entry: /' || warn "no loader entries - the kernel did not register"

# --- services and SELinux ----------------------------------------------------
note "enabling NetworkManager and sshd"
inch systemctl enable NetworkManager sshd

# --- SELinux, labelled HERE rather than on first boot -------------------------
#
# .autorelabel IS NOT ENOUGH AND CANNOT BE. Packages installed through an
# installroot are never labelled - the policy was not loaded, so nothing applied
# a context to anything. On the first boot systemd loads the policy, finds an
# entirely unlabelled filesystem, and cannot start:
#
#   systemd[1]: Unable to fix SELinux security context of /dev/...:
#               Permission denied        (several hundred times)
#   systemd[1]: Too many messages being logged to kmsg, ignoring
#   [!!!!!!] Failed to allocate manager object.
#
# "Failed to allocate manager object" is PID 1 giving up. /.autorelabel is run
# BY systemd, so it can do nothing about a system where systemd cannot start -
# the mechanism needs the very thing it is supposed to repair.
#
# setfiles works offline from the file_contexts database and needs no loaded
# policy, which is exactly why Anaconda runs it at the end of an install rather
# than deferring. It takes a couple of minutes on a fresh root.
note "labelling the filesystem for SELinux (this takes a minute)"
if [[ -f $MNT/etc/selinux/targeted/contexts/files/file_contexts ]]; then
    inch setfiles -F /etc/selinux/targeted/contexts/files/file_contexts / \
        || warn "setfiles reported errors - check before booting"
    # No .autorelabel afterwards: the work is done, and leaving it would make
    # the first boot repeat it for no reason.
    rm -f "$MNT/.autorelabel"
    note "labelled"
else
    warn "no file_contexts - selinux-policy-targeted is not installed"
    die "run stage two again; booting now would fail to start systemd"
fi

# ASKED ONLY ONCE. This script has had to be re-run a dozen times, and
# prompting for two passwords on every pass is how a careful operator ends up
# typing one wrong. A locked or empty entry in /etc/shadow begins with ! or *,
# or is blank; anything else is a real hash and gets left alone.
printf '\n'
has_password() {
    local h; h="$(awk -F: -v u="$1" '$1==u {print $2}' "$MNT/etc/shadow" 2>/dev/null)"
    [[ -n $h && $h != "!"* && $h != "*"* && $h != "!!" ]]
}
for u in root "$USERNAME"; do
    if has_password "$u"; then
        note "$u already has a password - leaving it"
    else
        note "set a password for $u"
        inch passwd "$u"
    fi
done

printf '\n'
note "done - this should now boot"
warn "the FIRST boot relabels SELinux and reboots itself once. That is expected."
