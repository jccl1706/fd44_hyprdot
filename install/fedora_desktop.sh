#!/usr/bin/env bash
# =========================================================================
# fedora_desktop.sh - NVIDIA and a minimal KDE, on a booted Fedora
# =========================================================================
#
# Usage:  sudo install/fedora_desktop.sh [--go]
#
# Stage four of four, the last that is required, and the first that runs ON the
# new machine rather than
# from the one beside it. Stages one to three were a chroot; this needs a
# running kernel to build a module against.
#
# ORDER IS DELIBERATE: RPM Fusion, then NVIDIA, then KDE, and a reboot to prove
# the driver before a display manager depends on it. The Gentoo install this
# disk used to carry was locked out of booting by exactly this module, and the
# difference between "no desktop" and "no machine" is worth one extra reboot.
#
# WEAK DEPENDENCIES ARE ON HERE, unlike the bootstrap. That was a deliberate
# "name everything"; akmod-nvidia genuinely needs its recommends to build and
# load, and a KDE missing its recommends is a desktop with no icons, no
# portals and no keyring. The minimalism in this file is the PACKAGE LIST, not
# the dependency resolver.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfedora:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

GO=0
while (( $# )); do
    case "$1" in
        --go) GO=1; shift ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

(( EUID == 0 )) || die "run this with sudo"
[[ -f /etc/fedora-release ]] || die "this runs ON the Fedora install, not from NixOS"
RELEASEVER="$(rpm -E %fedora)"
KVER="$(uname -r)"

note "this machine"
printf '  %-12s %s\n' "fedora"  "$RELEASEVER"
printf '  %-12s %s\n' "kernel"  "$KVER"
printf '  %-12s %s\n' "packages" "$(rpm -qa | wc -l)"
printf '  %-12s %s\n' "gpu"     "$(lspci -nn | grep -i 'VGA\|3D' | head -1 | cut -c1-70)"
printf '\n'

# THE KDE LIST, NAMED RATHER THAN GROUPED.
#
# @kde-desktop-environment is about 1800 packages. This is the set that makes a
# usable Plasma and stops: the shell, the display manager, a file manager, an
# archiver, a terminal, the settings panel. It mirrors what
# fd44_nixos/modules/desktop-plasma.nix keeps on the other disk, so the two
# machines feel the same.
#
# plasma-workspace brings kwin, the panel and the compositor. plasma-desktop is
# the desktop shell proper. xdg-desktop-portal-kde is NOT optional: without it
# file pickers and screen sharing fail in Wayland applications, and it fails
# quietly at the moment you try to use one.
KDE=(
    plasma-desktop plasma-workspace
    sddm sddm-breeze
    xdg-desktop-portal-kde
    dolphin ark konsole
    # SPECTACLE, BECAUSE WITHOUT IT PRINT SCREEN DOES NOTHING. Plasma's
    # screenshot shortcut and its portal both hand the job to Spectacle, and on
    # Wayland there is no fallback: grim and friends need wlr-screencopy, which
    # KWin does not implement. A desktop that cannot take a picture of itself is
    # missing something basic, and it was noticed the hard way - twice.
    spectacle
    plasma-systemsettings
    plasma-nm plasma-pa
    kscreen

    # BREEZE FOR GTK APPLICATIONS, which is two packages, not one. breeze-gtk is
    # only the theme sitting in /usr/share/themes; nothing reads it on its own,
    # and a fresh Plasma install leaves GTK applications on Adwaita. kde-gtk-config
    # is the part that applies it: it writes ~/.config/gtk-{3,4}.0/settings.ini
    # and the matching gsettings keys, and rewrites them whenever the Plasma
    # colour scheme changes, so light/dark stays in step with one setting.
    #
    # THIS IS ALSO WHAT THEMES BRAVE. Chromium follows Plasma through
    # chromium-qt6-ui below, but Brave's upstream build has no Qt variant and
    # derives its colours from the GTK theme, so Brave is Breeze only once
    # kde-gtk-config has written those files.
    breeze-gtk kde-gtk-config

    # THE KEYRING, AND WHY A PAM MODULE IS A DESKTOP PACKAGE. Chromium and Brave
    # ask the system keyring to hold the key their saved passwords are encrypted
    # with, and on Plasma that keyring is KWallet. On an account with no wallet
    # yet, the first browser launch runs KWallet's first-use wizard - which on
    # this machine offered the GPG-backed wallet, found no GPG secret key, and
    # failed with two stacked dialogs over the browser.
    #
    # INSTALLING THIS IS THE WHOLE FIX, and it looks like nothing because the
    # wiring already ships: /etc/pam.d/sddm carries `-auth optional
    # pam_kwallet5.so` and `-session optional pam_kwallet5.so auto_start`, where
    # the leading `-` means "skip silently if the module is missing". So the
    # lines sit inert on a stock install until the package is there, and then
    # SDDM creates and unlocks the wallet with the login password.
    pam-kwallet

    # DISCOVER, and only the backend this machine actually uses. Fedora splits
    # it into nine packages: plasma-discover is the shell, and each backend is
    # separate. packagekit is the one that talks to dnf.
    #
    # Deliberately NOT installed: -rpm-ostree (that is Silverblue, not this),
    # -snap (no snapd here), -kns (store content, wallpapers and widgets),
    # -flatpak (nothing uses flatpak on this machine - add it with flatpak
    # itself if that changes).
    #
    # -notifier is what tells you updates exist without opening anything, which
    # is the same job the fd44 bar's update box does on the Hyprland machines.
    plasma-discover plasma-discover-packagekit plasma-discover-notifier

    # REMOVABLE DISKS, which a minimal Plasma does not get. Dolphin's device
    # list, the panel's Disks & Devices applet and the Device Notifier are all
    # Solid talking to udisks2 over D-Bus, and Solid itself (kf6-solid) is only
    # the client half - it arrives with Plasma, udisks2 does not. Without it a
    # plugged-in drive is visible to lsblk and lsusb and INVISIBLE TO THE
    # DESKTOP, with nothing anywhere saying why. Measured with the Samsung T5 on
    # this machine: sda1 present, exfat, labelled, and absent from Dolphin.
    #
    # exfatprogs because that is what the external drives here are formatted
    # with. The kernel mounts exfat on its own; without the userspace tools
    # there is no fsck.exfat, so udisks can neither check nor relabel one.
    udisks2 exfatprogs
    pipewire wireplumber pipewire-pulseaudio
)

# THE TOOLS A MACHINE NEEDS WHEN SOMETHING GOES WRONG, which is not the same
# list as the tools it needs to run. Every one of these was wanted at some point
# while building this install and was not there; none of them is bloat, and
# together they are a few MB.
TOOLS=(
    bash-completion       # dnf and systemctl are unusable without it
    lsof strace           # what is holding this file, what is this process doing
    wget                  # curl is in @core; wget is what half of every README uses
    git                   # this repository has to be clonable on the machine
    rsync                 # moving things between the two systems on this box
    efibootmgr            # the boot entry below, and reading the order back
    compsize              # what the btrfs compression is actually saving
)

# THE BROWSERS. Chromium is in Fedora's own repositories; Brave is not and
# never will be, so it comes from its own.
#
# chromium-qt6-ui IS THE POINT OF SPLITTING THIS OUT. Fedora builds Chromium's
# toolkit layer as separate subpackages, and the default pulls the GTK one. On
# a Plasma desktop that means GTK file dialogs, GTK scrollbars and a browser
# that does not follow the system theme. The Qt6 build uses Plasma's own file
# picker and colours.
CHROMIUM=(
    chromium
    chromium-qt6-ui
)

if (( ! GO )); then
    note "would enable RPM Fusion free + nonfree for Fedora $RELEASEVER"
    note "would install akmod-nvidia xorg-x11-drv-nvidia-cuda"
    note "would install, with weak deps:"
    printf '    %s\n' "${KDE[@]}" "${TOOLS[@]}" "${CHROMIUM[@]}"
    note "would add Brave's repository and install brave-browser"
    note "would pre-answer KWallet for ${SUDO_USER:-the invoking user}"
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

# --- RPM Fusion --------------------------------------------------------------
#
# BOTH REPOSITORIES. The NVIDIA driver is in nonfree; free is what nonfree's
# packages expect to resolve against, and installing one without the other
# produces dependency failures that name neither.
note "enabling RPM Fusion"
dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$RELEASEVER.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$RELEASEVER.noarch.rpm"

note "refreshing metadata"
dnf -y makecache

# --- NVIDIA ------------------------------------------------------------------
#
# akmod, NOT kmod: akmod rebuilds the module against each new kernel as it is
# installed. A kmod is built for one kernel and silently stops matching after
# the next update, which on this hardware means no display.
#
# THE KERNEL HEADERS MATTER and are not implied. akmods needs kernel-devel for
# the RUNNING kernel to build against; without it the build is skipped and the
# failure only appears at the next boot, as a black screen.
note "installing the NVIDIA driver"
dnf -y install kernel-devel-"$KVER" akmod-nvidia xorg-x11-drv-nvidia-cuda

note "building the module for $KVER now, rather than discovering it at boot"
akmods --kernels "$KVER" --force || warn "akmods reported a problem - check before rebooting"

# --- the kernel command line -------------------------------------------------
#
# nvidia_drm.modeset=1 AND fbdev=1. The first gives the driver kernel mode
# setting, which Wayland requires. The second gives it a framebuffer console -
# without it the machine boots to a black screen between the bootloader and the
# display manager, which looks exactly like a failed boot.
#
# This cost real time on the Gentoo install that used to be on this disk; the
# write-up is in install/gentoo_desktop.sh and the salvaged scripts on the T5.
note "adding the NVIDIA kernel parameters"
CMDLINE=/etc/kernel/cmdline
for arg in nvidia_drm.modeset=1 nvidia_drm.fbdev=1; do
    grep -qw -- "$arg" "$CMDLINE" || printf ' %s' "$arg" >> "$CMDLINE"
done
sed -i 's/[[:space:]]\+/ /g; s/[[:space:]]*$//' "$CMDLINE"
printf '  %s\n' "$(cat "$CMDLINE")"

note "rewriting the boot entry with the new command line"
kernel-install add "$KVER" "/usr/lib/modules/$KVER/vmlinuz"
grep -h ^options /boot/loader/entries/*.conf | sed 's/^/  /'

# --- KDE ---------------------------------------------------------------------
note "installing a minimal KDE (${#KDE[@]} packages named, plus their deps)"
dnf -y install "${KDE[@]}"

note "and the tools for when something goes wrong"
dnf -y install "${TOOLS[@]}"

note "Chromium, with the Qt6 UI so it matches Plasma"
dnf -y install "${CHROMIUM[@]}"

# --- Brave -------------------------------------------------------------------
#
# ITS OWN REPOSITORY, SIGNED WITH ITS OWN KEY. Brave publishes a .repo file that
# sets gpgcheck=1 and points at its key; importing the key first means the very
# first package is verified rather than trusted.
#
# NOT a flatpak, and not a tarball in $HOME: a browser gets security updates
# more often than anything else on the machine, and it should come through the
# same dnf that updates everything else.
note "adding Brave's repository"
rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
dnf -y config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
    || dnf -y config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

note "installing Brave"
dnf -y install brave-browser

note "enabling the display manager"
systemctl set-default graphical.target
systemctl enable sddm


# --- KWallet ----------------------------------------------------------------
#
# WHAT THIS FILE DOES AND DOES NOT DO. `First Use=false` skips the wizard's
# introductory page, and that is all - the wizard fires on the ABSENCE OF A
# WALLET, so this file alone does not suppress it. It settles how the wallet
# behaves once it exists, so it never asks to be unlocked again.
#
# AND pam-kwallet NO LONGER CREATES THAT WALLET, which this comment used to
# claim. Measured on this machine, Fedora 44, libgcrypt 1.12.2, KDE 6.7.5, on a
# fresh install with an empty home:
#
#   sddm-helper[...]: pam_kwallet5(sddm:session): pam_kwallet5: Fail into
#                     creating the hash
#
# every login, after which ~/.local/share/kwalletd stays empty and the first
# application to want a secret - a browser - gets the creation wizard. The
# failure is inside the module's PBKDF2 call. It is not SELinux (no AVC names
# it), not FIPS (fips_enabled is 0), not a missing binary (/usr/bin/ksecretd is
# present and running) and not a permissions problem on the directory.
#
# So the wallet has to be created by hand, once, and the choice there is real:
# a BLANK password means kwalletd opens it silently forever and nothing ever
# prompts again, at the cost of the wallet being unencrypted at rest. A real
# password is properly encrypted and asks once per login, because unlocking
# goes through the same broken hash. This machine took the blank one, which is
# the same security as Chromium's --password-store=basic but covers every KDE
# application rather than just the browsers.
#
# Revisit when pam-kwallet or libgcrypt moves: if a login ever populates
# ~/.local/share/kwalletd by itself, the wallet can be recreated with a real
# password and this note deleted.
if [[ -n ${SUDO_USER-} && $SUDO_USER != root ]]; then
    user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    if [[ -d $user_home ]]; then
        note "pre-answering KWallet for $SUDO_USER"
        [[ -d $user_home/.config ]] || install -d -o "$SUDO_USER" -g "$SUDO_USER" -m 0700 "$user_home/.config"
        cat > "$user_home/.config/kwalletrc" <<'WALLET'
[Wallet]
Enabled=true
First Use=false
Use One Wallet=true
Prompt on Open=false
Close When Idle=false
Leave Open=true
WALLET
        chown "$SUDO_USER:$SUDO_USER" "$user_home/.config/kwalletrc"
    fi
fi

# --- the firmware boot entry -------------------------------------------------
#
# STAGE THREE PROMISED THIS AND NOTHING DELIVERED IT. bootctl runs there with
# --no-variables for a good reason - at that moment there is no kernel yet, and
# a firmware entry pointing at an empty systemd-boot is a machine that reaches
# no operating system at all, which happened once and needed the firmware menu
# to rescue. Its comment says the entry "gets added deliberately in stage four,
# after there is something to boot". Stage four never did.
#
# What that left: Fedora reachable only through the firmware's fallback path
# (\EFI\BOOT\BOOTX64.EFI, which both disks have), listed last in BootOrder
# behind NixOS, so every boot needed somebody to choose it by hand.
#
# A NAMED ENTRY, NOT bootctl's. `bootctl install` without --no-variables would
# create one labelled "Linux Boot Manager" - which is exactly what the NixOS
# install on the other disk already calls itself, giving two identically named
# entries on two disks. "Fedora" says which is which in the firmware menu.
note "the firmware boot entry"
ESP_DEV="$(findmnt -no SOURCE /boot)"
ESP_DISK="/dev/$(lsblk -no PKNAME "$ESP_DEV")"
ESP_PART="$(cat "/sys/class/block/$(basename "$ESP_DEV")/partition")"
if efibootmgr | grep -q 'Fedora[[:space:]]'; then
    note "already there"
else
    efibootmgr -q -c -d "$ESP_DISK" -p "$ESP_PART" -L "Fedora" \
        -l '\EFI\systemd\systemd-bootx64.efi' \
        || warn "could not create the entry - the firmware may refuse writes"
fi

# FIRST IN THE ORDER, WITHOUT DISCARDING THE REST. -o takes the whole list, so
# it is built from what is already there rather than typed out: the other
# entries are NixOS's, and a Fedora install has no business dropping them.
fedora_num="$(efibootmgr | awk '/[[:space:]]Fedora$/ {print substr($1,5,4); exit}')"
if [[ -n $fedora_num ]]; then
    rest="$(efibootmgr | awk '/^BootOrder:/ {print $2}' | tr ',' '\n' | grep -vx "$fedora_num" | paste -sd,)"
    efibootmgr -q -o "${fedora_num}${rest:+,$rest}" \
        || warn "could not set the boot order - set it in the firmware menu"
    efibootmgr | grep -E '^BootOrder|Fedora' | sed 's/^/  /'
fi

printf '\n'
note "done"
printf '  %-12s %s\n' "packages" "$(rpm -qa | wc -l)"
printf '  %-12s %s\n' "root used" "$(df -h / | awk 'NR==2{print $3}')"
printf '\n'
warn "REBOOT NOW, and expect the first boot to take longer: akmod may rebuild."
warn "If it comes up to a black screen, the firmware menu still reaches NixOS."
