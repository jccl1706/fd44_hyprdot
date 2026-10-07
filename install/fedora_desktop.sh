#!/usr/bin/env bash
# =========================================================================
# fedora_desktop.sh - NVIDIA and a minimal KDE, on a booted Fedora
# =========================================================================
#
# Usage:  sudo install/fedora_desktop.sh [--niri|--plasma] [--go]
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
# ONE DESKTOP OR THE OTHER, NEVER BOTH - the same rule install_fedora.sh keeps
# for Hyprland and Plasma, and for the same reason: two session managers and two
# portal implementations on one machine is a set of quiet, confusing failures.
DESKTOP=plasma
while (( $# )); do
    case "$1" in
        --go) GO=1; shift ;;
        --niri)   DESKTOP=niri;   shift ;;
        --plasma) DESKTOP=plasma; shift ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

(( EUID == 0 )) || die "run this with sudo"
[[ -f /etc/fedora-release ]] || die "this runs ON the Fedora install, not from NixOS"
RELEASEVER="$(rpm -E %fedora)"
KVER="$(uname -r)"
TARGET_USER="${SUDO_USER:-jc}"
# The checkout this script lives in, so it can call its siblings.
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

note "this machine"
printf '  %-12s %s\n' "fedora"  "$RELEASEVER"
printf '  %-12s %s\n' "kernel"  "$KVER"
printf '  %-12s %s\n' "packages" "$(rpm -qa | wc -l)"
printf '  %-12s %s\n' "gpu"     "$(command -v lspci >/dev/null && lspci -nn | grep -i 'VGA\|3D' | head -1 | cut -c1-70 || echo '(lspci not installed yet)')"
printf '  %-12s %s\n' "desktop" "$DESKTOP"
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
# THE NIRI LIST, WHICH IS WHAT THE FRAMEWORK RUNS.
#
# No display manager and no Plasma: the session is getty autologin on tty1 plus
# ~/.bash_profile, which reads ~/.local/state/fd44-compositor and hands the
# chosen compositor to uwsm. That arrangement is already in the repository and
# is linked by bin/link-dotfiles.sh; this list is the software it needs.
#
# niri IS IN FEDORA'S OWN REPOSITORIES - no COPR, no build. quickshell is not,
# and comes from the same COPR the laptop uses.
#
# xwayland-satellite IS NOT OPTIONAL ON niri. niri has no built-in Xwayland, so
# without it every X11 application simply fails to start, with nothing on screen
# to say why.
#
# THE PORTALS ARE gtk AND gnome, NOT kde. On niri the gnome portal provides the
# screencast and screenshot interfaces and gtk provides the file chooser; the
# KDE one would pull a third of Plasma in behind it.
NIRI=(
    niri
    quickshell
    uwsm                    # starts the session; the compositor runs under it
    # uwsm's OWN DEPENDENCY, WHICH IT DOES NOT DECLARE. `rpm -q --requires uwsm`
    # names /usr/bin/python3 and nothing else, but uwsm/main.py imports xdg on
    # line 34 - so on a minimal install every invocation dies with
    #
    #   ModuleNotFoundError: No module named 'xdg'
    #
    # and the session never starts. The Framework has it only because something
    # else pulled it in. Measured on a fresh fedora-gaming00: not installed.
    python3-pyxdg
    xwayland-satellite      # X11 applications, which niri cannot host itself
    xorg-x11-server-Xwayland
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome
    kitty                   # the terminal the keybinds in niri/binds.kdl name
    swaylock
    wl-clipboard cliphist   # copy/paste and its history
    grim slurp              # screenshots, which quickshell's binds call
    fuzzel                  # a launcher that works when quickshell does not
    waybar                  # likewise a bar - the fallback when the shell breaks
    # WITHOUT THIS THERE IS NO WALLPAPER AND NO ERROR. Every wallpaper in this
    # repository is .webp, and Qt cannot decode webp without the image format
    # plugins - so quickshell loads nothing, draws black, and says nothing in
    # the journal. The Framework has it; a minimal install does not.
    qt6-qtimageformats
    jetbrains-mono-fonts

    # THE FONT kitty.conf AND alacritty.toml ACTUALLY NAME, which nothing was
    # installing. Both ask for "Noto Sans Mono"; the laptop happened to have it
    # pulled in by another package and this machine did not, so the same
    # configuration rendered in two different fonts and only one of them was
    # the one written down. kitty hid it by matching a monospace face on its
    # own; alacritty took the substitution fontconfig offered - Noto Sans,
    # proportional - and the tmux status bar fell apart.
    #
    # A configuration that names a font is a configuration that has to install
    # it. Depending on another package to drag it in is how two machines from
    # one repository end up looking different.
    google-noto-sans-mono-fonts

    # THE APPLICATIONS THE REPOSITORY ALREADY ASSUMES. These were missing from
    # the first niri build because the list was read off the Framework's
    # SESSION packages and stopped there - so the machine came up with a
    # compositor, a shell and no file manager. Each of these is named in this
    # repository's own files, which is the test for belonging here:
    #
    #   nautilus      hypr/rules.lua has a translucency rule for it, and
    #                 Mod+E opens it in both compositors' binds
    #   gvfs          without it Nautilus has no trash, no mounts and no
    #                 network browsing - and says nothing about why
    #   file-roller   what Nautilus hands an archive to
    #   udiskie       systemd/udiskie.service is linked by link-dotfiles.sh
    #   restic        bin/backup.sh is nothing without it
    #   tmux          tmux/ is a tracked config this repository links
    #   bat           bashrc.d aliases to it in several places
    nautilus gvfs gvfs-fuse file-roller
    # PLYMOUTH, SO THE BOOT IS NOT A WALL OF TEXT. install_fedora.sh installs
    # these on the Framework and this machine had them before the rebuild;
    # plymouth-system-theme is what pulls the bgrt theme the firmware logo
    # needs, and without it the splash falls back to text.
    plymouth plymouth-system-theme
    udiskie
    restic
    tmux bat
    # THE AGENT THE FRAMEWORK ACTUALLY RUNS, read off it rather than guessed.
    # The first version of this list said polkit-gnome, which does not exist in
    # Fedora 44 at all - and because this script runs under set -e, that one
    # wrong name took the whole desktop install down with it after the NVIDIA
    # driver had already been built. Fedora offers polkit-kde (a third of
    # Plasma) and mate-polkit; the laptop uses neither.
    hyprpolkitagent         # without an agent, nothing can ask for a password
)

TOOLS=(
    bash-completion       # dnf and systemctl are unusable without it
    lsof strace           # what is holding this file, what is this process doing
    wget                  # curl is in @core; wget is what half of every README uses
    git                   # this repository has to be clonable on the machine
    rsync                 # moving things between the two systems on this box
    pciutils              # lspci - @core does not ship it, and this script
                          # reports the GPU before installing a driver for it
    efibootmgr            # the boot entry below, and reading the order back
    compsize              # what the btrfs compression is actually saving

    # PAPIRUS, AND FROM FEDORA RATHER THAN FROM GIT. Tela was here first,
    # installed by a script that cloned upstream and ran its installer into
    # ~/.local/share/icons - 190MB of theme, updated by remembering to pull.
    # Papirus is packaged, so it updates with everything else, and it already
    # draws the icons Tela did not: Plasma's battery applet asks for
    # battery-040-profile-balanced and its relatives when a power profile is
    # set, Tela ships only the plain names, and that one icon fell back to
    # Breeze and looked like a different theme in the middle of the tray.
    papirus-icon-theme
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
    if [[ $DESKTOP == niri ]]; then
        printf '    %s\n' "${NIRI[@]}" "${TOOLS[@]}" chromium
        note "would enable the nett00n/hyprland COPR for quickshell"
        note "would install Symbols Nerd Font from $REPO/fonts (Fedora packages none)"
        note "would autologin $TARGET_USER on tty1, with no display manager"
    else
        printf '    %s\n' "${KDE[@]}" "${TOOLS[@]}" "${CHROMIUM[@]}"
        note "would add Brave's repository and install brave-browser"
        note "would pre-answer KWallet for ${SUDO_USER:-the invoking user}"
    fi
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
PARAMS=(nvidia_drm.modeset=1 nvidia_drm.fbdev=1)

# AND THE QUIET BOOT, WHICH IS PLYMOUTH'S HALF OF THE BARGAIN. The splash only
# replaces the text if the text is silenced: rhgb asks for the graphical boot,
# quiet and the log levels stop the kernel and udev writing over it, and
# vt.global_cursor_default=0 removes the blinking cursor that otherwise sits in
# the corner of the splash. This is the Framework's line, kept in step.
PARAMS+=(quiet rhgb loglevel=3 systemd.show_status=false
         rd.systemd.show_status=false rd.udev.log_level=3 udev.log_level=3
         vt.global_cursor_default=0)

# WHOLE ARGUMENTS, WHOLE FILE, ONE LINE OUT. Three things went wrong here in
# turn, and each hid the next:
#
#   1. `grep -qw -- "$arg"` treats a dot as a word boundary, so
#      udev.log_level=3 matched inside the rd.udev.log_level=3 added moments
#      before and was never written.
#
#   2. Reading with `read -r -a have < "$CMDLINE"` takes only the FIRST LINE.
#      The file had two: stage three ends its line with a newline, so the very
#      first `printf ' %s' >>` started a second one. Everything on line two
#      looked absent and was appended again - the whole set, twice, which is
#      what the kernel then booted with.
#
#   3. `sed 's/[[:space:]]\+/ /g'` cannot join those lines, because sed works a
#      line at a time. The file stayed two lines however often it was tidied.
#
# So: read every line, compare whole fields, and write the result back as ONE
# line. A kernel command line is a single line by definition.
# AND IT DEDUPLICATES WHAT IS ALREADY THERE, not only what it adds. The first
# attempt at this fix joined the two lines and left every pre-existing
# duplicate in place - correct for new arguments, useless for a machine that
# had already been written twice by the broken version. A script that repairs
# the file has to repair the whole file.
#
# First occurrence wins, so order is preserved: root= stays at the front where
# it is read, and nothing is reordered behind the operator's back.
mapfile -t _cmdline_lines < "$CMDLINE"
read -r -a _have <<< "$(printf '%s ' "${_cmdline_lines[@]}")"
_out=()
_add() {
    local candidate="$1" seen
    for seen in "${_out[@]}"; do [[ $seen == "$candidate" ]] && return; done
    _out+=("$candidate")
}
for h in "${_have[@]}"; do [[ -n $h ]] && _add "$h"; done
for arg in "${PARAMS[@]}"; do _add "$arg"; done
printf '%s\n' "${_out[*]}" > "$CMDLINE"
unset _cmdline_lines _have _out
unset -f _add
printf '  %s\n' "$(cat "$CMDLINE")"

note "rewriting the boot entry with the new command line"
kernel-install add "$KVER" "/usr/lib/modules/$KVER/vmlinuz"
grep -h ^options /boot/loader/entries/*.conf | sed 's/^/  /'

# --- the desktop -------------------------------------------------------------
if [[ $DESKTOP == niri ]]; then
    # THE COPR IS FOR quickshell ALONE. niri is in Fedora's own repositories;
    # quickshell is not, and this is the COPR the Framework already uses, so
    # both machines run the same build.
    note "adding the quickshell COPR"
    dnf -y copr enable nett00n/hyprland

    # NAMES ARE CHECKED BEFORE ANY OF THEM IS INSTALLED. A single package that
    # does not exist makes dnf fail, and under set -e that ends the script -
    # after the NVIDIA driver has been built and before anything of the desktop
    # exists, which looks like "stage four finished" and is not.
    note "checking the package names resolve"
    missing=""
    for p in "${NIRI[@]}"; do
        dnf -q info "$p" >/dev/null 2>&1 || missing+="    $p"$'\n'
    done
    if [[ -n $missing ]]; then
        warn "these are not in any enabled repository:"
        printf '%s' "$missing" >&2
        die "fix the list before going further - nothing has been installed"
    fi

    note "installing niri and quickshell (${#NIRI[@]} packages named, plus their deps)"
    dnf -y install "${NIRI[@]}"

    note "and the tools for when something goes wrong"
    dnf -y install "${TOOLS[@]}"

    note "Chromium"
    dnf -y install chromium
else
    note "installing a minimal KDE (${#KDE[@]} packages named, plus their deps)"
    dnf -y install "${KDE[@]}"

    note "and the tools for when something goes wrong"
    dnf -y install "${TOOLS[@]}"

    note "Chromium, with the Qt6 UI so it matches Plasma"
    dnf -y install "${CHROMIUM[@]}"
fi

# --- Brave -------------------------------------------------------------------
#
# ITS OWN REPOSITORY, SIGNED WITH ITS OWN KEY. Brave publishes a .repo file that
# sets gpgcheck=1 and points at its key; importing the key first means the very
# first package is verified rather than trusted.
#
# NOT a flatpak, and not a tarball in $HOME: a browser gets security updates
# more often than anything else on the machine, and it should come through the
# same dnf that updates everything else.
if [[ $DESKTOP == plasma ]]; then
note "adding Brave's repository"
rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
dnf -y config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
    || dnf -y config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

note "installing Brave"
dnf -y install brave-browser
fi

if [[ $DESKTOP == niri ]]; then
    # SYMBOLS NERD FONT, WHICH FEDORA DOES NOT PACKAGE AT ALL. The only "nerd"
    # font in the repositories is texlive-inconsolata-nerd-font, which is
    # unrelated - so the glyphs in the bar, launcher, OSDs, power menu and lock
    # screen come from a font this repository carries at
    # fonts/nerd-fonts-symbols/ and installs itself.
    #
    # IT CANNOT BE LEFT AS A STEP TO REMEMBER. Without it every one of those
    # glyphs is an empty box, which looks like a broken shell rather than a
    # missing font - and on a fresh fedora-gaming00 that is exactly how it
    # looked until the two machines were compared.
    if [[ -x $REPO/bin/install-nerd-font.sh ]]; then
        note "Symbols Nerd Font, which Fedora does not package"
        "$REPO/bin/install-nerd-font.sh" || warn "the nerd font did not install - the bar will show empty boxes"
    else
        warn "bin/install-nerd-font.sh is missing - the bar will show empty boxes"
    fi

    # --- xwayland-satellite, held at 0.8.1 -----------------------------------
    #
    # A DOWNGRADE, DELIBERATELY, AND A LOCK TO KEEP IT. 0.8.2 tells an X11
    # override-redirect popup that the pointer left it about 35ms after it
    # maps, so every menu in every X11 application closes the instant it
    # opens. Steam is where it is unmissable - Steam, View, Friends, Games,
    # Help and every right-click are all unusable - but it is not a Steam bug
    # and not a bug in niri/rules.kdl's floating rule, which is what it looks
    # like from the outside.
    #
    #   https://github.com/Supreeeme/xwayland-satellite/issues/503
    #   https://github.com/niri-wm/niri/issues/4532
    #
    # Measured on fedora-gaming00: 0.8.2 broken, 0.8.1 fine, confirmed by
    # downgrading and restarting the session. Steam's own -system-composer
    # workaround was tried first and did nothing.
    #
    # THE LOCK IS THE IMPORTANT HALF. Without it the next `dnf upgrade` puts
    # 0.8.2 back and the menus break again weeks later, with nothing
    # connecting the two events.
    #
    # REMOVE ALL OF THIS when Fedora ships a build newer than 0.8.2 - the fix
    # is already in xwayland-satellite main. Leaving a package pinned to an old
    # version after the bug is fixed is its own kind of trap, so this block
    # only acts while the installed version is exactly 0.8.2.
    if [[ "$(rpm -q --qf '%{VERSION}' xwayland-satellite 2>/dev/null)" == "0.8.2" ]]; then
        note "holding xwayland-satellite at 0.8.1 - 0.8.2 breaks X11 menus"
        if dnf -y downgrade xwayland-satellite-0.8.1-1.fc44; then
            dnf versionlock add xwayland-satellite 2>/dev/null \
                || warn "could not lock it: a later dnf upgrade will undo this"
        else
            warn "the downgrade failed - X11 menus (Steam's especially) will not work"
            warn "see https://github.com/Supreeeme/xwayland-satellite/issues/503"
        fi
    fi

    # NO DISPLAY MANAGER, WHICH IS THE FRAMEWORK'S ARRANGEMENT. getty logs the
    # user in on tty1 and ~/.bash_profile - linked by bin/link-dotfiles.sh -
    # reads ~/.local/state/fd44-compositor and hands niri or Hyprland to uwsm.
    #
    # graphical.target STILL, NOT multi-user. The session is started by a shell
    # on tty1, but everything else about the machine is a graphical install, and
    # the user units the shell starts expect graphical-session.target to be
    # reachable.
    note "autologin on tty1, with no display manager"
    systemctl set-default graphical.target
    install -d /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<AUTOLOGIN
# Written by fd44_hyprdot install/fedora_desktop.sh --niri
#
# ExecStart IS CLEARED FIRST. A drop-in adds to ExecStart rather than replacing
# it, so without the empty assignment getty is started twice and the second one
# fails, which systemd reports as the unit failing even though the session is up.
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
AUTOLOGIN
    printf '  autologin as %s on tty1\n' "$TARGET_USER"
    systemctl disable sddm 2>/dev/null || true
else
    note "enabling the display manager"
    systemctl set-default graphical.target
    systemctl enable sddm
fi


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
if [[ $DESKTOP == plasma && -n ${SUDO_USER-} && $SUDO_USER != root ]]; then
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

# --- btrfs-patrol -------------------------------------------------------------
#
# ON A BTRFS MACHINE ONLY, and this one is only btrfs since the rebuild. It is
# this project's own tool and comes from its own COPR; `btrfs-patrol setup` is
# still a deliberate step afterwards, because creating the snapshot subvolume
# and editing fstab is not something to do to someone unasked.
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
    note "btrfs-patrol, from its COPR"
    dnf -y copr enable jccl1706/btrfs-patrol >/dev/null 2>&1 || true
    dnf -y install btrfs-patrol >/dev/null \
        && printf '  btrfs-patrol %s - run `sudo btrfs-patrol setup` when ready\n' \
               "$(rpm -q --qf '%{VERSION}' btrfs-patrol)" \
        || warn "btrfs-patrol did not install - check the COPR"
else
    note "not btrfs - skipping btrfs-patrol"
fi

printf '\n'
note "done"
printf '  %-12s %s\n' "packages" "$(rpm -qa | wc -l)"
printf '  %-12s %s\n' "root used" "$(df -h / | awk 'NR==2{print $3}')"
printf '\n'
warn "REBOOT NOW, and expect the first boot to take longer: akmod may rebuild."
warn "If it comes up to a black screen, the firmware menu still reaches NixOS."
