#!/usr/bin/env bash
# =========================================================================
# gentoo_chroot.sh - make the unpacked stage3 into a system that boots
# =========================================================================
#
# Usage:  sudo install/gentoo_chroot.sh [--mnt /mnt/gentoo] [--dry-run]
#
# Stage two of the install. Stage one (install_gentoo.sh) left a partitioned
# disk with a stage3 unpacked on it; this writes the configuration, enters the
# chroot and builds a system that will start on its own.
#
# IT STOPS AT "BOOTABLE", deliberately. Kernel, fstab, bootloader, network,
# users, sshd - and nothing else. The graphics driver and the gaming stack
# come after the first boot, over ssh, on a machine that can be rebooted
# without a chroot: a driver that fails to build is then an inconvenience
# rather than a reason to start again.
#
# BINARY PACKAGES WHERE THEY EXIST. Gentoo's own binhost carries the
# expensive ones - the kernel, gcc, rust, llvm - and `emerge` falls back to
# building anything it does not have. This is what makes the first day hours
# rather than a weekend; USE flags still work, they just cause a local build
# when they differ from the binary's.
#
# THE ESP IS GENTOO'S OWN, on Gentoo's own disk, mounted at /efi. Nothing here
# touches the NixOS ESP on the other drive: the firmware's boot menu chooses
# between the two disks, and neither system can break the other's bootloader.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sgentoo:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

MNT=/mnt/gentoo
DRY=0
HOSTNAME_NEW=gentoo-gaming00
TIMEZONE=America/New_York
USERNAME=jc

while (( $# )); do
    case "$1" in
        --mnt)      MNT="${2:?}"; shift 2 ;;
        --hostname) HOSTNAME_NEW="${2:?}"; shift 2 ;;
        --user)     USERNAME="${2:?}"; shift 2 ;;
        --dry-run)  DRY=1; shift ;;
        -h|--help)  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

run() { if (( DRY )); then printf '%swould run:%s %s\n' "$dim" "$reset" "$*"; else "$@"; fi; }

(( EUID == 0 )) || die "must run as root"
[[ -d $MNT ]] || die "$MNT does not exist - run install_gentoo.sh first"
[[ -x $MNT/bin/bash ]] || die "no stage3 at $MNT - run install_gentoo.sh first"
mountpoint -q "$MNT" || die "$MNT is not a mount point - is the Gentoo root mounted?"
mountpoint -q "$MNT/efi" || die "$MNT/efi is not mounted - the ESP has to be there for the bootloader"

root_uuid="$(findmnt -no UUID "$MNT")"
esp_uuid="$(findmnt -no UUID "$MNT/efi")"
swap_dev="$(lsblk -nro PATH,FSTYPE,LABEL | awk '$2 == "swap" && $3 == "GENTOOSWAP" { print $1; exit }')"
swap_uuid="$([[ -n $swap_dev ]] && blkid -s UUID -o value "$swap_dev" || true)"

note "root UUID $root_uuid"
note "ESP  UUID $esp_uuid"
[[ -n $swap_uuid ]] && note "swap UUID $swap_uuid"

# --- configuration the chroot needs before it can do anything -------------

note "writing portage configuration"
if (( ! DRY )); then
    mkdir -p "$MNT/etc/portage/binrepos.conf" "$MNT/etc/portage/package.use" "$MNT/etc/portage/package.license"

    cat > "$MNT/etc/portage/make.conf" <<CONF
# Written by install/gentoo_chroot.sh (fd44_hyprdot).

COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

# 16 threads on the 9800X3D, and --load-average so a parallel emerge does not
# leave the desktop unusable while it runs.
MAKEOPTS="-j16 -l16"
EMERGE_DEFAULT_OPTS="--jobs=4 --load-average=16 --keep-going --with-bdeps=y"

# getbinpkg: take Gentoo's binary packages when they match, build when they do
# not. binpkg-request-signature makes portage refuse an unsigned one.
FEATURES="getbinpkg binpkg-request-signature parallel-fetch candy"

ACCEPT_KEYWORDS="amd64"
# The NVIDIA driver and several firmware blobs are not free software and are
# named here rather than blanket-accepted, so a licence change is a question
# rather than a surprise.
# NVIDIA-2025 IS THE CURRENT NAME. This said NVIDIA-r2, which is what the
# licence used to be called, and the result was every single driver version
# reporting as masked:
#
#   615.71.09 (masked by: NVIDIA-2025 license(s), ~amd64 keyword)
#
# A licence accepted by an old name is not accepted at all.
ACCEPT_LICENSE="-* @FREE NVIDIA-2025 NVIDIA-r2 linux-fw-redistributable no-source-code"

VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"
L10N="en en-US"
LINGUAS="en en_US"

USE="wayland -kde -gnome pipewire pulseaudio alsa vulkan X"

GENTOO_MIRRORS="https://distfiles.gentoo.org"
CONF

    cat > "$MNT/etc/portage/binrepos.conf/gentoobinhost.conf" <<'CONF'
# Gentoo's official binary package host. Portage picks the one matching this
# profile; the signature check in FEATURES is what makes trusting it sane.
[binhost]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
CONF

    # sys-kernel/installkernel is what puts a kernel where the bootloader can
    # find it. With these flags it builds an initramfs with dracut and writes
    # a systemd-boot entry, which is why nothing here has to know the layout
    # of /efi.
    cat > "$MNT/etc/portage/package.use/installkernel" <<'CONF'
sys-kernel/installkernel dracut systemd-boot

# AND systemd ITSELF NEEDS USE=boot, which is where the bootctl binary and
# the kernel-install plugin come from. installkernel[systemd-boot] depends on
# systemd[boot], the stage3's systemd is built without it, and portage stops
# dead:
#
#   emerge: there are no ebuilds built with USE flags to satisfy
#           "sys-apps/systemd[boot(-)]"
#
# It is written here rather than left to --autounmask so the reason is on
# record. systemd then builds from source - a few minutes on 16 cores -
# because the binary package is compiled without it.
sys-apps/systemd boot
CONF

    cat > "$MNT/etc/fstab" <<FSTAB
# Written by install/gentoo_chroot.sh (fd44_hyprdot). BY UUID, because this
# machine's two NVMe drives have swapped kernel names between boots.
UUID=$root_uuid  /      ext4  noatime  0 1
UUID=$esp_uuid   /efi   vfat  umask=0077,shortname=winnt  0 2
FSTAB
    [[ -n $swap_uuid ]] && printf 'UUID=%s  none   swap  sw  0 0\n' "$swap_uuid" >> "$MNT/etc/fstab"

    # THE KERNEL COMMAND LINE, WRITTEN OUT because in a chroot there is none
    # to inherit. kernel-install builds its boot entry from /proc/cmdline on
    # a running system; inside a chroot that belongs to the HOST, so it
    # refuses and says so:
    #
    #   Please specify a command line to use in /etc/kernel/cmdline.
    #
    # root= by UUID for the same reason fstab is: the two NVMe drives on this
    # machine swap kernel names between boots. rw because systemd expects to
    # remount it itself.
    mkdir -p "$MNT/etc/kernel"
    printf 'root=UUID=%s rw\n' "$root_uuid" > "$MNT/etc/kernel/cmdline"

    printf '%s\n' "$HOSTNAME_NEW" > "$MNT/etc/hostname"
    ln -sfn "/usr/share/zoneinfo/$TIMEZONE" "$MNT/etc/localtime"
    printf 'en_US.UTF-8 UTF-8\nC.UTF8 UTF-8\n' > "$MNT/etc/locale.gen"
    printf 'LANG="en_US.UTF-8"\n' > "$MNT/etc/locale.conf"
    cp --dereference /etc/resolv.conf "$MNT/etc/resolv.conf"
fi

# --- the chroot itself ----------------------------------------------------

note "mounting the kernel filesystems"
if (( ! DRY )); then
    mountpoint -q "$MNT/proc" || mount --types proc /proc "$MNT/proc"
    for d in sys dev run; do
        mountpoint -q "$MNT/$d" || { mount --rbind "/$d" "$MNT/$d"; mount --make-rslave "$MNT/$d"; }
    done
fi

# The work inside is a script rather than a series of `chroot ... -c` calls:
# one environment, one place to read, and it can be re-run.
inside="$MNT/root/stage2-inside.sh"
note "writing the in-chroot half to ${inside#$MNT}"
if (( ! DRY )); then
    cat > "$inside" <<'INSIDE'
#!/bin/bash
set -euo pipefail
green=$'\033[1;32m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }

# set +u AROUND THE PROFILE, because Gentoo's own profile scripts are not
# written for it: /etc/profile.d/debuginfod.sh reads DEBUGINFOD_URLS before
# setting it, and under `set -u` that aborts the script on its first line -
# which is exactly how this failed the first time it ran.
set +u
source /etc/profile
set -u

# systemd's chroot check, told that this chroot is the machine being
# installed rather than somebody else's.
#
# ON ITS OWN THIS WAS NOT THE PROBLEM, and the first version of this comment
# said it was. 05-check-chroot.install failed for a second reason it only
# printed once the log was visible: "Please specify a command line to use in
# /etc/kernel/cmdline" - a chroot has no /proc/cmdline of its own to copy.
# That file is now written by the host half of this script. This stays
# because the check is still a check, and this chroot still is not the
# machine it is running on.
export SYSTEMD_IGNORE_CHROOT=1

note "fetching the portage tree"
emerge-webrsync

note "locales"
locale-gen

note "the profile in use"
eselect profile list | grep -E '\*|desktop/systemd' | head -5

# THE KERNEL COMES AS A BINARY. gentoo-kernel-bin is a prebuilt Gentoo kernel
# with its config; building one from source is the thing that makes people
# say Gentoo takes a weekend, and nothing about a gaming desktop needs a
# hand-rolled config to start with.
# ORDER MATTERS HERE, AND THE FIRST ATTEMPT HAD IT BACKWARDS. The kernel's
# postinst is what copies the kernel onto the ESP, via systemd's
# kernel-install - so everything it depends on has to exist BEFORE the kernel
# is merged, not after:
#
#   1. installkernel, with dracut and systemd-boot support
#   2. a machine-id, because the bls layout puts entries in
#      /efi/<machine-id>/<version>/ and kernel-install refuses without one -
#      a fresh stage3 has no machine-id at all
#   3. bootctl install, which creates /efi/loader and the EFI binaries
#   4. only then the kernel
#
# Merging the kernel first produced "FAILED postinst: 1 ... Kernel install
# failed" with the ESP still empty.
note "the tools that put a kernel on the ESP"
emerge --getbinpkg sys-kernel/installkernel

note "a machine-id for this install"
[[ -s /etc/machine-id ]] || systemd-machine-id-setup

note "bootloader onto Gentoo's own ESP"
bootctl install --esp-path=/efi

note "kernel and firmware"
# On failure, say WHY here rather than leaving it in a log the caller has to
# go and find with sudo.
if ! emerge --getbinpkg sys-kernel/gentoo-kernel-bin sys-kernel/linux-firmware; then
    log=/var/tmp/portage/sys-kernel/gentoo-kernel-bin-*/temp/build.log
    printf '\n--- the last of %s ---\n' "$log"
    tail -40 $log 2>/dev/null || printf '(no build log found)\n'
    exit 1
fi

# Deploy the kernel onto the ESP. This is the command the postinst itself
# names when it fails, and it is a no-op once the entry is there - which is
# what makes this script safe to run again.
note "putting the kernel on the ESP"
emerge --config sys-kernel/gentoo-kernel-bin

note "what actually landed there"
bootctl list 2>/dev/null | sed -n '1,20p' || true
find /efi -maxdepth 3 \( -name 'vmlinuz*' -o -name 'linux' -o -name '*.conf' \) 2>/dev/null | head -10

note "network and remote access"
emerge --getbinpkg net-misc/networkmanager net-misc/openssh app-admin/sudo net-dns/avahi
systemctl enable NetworkManager sshd avahi-daemon

# AND CHECKED, because `systemctl enable` failing quietly is how this install
# first booted with no network at all: the machine came up, the NIC was fine,
# and nothing was there to configure it. An enable that did not take is worth
# stopping for - it is the difference between a machine you can ssh into and
# one you have to walk to.
for unit in NetworkManager sshd; do
    state="$(systemctl is-enabled "$unit" 2>&1 || true)"
    case "$state" in
        enabled|enabled-runtime|alias|static|indirect)
            note "$unit: $state" ;;
        *)
            printf '\n  %s is %s, not enabled - the machine would boot without it\n' "$unit" "$state"
            exit 1 ;;
    esac
done

note "a wheel that can sudo"
sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

note "done inside the chroot"
printf '\n  Two passwords are still needed, and you type them:\n'
printf '    passwd                       # root\n'
printf '    useradd -m -G wheel,video,audio,input -s /bin/bash USERNAME\n'
printf '    passwd USERNAME\n\n'
INSIDE
    sed -i "s/USERNAME/$USERNAME/g" "$inside"
    chmod +x "$inside"
fi

note "entering the chroot"
if (( DRY )); then
    printf '%swould run:%s chroot %s /root/stage2-inside.sh\n' "$dim" "$reset" "$MNT"
    printf '%swould then leave you in:%s chroot %s /bin/bash\n' "$dim" "$reset" "$MNT"
else
    chroot "$MNT" /root/stage2-inside.sh
    note "the automatic part is finished - dropping you into the chroot"
    printf '  %sset the two passwords as printed above, then exit and reboot%s\n\n' "$dim" "$reset"
    chroot "$MNT" /bin/bash -l
fi
