#!/usr/bin/env bash
#
# Guided Fedora 44 installer                               v1.13  2026-09-15
#   Btrfs + subvolumes  |  systemd-boot (UEFI)  |  optional LUKS2+LVM  |  hibernation
#   Hyprland + quickshell only  |  AMD (Framework 13)  |  laptop
#   No display manager: getty autologin + uwsm  |  Plymouth graphical boot
#
# Ported from install_arch_v3_3.sh. Same shape, same wizard/preflight/dry-run
# plumbing, same Btrfs subvolume scheme and hibernation/zram logic - but the
# desktop question is gone. This script only ever installs Hyprland with
# quickshell as the bar. If you want GNOME/KDE/niri or waybar, go back to the
# Arch script or add another branch yourself; this one is deliberately narrow.
#
# Changelog
#   v1.13 A SECOND LAPTOP: a ThinkPad T480 (Intel, two NVMe drives, one
#         holding a Debian install to keep).
#           - --disk accepts a stable path such as
#             /dev/disk/by-id/nvme-MODEL_SERIAL and resolves it before any
#             partition name is derived from it; nvme0n1/nvme1n1 can swap
#             between boots. The disk menu and the "About to ERASE" listing
#             show model and serial, and the dry run's closing "run it for
#             real" line repeats the stable path rather than the kernel name.
#           - GPU detection matched names, and "ati" is in "VGA compatible"
#             and "Intel Corporation": every machine detected as AMD. It now
#             reads the PCI class and vendor ID. It also runs in --unattended
#             installs, like the CPU, instead of defaulting to "amd".
#           - Outside the installer, the scripts it links stop assuming the
#             Framework: the charger is found by type (AC on a ThinkPad, ACAD
#             on the Framework), the lock screen sums every battery, and
#             hypr/monitors.lua scales each panel by its EDID make and model.
#   v1.12 RENAMED to install_fedora.sh: the file name no longer carries the
#         version, so the download link stops changing with every release.
#         The version lives in this header and in installer_version below.
#         Everything since v1.11, most of it found by living with the result:
#           - SECURITY. A machine without disk encryption locks the session at
#             login (bin/lock-at-login.sh) - autologin otherwise hands the
#             desktop to anyone who switches it on. The Chromium policy
#             directory stays root's, written by a sandboxed root service from
#             a validated request (bin/chromium-policy-setup.sh), instead of
#             being writable by the user. The default-password gate in
#             ~/.bash_profile cannot be skipped with Ctrl+C, the Nerd Font
#             download is pinned by sha256 and extracted without following
#             symlinks, and the install log is mode 600.
#           - NO WALLPAPER DAEMON. Quickshell draws the wallpaper
#             (quickshell/Wallpaper.qml); hyprpaper and swaybg are no longer
#             installed. The COPR's hyprpaper aborts on start.
#           - --desktop (no battery or lid, no encryption, no swap partition)
#             and --dotfiles URL.
#           - Configs linked from the dotfiles repo: kitty and wireplumber
#             join hypr and quickshell, and scripts are reached through
#             ~/.config/hypr rather than a hardcoded path.
#           - Packages: jetbrains-mono-fonts (kitty's font), libwebp-tools and
#             qt6-qtimageformats (the WebP wallpapers and previews),
#             python3-gobject (powerprofilesctl is a Python script); the
#             Symbols Nerd Font comes from the copy committed to the repo
#             instead of a download; nwg-panel is excluded (it installs itself
#             through Supplements: hyprland); playerctl is gone (quickshell
#             speaks MPRIS itself).
#           - The power button opens the power menu instead of shutting down,
#             and the install verifies that drop-in.
#           - Fixed: --dry-run, which the Chromium policy step broke; an empty
#             wallpaper picker on a fresh install; false statements in the
#             closing banner, and a command that ran inside it.
#   v1.11 THE INSTALLED MACHINE COULD NOT LOG IN. Two bugs, both found by
#         actually booting a VM install rather than by reading the script.
#           - The account's password was force-expired (shadow field 3 = 0) on
#             the belief that PAM would prompt for a change at first login. It
#             does not: agetty --autologin runs `login -f`, and pam_unix
#             REJECTS an expired password in account management with no
#             interactive dialog. login exited, systemd respawned getty, and
#             the machine looped forever - black screen, no shell, Hyprland
#             never started. The forced change now lives in ~/.bash_profile,
#             which runs after login succeeds and can actually prompt, and a
#             post-install check asserts the password is NOT expired.
#           - ~/.config/quickshell was never symlinked. Only hypr/ and
#             systemd/ were, so a dotfiles repo's bar, frame and launcher were
#             silently absent and the desktop came up bare.
#         Also: the Nerd Font installed in v1.10 landed owned by the uid
#         recorded in the upstream tarball (1001) rather than root, because
#         tar as root restores archived ownership. Fixed with --no-same-owner.
#   v1.10 The two fonts the quickshell config asks for by name. Both were
#         documented in the README and installed by neither the script nor
#         anything it pulls in, so a fresh install rendered the bar in the
#         wrong typeface with empty boxes where the icons should be - and
#         nothing reported an error, because a missing font is a silent
#         substitution rather than a failure.
#           - rsms-inter-vf-fonts, a plain Fedora package with no
#             dependencies of its own. NOTE it registers the family as
#             "Inter Variable", not "Inter"; asking for the latter silently
#             falls back to Noto Sans.
#           - Symbols Nerd Font, which Fedora does not package at all (the
#             only Nerd Font in the repos is a TeX one). Downloaded from the
#             upstream release as the symbols-only archive - ~2 MB rather
#             than ~50 MB for a patched family, and the glyphs are all that
#             is wanted since the text comes from Inter. This is the one
#             thing the script fetches from outside the distro repos, and it
#             is deliberately NON-FATAL: it warns and continues, because a
#             missing font costs you some icons and failing the install over
#             it - after the disk is already partitioned - would not.
#   v1.9  Brought in line with the machine this actually built. Three
#         changes, all from living with the result:
#           - NO DISPLAY MANAGER. sddm and greetd are both gone, along with
#             the login-manager wizard question. The session now starts from
#             a getty autologin on tty1 plus a `uwsm check may-start` hook in
#             ~/.bash_profile. SDDM was dropped because its Wayland greeter
#             runs under Weston, and Weston 15 does not implement
#             wp_cursor_shape_manager_v1 while Qt 6.11 wants it - so the
#             greeter had no mouse cursor and no amount of CursorTheme
#             configuration fixed it. Note the default target STAYS
#             graphical.target: most autologin guides say multi-user.target,
#             which breaks this, because `uwsm check may-start` requires
#             graphical.target to have been reached. Not installing a DM is
#             sufficient - display-manager.service is only Wanted by that
#             target, not Required.
#           - PLYMOUTH plus a quiet kernel cmdline (rhgb, loglevel=3,
#             systemd.show_status=false and the rd.* equivalents). Note
#             `quiet` alone does NOT suppress systemd's "[ OK ] Started ..."
#             lines - systemd.show_status=false is the one that does, and it
#             was the bulk of the text on screen. agetty also gets
#             --noissue --nohostname -n and, importantly, NOT --noclear:
#             --noclear is precisely what preserves leftover boot text.
#           - OPTIONAL DOTFILES. The wizard asks for a git URL; if given it
#             is cloned to ~/Work/<name>, ~/.config/hypr is symlinked at its
#             hypr/ directory, and any user units in its systemd/ directory
#             are linked and enabled. Blank skips all of it and the minimal
#             stock config written by this script stays.
#         Deliberately NOT included: RPM Fusion and mesa-va-drivers-freeworld.
#         They give H.264/HEVC hardware decode, but nothing is broken without
#         them and they mean a permanent third-party repo. Add by hand if you
#         want them.
#   v1.8  xorg-x11-server-Xwayland added to depacs. Same class of gap as
#         the v1.7 Wi-Fi bugs: nothing in the minimal --installroot pulls
#         it in, and Hyprland does NOT depend on it, so the installed
#         system could not run a single X11 application - no Xwayland
#         binary, no /tmp/.X11-unix socket, every X11 client just fails to
#         open a display. Easy to miss because Hyprland reports
#         `xwayland:enabled = true` and still advertises xwayland_shell_v1
#         to clients regardless, so the compositor looks correctly
#         configured while the binary behind it is simply absent.
#         Note Hyprland only spawns Xwayland at compositor startup, so on
#         an ALREADY-RUNNING session installing the package is not enough -
#         you have to log out and back in. On a fresh install from this
#         script that is moot, since it is present before first login.
#   v1.7  Wi-Fi fixed. Found by auditing a machine this script actually
#         built - it came up with NO working Wi-Fi at all, from two
#         independent causes, the second hidden behind the first:
#           - iwlwifi-mvm-firmware added to hwpacs. Fedora 44 SPLIT the
#             iwlwifi blobs out of linux-firmware into separate
#             iwlwifi-{mvm,mld,dvm}-firmware packages, so /usr/lib/firmware
#             had zero iwlwifi ucode and the AX210 never bound a driver
#             ("no suitable firmware found! iwlwifi-ty-a0-gf-a0-89 is
#             required"). NOTE this invalidates part of the v1.1 note below:
#             keeping weak deps is still right for amdgpu, but it no longer
#             covers iwlwifi, because the firmware is not a weak dep of
#             anything now - it has to be named explicitly. mvm is the
#             op_mode for the AX210 in this Framework 13; add mld/dvm only
#             if you ever put a different Intel card in.
#           - NetworkManager-wifi added to basepacs. Bare NetworkManager
#             has no Wi-Fi backend, so even once the firmware loaded, NM
#             logged "'wifi' plugin not available; creating generic device"
#             and left the radio permanently unmanaged. This subpackage
#             pulls wpa_supplicant in as a dependency. Invisible until the
#             firmware problem above was fixed first.
#         Also iproute added to basepacs - nothing in the minimal
#         --installroot pulls it in, so the installed system had no `ip`
#         command at all. Same class of gap as `tar` in v1.1.
#   v1.6  xdg-user-dirs added explicitly. It was only ever present as a
#         dependency pulled in by nautilus - creates ~/Downloads,
#         ~/Documents, ~/Pictures etc. at first login. Making it explicit
#         so those folders keep getting created even if nautilus is ever
#         dropped from a future install.
#   v1.5  intel-media-driver dropped from the Intel GPU branch (and from
#         check_repos()'s extras list) - same symptom as mesa-va-drivers in
#         v1.1: listed in Fedora's package index but unresolvable against
#         this live media's mirrors. Not required for the desktop to work;
#         confirm the real name yourself with `dnf5 search vaapi` if you
#         want Intel VAAPI acceleration.
#   v1.4  hyprland-guiutils added (Hyprland's own dialogs need it - "runtime
#         dependency for some dialogs" warning otherwise). Closing message no
#         longer assumes ~/.config/hypr/hyprland.conf - Hyprland 0.55 (April
#         2026) replaced the old hyprlang syntax with hyprland.lua by
#         default, and this COPR already tracks that; the message now says
#         to check which file actually exists rather than naming one.
#   v1.3  wofi/mako removed again (net installer default: no launcher, no
#         notification daemon, on request - was added back briefly in v1.2).
#   v1.2  wofi + mako added to depacs, undoing part of an earlier trim - a
#         desktop with no launcher and no notification daemon at all turned
#         out to be more friction than the disk-space savings were worth.
#   v1.1  Everything below came out of an actual install on the real
#         hardware, not a read-through - each was a genuine failure, not a
#         style choice:
#           - tar added to basepacs. Nothing in a minimal --installroot
#             pulls it in for free; the first post-install step that needed
#             it (extracting anything) failed with "tar: command not found".
#           - REMOVED --setopt=install_weak_deps=False from both dnf5 calls.
#             This was the single biggest bug: Fedora ships this Framework's
#             amdgpu AND iwlwifi firmware, and systemd's PAM/logind
#             integration, only as Recommends - stripping weak deps left
#             amdgpu unable to load ANY firmware ("Fatal error during GPU
#             init", permanent black screen at boot) and sddm-helper unable
#             to open a login session (no pam_systemd.so -> "could not open
#             seat"). Two independent fatal failures, one cause.
#           - dnf5 --use-host-config kept ONLY on the first --installroot
#             call, dropped on the second. That flag reads the LIVE
#             system's own repo list instead of the installroot's - correct
#             before fedora-release exists in $rootmnt (zero repos of its
#             own yet), wrong after (it would silently ignore the COPR repo
#             file already sitting in $rootmnt/etc/yum.repos.d, and desktop
#             packages would fail to resolve with no indication why).
#           - Package name fixes, each found by actually hitting it:
#             `systemd-boot` doesn't exist as a standalone package for a
#             plain non-Secure-Boot install (systemd-boot-unsigned has
#             bootctl and the EFI binaries) - dropped. `man-pages-overrides`
#             is RHEL-only -> `man-pages`. `sof-firmware` -> the real name
#             `alsa-sof-firmware`. `mesa-va-drivers` dropped entirely - Fedora
#             lists it but it was unresolvable against this live media's
#             mirrors, not required for the desktop to function.
#             `greetd-tuigreet` (the Arch package name) -> plain `tuigreet`
#             on Fedora.
#           - python3-pyxdg and python3-dbus added explicitly - the COPR's
#             uwsm RPM hard-imports both in its own Python code without
#             declaring them as dependencies; uwsm crashed with
#             ModuleNotFoundError the instant a session was started.
#           - check_repos() now tests the UNION of every wizard branch
#             (both login managers, both browsers, both GPU vendors), not
#             just whatever the config defaults resolve to. --check-repos
#             skips the wizard, so it was only ever validating the SDDM/
#             chromium/AMD path - the wrong tuigreet package name went
#             completely undetected by repeated --check-repos runs because
#             greetd was never the path actually being checked.
#           - "hyprland-uwsm session entry" verification check fixed to
#             accept EITHER /usr/share/wayland-sessions (if the COPR's own
#             package already ships one - it does) or the script's
#             /usr/local/share fallback. Was a false FAIL on a system that
#             was actually fine.
#           - LVM deactivation (`vgchange -an`) added before `cryptsetup
#             close` in the pre-partition cleanup. A previous interrupted
#             run leaves the old LUKS+LVM stack unmounted but still ACTIVE
#             at the device-mapper level; closing LUKS while the LVM VG on
#             top of it is still active silently no-ops, and the next
#             luksFormat then fails right after the passphrase prompt with
#             no visible error.
#           - Logging/exit-trap rewritten. `exec > >(tee -a "$logfile")`
#             runs tee as a background process - if the script exits
#             abruptly, bash does not wait for that background process to
#             flush before the parent shell regains control, so `die()`'s
#             own error message could be silently lost in the race. Fixed
#             with a single on_exit trap that restores the original
#             stdout/stderr and explicitly waits for tee before the process
#             actually ends. (This one cost real time - it looked like a
#             silent kill/systemd-oomd for several attempts before the
#             actual cause turned out to be this logging race the whole
#             time.)
#           - chroot bind mounts switched from plain `--bind` to
#             `--rbind` + `--make-rslave` for /dev and /sys, so submounts
#             (devpts, efivars, etc.) are actually visible inside the
#             chroot, not just the top-level mountpoint.
#           - `.autorelabel` added. Every config file this script writes
#             directly (fstab, sudoers, hypridle/hyprlock, zram, dracut,
#             greetd) bypasses rpm's normal SELinux labeling.
#           - check_live_tools() added: Fedora's live media does not ship
#             sgdisk/gdisk by default (the Arch ISO does) - checked and
#             installed on the LIVE system, before any partitioning, instead
#             of failing mid-`Creating partitions` with a bare command-not-
#             found and nothing else printed.
#           - preflight now warns if systemd-oomd is active, with the mask
#             command right there - a real, if ultimately not the actual,
#             suspect chased during this same debugging session.
#   v1.0  Initial Fedora port of install_arch_v3_3.sh.
#
# Usage:
#   ./install_fedora.sh                 guided install (asks everything)
#   ./install_fedora.sh --preflight     report on this machine, change nothing
#   ./install_fedora.sh --check-repos   resolve every package name against the
#                                             real repos (incl. the Hyprland COPR),
#                                             change nothing, no root needed
#   ./install_fedora.sh --dry-run       ask, then print every command, touch nothing
#   ./install_fedora.sh --unattended    no prompts, use the config block below
#   ./install_fedora.sh --unattended -y skip the countdown too
#   ./install_fedora.sh --desktop       no battery, no lid: machine=desktop,
#                                             no disk swap, no encryption, zram on
#   ./install_fedora.sh --dotfiles URL  clone this repo and link its configs
#
# Recommended first run:  --check-repos, then --preflight, then --dry-run, then for real.
# Run this from a Fedora live/rescue environment (Fedora Everything netinst
# or Server DVD booted to a shell both work; Workstation live also works).
#
# WHAT CHANGED PORTING FROM ARCH, AND WHY
#
#   Bootloader: Limine -> systemd-boot.
#     Fedora's kernel package already writes Boot Loader Specification (BLS)
#     entries on every kernel install/update via
#     /usr/lib/kernel/install.d/90-loaderentry.install (part of systemd) and
#     dracut's own install.d hook - this happens regardless of which
#     bootloader consumes those entries. So "switch to systemd-boot" is
#     mostly just: install the `systemd-boot-unsigned` package (there is no
#     separate signed `systemd-boot` package for a plain non-Secure-Boot
#     install - `bootctl` and the EFI binaries both live in `-unsigned`),
#     run `bootctl install`,
#     and make sure grub2 is never installed to the ESP. No config file is
#     hand-written the way limine.conf was - entries under
#     /boot/loader/entries/ are generated by kernel-install itself, and this
#     script calls `kernel-install add` explicitly after pacstrapping instead
#     of trusting RPM scriptlets alone (dnf --installroot runs scriptlets
#     chrooted, which usually works, but a script that changes your disk
#     shouldn't leave the bootability check implicit).
#
#   initramfs: mkinitcpio -> dracut.
#     dracut's default hostonly mode inspects the actual block devices under
#     the target root (LUKS, LVM, Btrfs) and pulls in the right modules on
#     its own - there is no HOOKS array to assemble by hand the way
#     mkinitcpio needed one. Microcode is handled the same way: installing
#     `microcode_ctl` is enough, dracut folds it into the initramfs itself;
#     unlike Limine there is no separate module_path line to write.
#
#   Package manager: pacman/pacstrap -> dnf5 --installroot.
#     dnf5 --installroot bootstraps a target root much like pacstrap does,
#     but Fedora's repo metadata (and RPM Fusion, and the Hyprland COPR) has
#     to be reachable from inside that installroot, which is why the repo
#     files below get written into $rootmnt/etc/yum.repos.d BEFORE the
#     desktop package set is pulled - the same spot in the flow where the
#     Arch script flipped on [multilib] mid-script.
#
#   Desktop packaging: Hyprland is NOT in Fedora's official repos for
#     Fedora 43/44 (it shipped officially only through Fedora 42, then was
#     dropped). quickshell was never in the official repos either. Both are
#     pulled from a third-party COPR (nett00n/hyprland, chosen because as of
#     writing it actively builds both hyprland AND quickshell against
#     Fedora 43/44/45, where several other Hyprland COPRs have gone stale).
#     THIS IS A THIRD-PARTY REPO YOU ARE TRUSTING - verify it still looks
#     maintained before you run this for real:
#       https://copr.fedorainfracloud.org/coprs/nett00n/hyprland/
#     If it has gone stale, swap $hypr_copr below for whatever COPR is
#     current; everything else in this script is COPR-agnostic.
#
#   LUKS/LVM cmdline: cryptdevice=...  ->  rd.luks.uuid=... rd.lvm.lv=...
#     dracut's own kernel-cmdline syntax, not mkinitcpio's.
#
#   Nvidia: dropped entirely. This script targets a Framework 13 AMD, which
#     has no discrete GPU to drive - the RPM Fusion nonfree add-on, the
#     akmod-nvidia branch, the nouveau blacklist and the
#     suspend/hibernate/resume unit wiring that the Arch script needed for
#     Nvidia are all gone rather than carried as dead branches. GPU support
#     is just the AMD path: mesa's RADV Vulkan driver and the in-kernel amdgpu
#     driver, both already covered by the base package set.
#
#   Btrfs subvolume layout: switched to Fedora's OWN Anaconda convention
#     instead of the Arch script's @-prefixed set. That convention is just
#     two subvolumes, named "root" and "home" (no @, no /opt, /srv, /var/log,
#     /var/cache, or /var/lib/libvirt/images split out, no snapshots
#     subvolume) - because Fedora does not wire up automatic snapshotting
#     the way openSUSE does with snapper, those extra subvolumes bought
#     nothing here beyond bookkeeping. The other Fedora-native detail this
#     copies: root is mounted via `btrfs subvolume set-default`, not a
#     `subvol=root` mount option - which is why fstab's root line below has
#     no subvol= on it and the kernel cmdline has no rootflags=subvol=
#     either, matching a stock Fedora installer's own fstab exactly. /home
#     is still the one explicit subvol=home mount, same as Anaconda does it.
#     If you want /var/log, /var/cache or libvirt's image store nocow and
#     snapshot-excluded later, that is a `btrfs subvolume create` + fstab
#     edit any time after install - it does not need to happen now.
#
#   sudo group: unchanged. Fedora's install-time admin group is also `wheel`.
#
# NOTE ON PASSPHRASES
#   The LUKS passphrase is never stored: cryptsetup prompts for it on the
#   console when the script runs. The user login password is the hash in the
#   config block below - regenerate it with `mkpasswd -m sha-512` (or
#   `openssl passwd -6` if mkpasswd is not on your live media).
#
set -Eeuo pipefail

# Shown in the wizard's banner and the preflight report. Bump it together
# with the header at the top of this file.
installer_version="v1.13"

###############################################################################
# Config - these are the DEFAULTS. Interactive mode offers them as defaults
# and lets you change them; --unattended uses them verbatim.
###############################################################################
target="/dev/nvme0n1"          # WHOLE DISK - it will be wiped
esp_size="1024M"
swap_size="32G"                # or "none" for no swap and no hibernation
# zram is compressed swap in RAM: a pressure valve, NOT a hibernation target.
# Independent of swap_size. Empty = no zram. Otherwise a zram-generator size
# expression in MB, e.g. "min(ram / 2, 4096)" or "ram / 2".
zram_size=""
encrypt="yes"                  # yes | no
machine="laptop"               # laptop | desktop
cpu_vendor=""                  # amd | intel   (empty = autodetect)
gpu_vendor=""                  # amd | intel   (empty = autodetect)
# Login manager. Empty = sddm (Hyprland has no GNOME/KDE session to derive a
# default from here, unlike the Arch script). sddm | greetd
# Dotfiles git URL. Left blank the installer sets up autologin and Plymouth
# but writes only a minimal Hyprland config; supply a repo and it is cloned to
# ~/Work/<name> and ~/.config/hypr is symlinked into it instead.
dotfiles_repo=""
browser="chromium"             # chromium | firefox
terminal="kitty"

releasever="44"
# Third-party COPR providing hyprland + quickshell for Fedora 43/44/45.
# CHECK THIS IS STILL MAINTAINED before a real install - see the note above.
hypr_copr="nett00n/hyprland"

rootmnt="/mnt"
locale="en_US.UTF-8"
keymap="us"
timezone="America/New_York"
hostname="fedora-hypr"
username="jc"

# SHA-512 crypt hash for the user account.
#
# This is the hash of the literal password "changeme", and it is PUBLIC - this
# repository is public, so treat it as known to everyone.
#
# That is safe only because ~/.bash_profile refuses to start a session until
# the password has actually been changed - see the profile written near the
# end of this script. Do not remove that gate while this default is in place.
#
# NOTE it is enforced there, in the profile, and NOT by expiring the password:
# an expired password breaks autologin entirely. There is a long comment where
# the account is created explaining exactly how.
#
# To ship your own instead:   mkpasswd -m sha-512
#
# Inside double quotes every $ must be backslash-escaped, e.g.
#   user_password="\$6\$somesalt\$somehash..."
user_password="\$6\$zcrn5YwbNeft2Sd8\$3CdRbMzCFs0l6NjjWHTzpGD9X6snAgShzQePocq9OJ9CuiPtvvvLdGu3Y8ic6tuSdyOo3aAyuANcgLW2iwAEu."

luks_label="CRYPTROOT"
vg_name="vg0"
mapper_name="cryptlvm"

btrfs_opts="noatime,compress=zstd:1,space_cache=v2"

###############################################################################
# Plumbing
###############################################################################
DRY=0; ASSUME_YES=0; PREFLIGHT_ONLY=0; UNATTENDED=0; CHECK_REPOS=0; DESKTOP=0

log()  { printf '\n\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  {
    printf '\n\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2
    [[ -n "${logfile-}" ]] && printf '    full log: %s\n' "$logfile" >&2
    exit 1
}
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

run() {
    if (( DRY )); then
        local a out=""
        for a in "$@"; do
            if [[ -z "$a" || "$a" == *[[:space:]]* ]]; then out+=" '$a'"; else out+=" $a"; fi
        done
        printf '   \033[2m|\033[0m%s\n' "$out"
        return 0
    fi
    "$@"
}
runsh() {
    if (( DRY )); then printf '   \033[2m|\033[0m %s\n' "$1"; return 0; fi
    eval "$1"
}
writefile() {
    local mode="$1" path="$2" content
    content="$(cat)"
    if (( DRY )); then
        printf '   \033[2m|\033[0m write %s (%s)\n' "$path" "$mode"
        return 0
    fi
    install -Dm"$mode" /dev/null "$path"
    printf '%s' "$content" > "$path"
}

have_tty() { [[ -e /dev/tty ]] && exec 3<>/dev/tty 2>/dev/null; }

menu() {   # menu "Question" default_index "Label|value" ...
    local prompt="$1" def="$2"; shift 2
    local -a labels=() values=()
    local i=0 opt
    for opt in "$@"; do
        i=$((i+1))
        labels+=("${opt%%|*}")
        values+=("${opt#*|}")
    done
    printf '\n\033[1m%s\033[0m\n' "$prompt" >/dev/tty
    for ((i=0; i<${#labels[@]}; i++)); do
        printf '  %s%d) %s\n' "$( (( i+1 == def )) && echo '* ' || echo '  ' )" "$((i+1))" "${labels[i]}" >/dev/tty
    done
    local a
    while true; do
        printf '  choice [\033[2m%s\033[0m]: ' "$def" >/dev/tty
        read -r a </dev/tty || a=""
        [[ -z "$a" ]] && a="$def"
        if [[ "$a" =~ ^[0-9]+$ ]] && (( a >= 1 && a <= ${#values[@]} )); then
            printf '%s' "${values[a-1]}"
            return 0
        fi
        printf '  enter a number from 1 to %d\n' "${#values[@]}" >/dev/tty
    done
}

ask_text() {   # ask_text "Question" "default"
    local prompt="$1" def="$2" a
    printf '\n\033[1m%s\033[0m [\033[2m%s\033[0m]: ' "$prompt" "$def" >/dev/tty
    read -r a </dev/tty || a=""
    printf '%s' "${a:-$def}"
}

###############################################################################
# Argument parsing
###############################################################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)     DRY=1 ;;
        -p|--preflight)   PREFLIGHT_ONLY=1 ;;
        -c|--check-repos) CHECK_REPOS=1 ;;
        -u|--unattended)  UNATTENDED=1 ;;
        -y|--yes)         ASSUME_YES=1 ;;
        -d|--disk)        target="${2:?--disk needs an argument}"; shift ;;
        --desktop)        DESKTOP=1 ;;
        --dotfiles)       dotfiles_repo="${2:?--dotfiles needs a git URL}"; shift ;;
        -h|--help)        awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
        *)                die "unknown option: $1  (try --help)" ;;
    esac
    shift
done

# --desktop: the four config values that differ on a machine with no battery
# and no lid. Applied AFTER parsing so an explicit --disk still wins, and
# before the wizard so its defaults are the desktop ones.
#
# These are not arbitrary. A desktop has nothing to hibernate for, so disk
# swap buys only a 32G hole; zram gives the pressure valve instead, capped
# because it costs real RAM to hold compressed pages. Encryption is left off
# because a machine that never leaves the house gains little from a passphrase
# it must be present to type - turn it back on with the wizard if that is not
# your threat model.
#
# The machine type would be DETECTED correctly anyway - detect_machine() looks
# for a battery - but detection only reaches the wizard's default, and an
# unattended install never runs the wizard. This is what makes --unattended
# usable on a desktop without editing the file.
if (( DESKTOP )); then
    machine="desktop"
    swap_size="none"
    encrypt="no"
    zram_size="min(ram / 2, 8192)"
fi

(( DRY )) || (( PREFLIGHT_ONLY )) || (( CHECK_REPOS )) || [[ $UID -eq 0 ]] || die "This script needs to be run as root."

logfile=""
tee_pid=""
if (( ! DRY )) && (( ! PREFLIGHT_ONLY )) && (( ! CHECK_REPOS )); then
    logfile="/tmp/fedora-install.log"
    exec 3>&1 4>&2
    exec > >(tee -a "$logfile") 2>&1
    tee_pid=$!
fi

# Single EXIT trap for the whole script (bash only honors the LAST one set,
# so this has to cover everything, not just logging).
#
# `exec > >(tee ...)` above runs tee as a background process reading from a
# pipe. If the script exits abruptly - a real error, not just reaching the
# end - bash does NOT wait for that background tee to finish flushing its
# buffered output before the parent shell regains control. The actual error
# message from `die` can be lost in that race, leaving nothing but a bare
# exit code with no explanation - which is exactly what happened chasing an
# earlier failure in this script's history: it was never a silent kill,
# `die` was firing correctly the whole time, its message just never made it
# out before the process ended.
on_exit() {
    # Tear down chroot bind mounts, if that helper exists yet and was ever
    # used - declare -F guards against firing before it's been defined,
    # since an early failure can trigger this trap before later parts of
    # the script have run.
    declare -F umount_chroot >/dev/null && umount_chroot
    if [[ -n "$tee_pid" ]]; then
        exec 1>&3 2>&4 3>&- 4>&-
        wait "$tee_pid" 2>/dev/null || true
    fi
}
trap on_exit EXIT

###############################################################################
# Hardware autodetection
###############################################################################
detect_cpu() { grep -qm1 AuthenticAMD /proc/cpuinfo && echo amd || echo intel; }
detect_gpu() {
    # By PCI CLASS and VENDOR ID, not by name. Matching names found "ati" in
    # "VGA compatible" and "Intel Corporation", and "3D" in a bus address
    # (3d:00.0, an NVMe drive), so every machine detected as AMD - a ThinkPad
    # T480 with only Intel graphics included. Classes 0300 VGA, 0302 3D,
    # 0380 display; vendors 1002 AMD, 8086 Intel. AMD first, as before, for a
    # machine with both.
    local gpus; gpus="$(lspci -nn 2>/dev/null | grep -E '\[03(00|02|80)\]' || true)"
    if   grep -q '\[1002:' <<<"$gpus"; then echo amd
    elif grep -q '\[8086:' <<<"$gpus"; then echo intel
    else detect_cpu; fi
}
detect_machine() {
    if [[ -d /sys/class/power_supply ]] && compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
        echo laptop
    else
        echo desktop
    fi
}

[[ -n "$cpu_vendor" ]] || cpu_vendor="$(detect_cpu)"
[[ -n "$gpu_vendor" ]] || gpu_vendor="$(detect_gpu)"

ram_bytes=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) * 1024 ))
ram_gib=$(( ram_bytes / 1024 / 1024 / 1024 ))

###############################################################################
# The wizard
###############################################################################
wizard() {
    have_tty || die "no terminal available for the guided install - use --unattended"

    {
        printf '\n\033[1;36m'
        printf '  ┌──────────────────────────────────────────────┐\n'
        printf '  │  Fedora 44 + Hyprland guided install   %-5s │\n' "$installer_version"
        printf '  └──────────────────────────────────────────────┘\n'
        printf '\033[0m'
        printf '  Press Enter to accept the default shown for each question.\n'
        printf '  Desktop is fixed: Hyprland + quickshell, systemd-boot.\n'
    } >/dev/tty

    # ---- disk ----------------------------------------------------------
    local -a diskopts=()
    local name size rest n=0 defdisk=1
    while read -r name size rest; do
        [[ "$name" =~ ^(zram|loop|sr) ]] && continue
        n=$((n+1))
        diskopts+=("/dev/$name   $size   ${rest:-unknown model}|/dev/$name")
        [[ "/dev/$name" == "$target" ]] && defdisk=$n
    # SERIAL too: two drives of the same model are otherwise the same line.
    done < <(lsblk -dno NAME,SIZE,MODEL,SERIAL 2>/dev/null)
    (( ${#diskopts[@]} )) || die "no disks found to install to"
    target="$(menu "Which disk should be WIPED and installed to?" "$defdisk" "${diskopts[@]}")"

    # ---- swap ----------------------------------------------------------
    local suggested="${ram_gib}G"
    swap_size="$(menu "Swap size?  (hibernation needs swap; RAM is ${ram_gib}G)" 2 \
        "none - no swap, no hibernation|none" \
        "${suggested} - matches RAM, hibernation always works|${suggested}" \
        "$(( (ram_gib + 1) / 2 ))G - half of RAM, usually enough|$(( (ram_gib + 1) / 2 ))G" \
        "8G|8G" "16G|16G" "32G|32G" \
        "custom|CUSTOM")"
    if [[ "$swap_size" == CUSTOM ]]; then
        swap_size="$(ask_text "Swap size (e.g. 24G)" "${suggested}")"
    fi

    # ---- zram ------------------------------------------------------------
    local zdef=1
    [[ "$swap_size" == none ]] && zdef=2
    zram_size="$(menu "Add zram?  (compressed swap in RAM - relieves memory pressure, cannot hibernate)" "$zdef" \
        "No zram|" \
        "Yes - up to 4G  (min(ram/2, 4096))|min(ram / 2, 4096)" \
        "Yes - up to 8G  (min(ram/2, 8192))|min(ram / 2, 8192)" \
        "Yes - half of RAM, uncapped|ram / 2")"

    # ---- encryption ------------------------------------------------------
    encrypt="$(menu "Full disk encryption?" "$( [[ $encrypt == yes ]] && echo 1 || echo 2 )" \
        "Yes - LUKS2 container holding an LVM group (recommended for laptops)|yes" \
        "No  - plain partitions, no passphrase at boot|no")"

    # ---- machine type ------------------------------------------------------
    local defmachine; defmachine="$(detect_machine)"
    machine="$(menu "Machine type?  (detected: $defmachine)" "$( [[ $defmachine == laptop ]] && echo 1 || echo 2 )" \
        "Laptop - power profiles, backlight, lid suspend/hibernate|laptop" \
        "Desktop - none of the battery/lid handling|desktop")"

    # ---- cpu ---------------------------------------------------------------
    local defcpu; defcpu="$(detect_cpu)"
    cpu_vendor="$(menu "CPU vendor?  (detected: $defcpu)" "$( [[ $defcpu == amd ]] && echo 1 || echo 2 )" \
        "AMD   - microcode_ctl picks it up automatically|amd" \
        "Intel - microcode_ctl picks it up automatically|intel")"

    # ---- gpu -----------------------------------------------------------
    local defgpu; defgpu="$(detect_gpu)" ; local gnum=1
    case "$defgpu" in amd) gnum=1 ;; intel) gnum=2 ;; esac
    gpu_vendor="$(menu "Graphics?  (detected: $defgpu)" "$gnum" \
        "AMD    - mesa, RADV Vulkan|amd" \
        "Intel  - mesa, ANV Vulkan, iHD VAAPI|intel")"

    # ---- dotfiles --------------------------------------------------------
    # There is no login-manager question any more: this installer always sets
    # up getty autologin on tty1 plus uwsm, with no display manager at all.
    dotfiles_repo="$(ask_text "Dotfiles git URL (blank = skip)" "$dotfiles_repo")"

    # ---- apps ----------------------------------------------------------
    browser="$(menu "Browser?" "$( [[ $browser == chromium ]] && echo 1 || echo 2 )" \
        "Chromium|chromium" "Firefox|firefox")"

    # ---- identity ------------------------------------------------------
    hostname="$(ask_text "Hostname" "$hostname")"
    username="$(ask_text "Username" "$username")"
    timezone="$(ask_text "Timezone" "$timezone")"
}

# A STABLE DISK PATH IS ALLOWED, and on a machine with two NVMe drives it is
# the safe way to name the one to wipe: nvme0n1 and nvme1n1 are handed out in
# probe order and can swap between boots. Seen on a ThinkPad T480 with a
# Debian install on one drive to keep and an empty one to install to.
#
# But partition names are built from the kernel name (partdev: nvme0n1 ->
# nvme0n1p1), and /dev/disk/by-id/nvme-MODEL_SERIAL spells its partitions
# -part1 - so "...SERIALp1" would not exist. Resolve the link once, before
# anything derives a name from it.
#
# BEFORE THE WIZARD, not after: its disk menu preselects the entry equal to
# $target, and compares /dev/NAME. With the link still unresolved nothing
# matched, the default fell to entry 1 - on the T480 the Ventoy USB stick the
# live system was running from - and pressing Enter would have wiped it.
if [[ -L "$target" ]]; then
    target_given="$target"
    target="$(readlink -f "$target")"
    log "Disk $target_given is $target"
fi

(( UNATTENDED )) || (( PREFLIGHT_ONLY )) || (( CHECK_REPOS )) || wizard

# A different disk picked in the wizard makes the stable path stale - it must
# not reappear in the dry run's "run it for real" line.
if [[ -n "${target_given:-}" && "$(readlink -f "$target_given")" != "$target" ]]; then
    unset target_given
fi

###############################################################################
# Derived values
###############################################################################
[[ "$swap_size" == "none" ]] && want_swap=no || want_swap=yes

partdev() {
    case "$target" in
        *nvme*|*mmcblk*|*loop*) printf '%sp%s' "$target" "$1" ;;
        *)                      printf '%s%s'  "$target" "$1" ;;
    esac
}
esppart="$(partdev 1)"
if [[ "$encrypt" == yes ]]; then
    cryptpart="$(partdev 2)"
    mapperdev="/dev/mapper/$mapper_name"
    rootdev="/dev/$vg_name/root"
    swapdev="/dev/$vg_name/swap"
else
    if [[ "$want_swap" == yes ]]; then
        swapdev="$(partdev 2)"; rootdev="$(partdev 3)"
    else
        swapdev=""; rootdev="$(partdev 2)"
    fi
fi

# No display manager. The session starts from a getty autologin on tty1 that
# execs uwsm from the user's shell profile - see the "Autologin" section far
# below. SDDM and greetd were both dropped in v1.9.

###############################################################################
# Package sets
###############################################################################
basepacs=(
    fedora-release
    kernel kernel-core kernel-modules kernel-modules-extra
    linux-firmware microcode_ctl
    btrfs-progs
    systemd-boot-unsigned efibootmgr dracut
    NetworkManager NetworkManager-wifi
    iproute
    sudo nano vim-enhanced git
    # shadow-utils provides useradd/usermod/groupadd/chpasswd. It is NOT pulled
    # in by anything else in this list: until v1.9 it arrived only as an sddm
    # dependency, so removing the display manager silently took it with it and
    # the install died at "chroot: failed to run command 'useradd'". Explicit
    # now. (The same trap bit this on a real machine when sddm was removed
    # post-install - it needed `dnf mark user shadow-utils` to survive.)
    shadow-utils
    man-db man-pages texinfo
    dnf5-plugins
    zstd tar
    glibc-langpack-en
)
[[ "$encrypt" == yes ]] && basepacs+=(cryptsetup lvm2)
[[ -n "$zram_size" ]] && basepacs+=(zram-generator-defaults)

hwpacs=(
    iwlwifi-mvm-firmware
    alsa-sof-firmware alsa-utils
    pipewire pipewire-alsa pipewire-pulseaudio pipewire-jack-audio-connection-kit wireplumber
    mesa-libGL mesa-vulkan-drivers mesa-libgbm
    bluez bluez-tools
    usbutils pciutils
)
if [[ "$machine" == laptop ]]; then
    # python3-gobject is for powerprofilesctl, NOT for anything here directly.
    # That CLI is a Python script - `from gi.repository import Gio, GLib` - and
    # power-profiles-daemon declares only the C libraries it links against, not
    # the Python bindings its own command-line tool imports. So the daemon
    # installs, the CLI is present, and every call fails with
    # ModuleNotFoundError until something else happens to pull the bindings in.
    #
    # On the development machine something did: nwg-panel. Removing that
    # unwanted package silently broke the AC/battery power policy, and the
    # breakage was invisible to any search of this repository, because nothing
    # here imports gi - powerprofilesctl does. Third package in one day found
    # to be surviving on someone else's weak dependency.
    hwpacs+=(power-profiles-daemon python3-gobject brightnessctl fwupd upower)
fi
case "$gpu_vendor" in
    # RADV Vulkan comes from mesa-vulkan-drivers above - that's what
    # actually matters for Hyprland/quickshell rendering. VAAPI hardware
    # video decode is left out for BOTH vendors: mesa-va-drivers (AMD) and
    # intel-media-driver (Intel) both showed the same symptom under
    # --check-repos - listed in Fedora's own package index, but
    # unresolvable against this live media's current mirrors, which
    # suggests a mirror sync lag rather than either name being wrong.
    # Neither is required for the desktop to work. Once installed, confirm
    # the real name with `dnf5 search vaapi` (or `mesa-va`/`intel-media` for
    # the specific vendor) and add it if you want accelerated video decode.
    amd)    : ;;
    intel)  hwpacs+=(libva-utils) ;;
esac

# Hyprland + quickshell only. uwsm is REQUIRED here for the same reason it
# was on Arch: Hyprland launched from a .desktop entry never starts
# graphical-session.target on its own, so the polkit agent would be enabled
# but never actually run.
#
# python3-pyxdg and python3-dbus are listed explicitly because the COPR's
# uwsm RPM doesn't declare them as dependencies even though uwsm's own code
# hard-imports both (uwsm/main.py imports xdg.BaseDirectory, uwsm/dbus.py
# imports dbus) - without them uwsm crashes with ModuleNotFoundError the
# instant you try to start a session, discovered by actually running it
# rather than by anything dnf could have caught. If a future COPR update
# still crashes on a DIFFERENT missing module, the fix is the same: find
# the module name in the traceback, `sudo dnf5 install python3-<name>`.
depacs=(
    hyprland uwsm quickshell qt6-qtwayland
    xorg-x11-server-Xwayland
    python3-pyxdg python3-dbus
    # No wallpaper daemon: quickshell draws the wallpaper itself
    # (quickshell/Wallpaper.qml). hyprpaper used to, with swaybg as a fallback
    # because hyprpaper 0.8.4 aborted on startup inside libhyprtoolkit's wl_seat
    # handler - and the COPR's current build does that on every machine tried.
    hyprlock hypridle hyprpolkitagent xdg-desktop-portal-hyprland
    hyprland-guiutils
    wl-clipboard cliphist grim slurp
    nautilus gvfs file-roller xdg-user-dirs
    xdg-desktop-portal xdg-desktop-portal-gtk
    google-noto-sans-mono-fonts

    # The quickshell bar asks for this by name (Theme.font). Without it
    # fontconfig silently substitutes Noto Sans and the bar merely looks
    # slightly wrong, which is harder to notice than an outright failure.
    #
    # NOTE the family is "Inter Variable", NOT "Inter" - this package
    # registers the variable font under that name, and asking for plain
    # "Inter" falls back. Check with: fc-match "Inter Variable"
    #
    # Pulls nothing: noarch, no dependencies of its own.
    rsms-inter-vf-fonts

    # kitty asks for "JetBrains Mono" by name (kitty/kitty.conf). Same class
    # of gap as Inter: named in a config, installed by nothing, and a miss is
    # a silent fallback to the default mono font rather than an error.
    # Pulls nothing: noarch, no dependencies of its own.
    jetbrains-mono-fonts

    # A serif, and metric-compatible stand-ins for the fonts web pages name.
    # Without them NO serif font is installed at all, and fontconfig's answer
    # for "serif" - and for Times New Roman, Georgia and Times - is Adwaita
    # Mono: a MONOSPACE font. Chromium's default standard font is Times New
    # Roman, so every page that does not set its own font rendered in a
    # typewriter face, and Arial/Courier New pages got Noto with different
    # widths. Found on the desktop, reading pages in Chromium.
    #   google-noto-serif-vf-fonts  the serif itself (2 MB)
    #   liberation-{sans,serif,mono}-fonts  same metrics as Arial, Times New
    #                               Roman and Courier New, so layouts built
    #                               around those do not reflow (4 MB)
    # All noarch, no dependencies of their own. The three Liberation packages
    # are named directly rather than through the liberation-fonts metapackage.
    google-noto-serif-vf-fonts
    liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts

    # cwebp/dwebp, used by bin/wallpaper.sh to build the picker's preview
    # thumbnails. Without it `wallpaper.sh thumbs` dies on every login and the
    # picker has no previews to show - which is how a VM install came up with
    # an empty wallpaper picker despite the wallpapers being cloned correctly.
    # 289 KB, and everything it needs (libwebp) is already pulled in.
    libwebp-tools

    # Qt's WebP decoder (libqwebp.so). The wallpapers are .webp and so are the
    # picker's previews, and quickshell draws both - without this plugin it
    # logs "Unsupported image format" for every one of them, the desktop is a
    # plain background colour and the picker shows empty tiles. Nothing in the
    # Qt or quickshell stack requires or recommends it: the laptop only had it
    # as someone else's dependency, and the gaming desktop's fresh install came
    # up with an empty picker.
    # 446 KB, plus jasper-libs, libmng and cmake-filesystem (~0.9 MB) for its
    # other formats; the version is locked to qt6-qtbase, so it never pulls a
    # different Qt.
    qt6-qtimageformats
)
# Plymouth: graphical boot splash, and a graphical LUKS passphrase prompt
# instead of the bare text one. plymouth-system-theme pulls the bgrt theme,
# which shows the firmware logo (on a Framework, the Framework logo).
depacs+=(plymouth plymouth-system-theme)

apppacs=("$browser" "$terminal" dejavu-sans-fonts google-noto-fonts-common google-noto-emoji-fonts)

###############################################################################
# Repo check
#
# Resolves every package name this run COULD install - the union of every
# wizard branch, not just whatever the current defaults resolve to (see the
# note inside check_repos() for why that distinction matters) - against the
# real repo metadata (default Fedora repos plus the Hyprland/quickshell
# COPR), without touching any disk and without root. This is what catches a renamed COPR
# package or a typo'd name BEFORE the target disk has already been wiped,
# instead of discovering it mid-transaction during the real install.
#
# It does NOT catch: a repo that resolves the name but is actually broken
# (bad build, missing deps at install time), or a COPR that has gone stale
# in ways short of removing the package entirely. It only proves the name
# exists somewhere reachable right now.
###############################################################################
check_repos() {
    log "Checking repos - resolving every package name, no changes made"
    local tmp_cache; tmp_cache="$(mktemp -d)"
    trap 'rm -rf "$tmp_cache"' RETURN
    local copr_baseurl="https://download.copr.fedorainfracloud.org/results/${hypr_copr}/fedora-\$releasever-\$basearch/"

    # --check-repos skips the wizard (same as --preflight), so basepacs/
    # hwpacs/depacs/apppacs at this point only reflect whatever the config
    # DEFAULTS resolve to (sddm, chromium, amd GPU, ...) - never whichever
    # branch you'd actually pick if you answered the questions. A check
    # that only covers the default path gives false confidence on every
    # other one, which is exactly how the wrong "greetd-tuigreet" package
    # name went undetected here despite this check passing repeatedly:
    # greetd was never the resolved $dm during a --check-repos run, so its
    # packages were never in the list being tested. The extras[] below are
    # every package that ONLY appears down a non-default wizard branch,
    # added explicitly so this check covers the union of every choice, not
    # just today's defaults.
    local -a extras=(
        chromium firefox                              # both browsers
        libva-utils                                    # Intel GPU branch
    )
    local -a allpkgs=("${basepacs[@]}" "${hwpacs[@]}" "${depacs[@]}" "${apppacs[@]}" "${extras[@]}")
    local -A seen=()
    local -a uniq=() missing=()
    local p result found=0

    for p in "${allpkgs[@]}"; do
        [[ -n "${seen[$p]-}" ]] && continue
        seen[$p]=1
        uniq+=("$p")
    done

    for p in "${uniq[@]}"; do
        result="$(dnf5 --setopt="cachedir=$tmp_cache" --releasever "$releasever" \
                       --repofrompath="hyprcheck,$copr_baseurl" \
                       repoquery --quiet "$p" 2>/dev/null || true)"
        if [[ -n "$result" ]]; then
            printf '  \033[32mok\033[0m      %s\n' "$p"
            found=$((found+1))
        else
            printf '  \033[31mmissing\033[0m %s\n' "$p"
            missing+=("$p")
        fi
    done

    printf '\n  %d/%d package names resolved\n' "$found" "${#uniq[@]}"
    if (( ${#missing[@]} )); then
        printf '\n  MISSING - fix these names, or check whether %s still\n' "$hypr_copr"
        printf '  builds them, before running this for real:\n'
        printf '    %s\n' "${missing[@]}"
        return 1
    fi
    printf '\n  All package names resolve against the default repos + %s.\n' "$hypr_copr"
    printf '  This does not guarantee the COPR build is healthy - it only\n'
    printf '  proves the name exists right now.\n'
    return 0
}

if (( CHECK_REPOS )); then
    if check_repos; then exit 0; else exit 1; fi
fi

###############################################################################
# Live-environment tool check
#
# Unlike the Arch ISO (which ships sgdisk, dosfstools, btrfs-progs etc. out
# of the box), Fedora's live media is deliberately minimal - several tools
# this script needs to partition and format the disk are NOT installed by
# default. Checked and installed on the LIVE system here (never the target
# root) before any destructive action, rather than discovering one is
# missing halfway through partitioning with a bare "command not found".
###############################################################################
declare -A tool_pkg=(
    [sgdisk]=gdisk
    [wipefs]=util-linux
    [partprobe]=parted
    [udevadm]=systemd-udev
    [mkfs.vfat]=dosfstools
    [mkfs.btrfs]=btrfs-progs
    [btrfs]=btrfs-progs
    [blkid]=util-linux
    [chroot]=coreutils
)
[[ "$encrypt" == yes ]] && tool_pkg[cryptsetup]=cryptsetup
[[ "$encrypt" == yes ]] && tool_pkg[pvcreate]=lvm2
check_live_tools() {
    local missing_pkgs=() t
    for t in "${!tool_pkg[@]}"; do
        command -v "$t" >/dev/null 2>&1 || missing_pkgs+=("${tool_pkg[$t]}")
    done
    (( ${#missing_pkgs[@]} == 0 )) && return 0
    mapfile -t missing_pkgs < <(printf '%s\n' "${missing_pkgs[@]}" | sort -u)
    warn "missing on this live system: ${missing_pkgs[*]}"
    if (( DRY )) || (( PREFLIGHT_ONLY )); then
        warn "would run: dnf5 install -y ${missing_pkgs[*]}"
        return 0
    fi
    log "Installing missing live-system tools: ${missing_pkgs[*]}"
    dnf5 install -y "${missing_pkgs[@]}" \
        || die "failed to install required tools on the LIVE system (${missing_pkgs[*]}) - install them manually and re-run"
}
check_live_tools

###############################################################################
# Preflight
###############################################################################
preflight() {
    log "Preflight  (installer $installer_version)"

    printf '\n  Disks on this machine:\n'
    lsblk -dno NAME,SIZE,TYPE,MODEL,TRAN 2>/dev/null \
        | awk '$3=="disk" && $1!~/^(zram|loop|sr)/ {$3=""; printf "    /dev/%s\n", $0}' || true

    printf '\n  Firmware  : '
    if [[ -d /sys/firmware/efi/efivars ]]; then echo "UEFI  ok"; else echo "BIOS/CSM  -- systemd-boot needs UEFI"; fi
    printf '  CPU       : %s (%s)  ->  microcode_ctl\n' \
        "$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)" "$cpu_vendor"
    printf '  GPU       : %s\n' "$gpu_vendor"
    printf '  RAM       : %s\n' "$(numfmt --to=iec "$ram_bytes")"
    printf '  Network   : '
    if ping -c1 -W3 fedoraproject.org >/dev/null 2>&1; then echo "ok"; else echo "NO ROUTE -- connect before installing"; fi
    printf '  systemd-oomd: '
    if systemctl is-active --quiet systemd-oomd 2>/dev/null; then
        printf 'ACTIVE  -- known to silently SIGKILL long/disk-heavy scripts on live\n'
        printf '    media under memory pressure, with no error message at all. If a\n'
        printf '    real run dies with no ERROR line, this is the first suspect:\n'
        printf '        sudo systemctl mask --now systemd-oomd\n'
    else
        echo "inactive/not present  ok"
    fi

    printf '\n  \033[1mPlan\033[0m\n'
    printf '    Disk       : %s\n' "$target"
    printf '    Machine    : %s\n' "$machine"
    printf '    Encryption : %s\n' "$encrypt"
    if [[ "$want_swap" == yes ]]; then
        printf '    Swap       : %s on disk  (hibernation enabled)\n' "$swap_size"
    else
        printf '    Swap       : no disk swap  (no hibernation)\n'
    fi
    if [[ -n "$zram_size" ]]; then
        printf '    zram       : %s  (compressed RAM swap, used before disk swap)\n' "$zram_size"
    else
        printf '    zram       : none\n'
    fi
    printf '    Desktop    : Hyprland + quickshell  (autologin on tty1, no display manager)\n'
    printf '    Dotfiles   : %s\n' "${dotfiles_repo:-none}"
    printf '    Apps       : %s, %s\n' "$browser" "$terminal"
    printf '    Host/user  : %s / %s\n' "$hostname" "$username"
    printf '    Hyprland/quickshell source: COPR %s - VERIFY IT IS STILL MAINTAINED\n' "$hypr_copr"

    printf '\n    Layout:\n'
    printf '      %s  ESP %s, vfat, mounted at /boot  (also holds systemd-boot + BLS entries)\n' "$esppart" "$esp_size"
    if [[ "$encrypt" == yes ]]; then
        printf '      %s  LUKS2 -> LVM %s -> ' "$cryptpart" "$vg_name"
        [[ "$want_swap" == yes ]] && printf 'lv swap (%s) + ' "$swap_size"
        printf 'lv root (Btrfs)\n'
    else
        [[ "$want_swap" == yes ]] && printf '      %s  swap %s\n' "$swapdev" "$swap_size"
        printf '      %s  Btrfs root\n' "$rootdev"
    fi

    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        warn "not booted UEFI - this script cannot proceed"
        return 1
    fi

    if [[ "$want_swap" == yes ]]; then
        local sb; sb=$(numfmt --from=iec "$swap_size" 2>/dev/null || echo 0)
        (( sb * 5 >= ram_bytes * 2 )) || warn "swap is under 2/5 of RAM - hibernation may fail under load"
    fi
    printf '\n'
}

if (( PREFLIGHT_ONLY )); then
    if preflight; then exit 0; else exit 1; fi
fi

if (( DRY )); then
    preflight || warn "preflight found problems - continuing anyway, this is only a dry run"
else
    preflight || die "preflight failed"
    [[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode."
    [[ -b "$target" ]] || die "Target disk $target does not exist."
    livedev="$(findmnt -no SOURCE / || true)"
    if [[ -n "$livedev" && "$livedev" == "$target"* ]]; then
        die "$target appears to hold the running live system. Aborting."
    fi
fi

###############################################################################
# Confirm
###############################################################################
if (( DRY )); then
    log "DRY RUN - nothing below is executed, only printed"
else
    log "About to ERASE $target"
    lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS "$target" || true
    if (( ! ASSUME_YES )); then
        echo
        for i in {10..1}; do printf '\r    starting in %2ds - Ctrl+C to abort ' "$i"; sleep 1; done
        echo
    fi
fi

###############################################################################
# Partition
###############################################################################
log "Creating partitions"
run swapoff -a || true
runsh "umount -R $rootmnt 2>/dev/null || true"
# A previous interrupted run can leave the target's OLD LUKS/LVM stack live:
# unmounted (above) but still active at the device-mapper level. You cannot
# `cryptsetup close` a LUKS device while an LVM volume group built on top of
# it is still active - the LV stays active even after its filesystem is
# unmounted, until explicitly deactivated. Skipping this step doesn't fail
# loudly: cryptsetup close just silently no-ops on "device busy" (that's
# what the `|| true` below was hiding), and the script would then plow into
# wipefs/sgdisk with the old encrypted volume still live underneath -
# harmless for the GPT header itself, but it makes the NEXT luksFormat call
# fail right after you type the passphrase, since the partition is still
# genuinely in use by the stale mapping.
if [[ "$encrypt" == yes ]]; then
    runsh "vgchange -an 2>/dev/null || true"
    runsh "cryptsetup close $mapper_name 2>/dev/null || true"
fi
# A btrfs that the running kernel has already SCANNED stays registered even
# after it is unmounted, and that registration keeps the partition busy: the
# kernel then refuses to re-read the partition table ("unable to inform the
# kernel of the change ... they are in use"), so every later mkfs hits a stale
# layout and fails with "Device or resource busy". Live media scan for btrfs
# at boot, so this bites when reinstalling over an existing btrfs system - not
# only when a previous run of this script was interrupted.
#
# `btrfs device scan --forget` drops those registrations. It fails while a
# filesystem is still mounted, hence the umount above first, and it is not
# fatal here - on a disk with no btrfs there is simply nothing to forget.
if command -v btrfs >/dev/null 2>&1; then
    runsh "btrfs device scan --forget 2>/dev/null || true"
fi

run wipefs -af "$target"
run sgdisk -Z "$target"

# Make the kernel actually adopt the new table before anything tries to mkfs
# on it. partprobe alone is not always enough: udev has to finish creating the
# new device nodes, and on a disk that was just wiped the settle can lag.
settle_partitions() {
    local i
    (( DRY )) && { printf '   \033[2m|\033[0m partprobe %s + udevadm settle (with retries)\n' "$target"; return 0; }
    for i in 1 2 3 4 5; do
        partprobe "$target" >/dev/null 2>&1
        udevadm settle --timeout=10 >/dev/null 2>&1
        sleep 1
        # Success once the kernel reports at least one partition for the target.
        if lsblk -nro NAME "$target" 2>/dev/null | tail -n +2 | grep -q .; then
            return 0
        fi
    done
    warn "kernel still has not adopted the partition table for $target"
    warn "  if the next step fails with 'Device or resource busy', reboot the"
    warn "  live environment and run this script again - something in this"
    warn "  session still holds the old layout."
    return 0
}

# Erase filesystem signatures from each NEW partition.
#
# `wipefs -af "$target"` above only clears signatures on the disk itself - it
# does not reach inside partitions. An old btrfs superblock therefore survives
# in the region the new partition table maps to, and udev's btrfs rule scans
# and REGISTERS it the moment the partition node appears. That registration
# holds the device busy, so mkfs.btrfs then dies with
#     ERROR: unable to open /dev/vdaN: Device or resource busy
# and no amount of `btrfs device scan --forget` helps, because udev simply
# re-registers it. Wiping the partitions themselves removes what udev finds.
wipe_partitions() {
    local part
    if (( DRY )); then
        printf '   \033[2m|\033[0m wipefs -af each partition of %s\n' "$target"
        return 0
    fi
    for part in $(lsblk -nrpo NAME "$target" 2>/dev/null | tail -n +2); do
        if wipefs -af "$part" >/dev/null 2>&1; then
            continue
        fi
        # wipefs opens with O_EXCL, so it FAILS on a device the kernel still
        # holds - exactly the case we are trying to escape. dd does not use
        # O_EXCL and can still write, so fall back to zeroing the superblock
        # locations by hand. btrfs keeps its primary superblock at 64 KiB and
        # a copy at 64 MiB; clearing the first megabyte and the 64 MiB mark
        # removes both, which is what stops udev re-registering the device.
        warn "  wipefs could not open $part (busy) - zeroing superblocks directly"
        dd if=/dev/zero of="$part" bs=1M count=2      conv=fsync >/dev/null 2>&1 || true
        dd if=/dev/zero of="$part" bs=1M count=1 seek=64 conv=fsync >/dev/null 2>&1 || true
    done
    # Drop any registration that slipped in before the wipe.
    command -v btrfs >/dev/null 2>&1 && btrfs device scan --forget >/dev/null 2>&1 || true
    udevadm settle --timeout=10 >/dev/null 2>&1 || true
}

if [[ "$encrypt" == yes ]]; then
    run sgdisk \
        -n1:0:+"$esp_size" -t1:ef00 -c1:EFISYSTEM \
        -n2:0:0            -t2:8309 -c2:"$luks_label" \
        "$target"
elif [[ "$want_swap" == yes ]]; then
    run sgdisk \
        -n1:0:+"$esp_size"  -t1:ef00 -c1:EFISYSTEM \
        -n2:0:+"$swap_size" -t2:8200 -c2:SWAP \
        -n3:0:0             -t3:8300 -c3:BTRFSROOT \
        "$target"
else
    run sgdisk \
        -n1:0:+"$esp_size" -t1:ef00 -c1:EFISYSTEM \
        -n2:0:0            -t2:8300 -c2:BTRFSROOT \
        "$target"
fi
settle_partitions
wipe_partitions

log "Making file systems"
run mkfs.vfat -F32 -n EFISYSTEM "$esppart"
run udevadm settle

if [[ "$encrypt" == yes ]]; then
    log "Setting up LUKS2 + LVM"
    {
        echo
        echo "  You will be prompted for the disk encryption passphrase:"
        echo "  twice to set it, then once more to unlock it for the install."
        echo "  It is not recoverable if you lose it."
        echo
    } >/dev/tty 2>/dev/null || true
    run cryptsetup luksFormat --type luks2 --batch-mode --label "$luks_label" "$cryptpart"
    run cryptsetup open "$cryptpart" "$mapper_name"
    run udevadm settle

    run pvcreate -f "$mapperdev"
    run vgcreate "$vg_name" "$mapperdev"
    [[ "$want_swap" == yes ]] && run lvcreate -L "$swap_size" -n swap "$vg_name"
    run lvcreate -l 100%FREE -n root "$vg_name"
    run udevadm settle
fi

[[ "$want_swap" == yes ]] && run mkswap -L SWAP "$swapdev"
run mkfs.btrfs -f -L BTRFSROOT "$rootdev"
run udevadm settle

if (( DRY )); then
    luks_uuid="00000000-0000-0000-0000-0000000luks"
    root_uuid="00000000-0000-0000-0000-00000000root"
    swap_uuid="00000000-0000-0000-0000-00000000swap"
else
    root_uuid="$(blkid -s UUID -o value "$rootdev")"
    [[ -n "$root_uuid" ]] || die "could not read the root filesystem UUID"
    swap_uuid=""
    if [[ "$want_swap" == yes ]]; then
        swap_uuid="$(blkid -s UUID -o value "$swapdev")"
        [[ -n "$swap_uuid" ]] || die "could not read the swap UUID"
    fi
    luks_uuid=""
    if [[ "$encrypt" == yes ]]; then
        luks_uuid="$(blkid -s UUID -o value "$cryptpart")"
        [[ -n "$luks_uuid" ]] || die "could not read the LUKS container UUID"
    fi
fi

###############################################################################
# Subvolumes  (Fedora's own root+home layout - see the header note)
###############################################################################
log "Creating Btrfs subvolumes"
run mount "$rootdev" "$rootmnt"
run btrfs subvolume create "$rootmnt/root"
run btrfs subvolume create "$rootmnt/home"

# Fedora mounts root via the filesystem's DEFAULT subvolume rather than a
# subvol= option - set that now while the top-level subvolume (id 5) is
# still what's mounted at $rootmnt, so every later mount of $rootdev with
# no subvol= option lands on "root" automatically, exactly like a stock
# Fedora fstab.
if (( DRY )); then
    root_subvolid="256"
else
    root_subvolid="$(btrfs subvolume list "$rootmnt" | awk '$NF=="root"{print $2}')"
    [[ -n "$root_subvolid" ]] || die "could not find the id of the root subvolume just created"
fi
run btrfs subvolume set-default "$root_subvolid" "$rootmnt"
run umount "$rootmnt"

log "Mounting subvolumes"
run mount -o "$btrfs_opts" "$rootdev" "$rootmnt"
run mkdir -p "$rootmnt"/{home,boot}
run mount -o "$btrfs_opts,subvol=home" "$rootdev" "$rootmnt/home"
run mount "$esppart" "$rootmnt/boot"
[[ "$want_swap" == yes ]] && run swapon "$swapdev"

###############################################################################
# chroot helper
#
# Fedora live media does not ship arch-chroot's convenience of bind-mounting
# /dev, /proc, /sys and /run for you - dnf --installroot handles that for its
# OWN transactions, but anything this script runs manually after the package
# install (kernel-install, bootctl, useradd, systemctl --root does NOT need
# this) does. fchroot mounts them once and reuses the mount for every call.
###############################################################################
_chroot_mounted=0
mount_chroot() {
    (( _chroot_mounted )) && return 0
    (( DRY )) && { _chroot_mounted=1; return 0; }
    # --rbind + --make-rslave (not a plain --bind) for /dev and /sys: both
    # have their own submounts (devpts, shm, cgroup, efivars, etc.) that
    # bootctl/dracut/kernel-install can need. A flat --bind only exposes the
    # top mount, not what's mounted under it.
    run mount --types proc /proc "$rootmnt/proc"
    run mount --rbind /sys "$rootmnt/sys"
    run mount --make-rslave "$rootmnt/sys"
    run mount --rbind /dev "$rootmnt/dev"
    run mount --make-rslave "$rootmnt/dev"
    run mount --bind /run "$rootmnt/run"
    _chroot_mounted=1
}
umount_chroot() {
    (( _chroot_mounted )) || return 0
    (( DRY )) || {
        umount -R "$rootmnt/run" 2>/dev/null || true
        umount -R "$rootmnt/sys" 2>/dev/null || true
        umount -R "$rootmnt/dev" 2>/dev/null || true
        umount -R "$rootmnt/proc" 2>/dev/null || true
    }
    _chroot_mounted=0
}
# Cleanup on any exit (die, signal, or normal completion) is handled by the
# single on_exit trap set earlier, right after the log redirection - not
# here, since a second `trap ... EXIT` would silently replace that one.
fchroot() {
    mount_chroot
    if (( DRY )); then
        printf '   \033[2m|\033[0m chroot %s %s\n' "$rootmnt" "$*"
        return 0
    fi
    chroot "$rootmnt" "$@"
}

###############################################################################
# Base system
###############################################################################
log "Bootstrapping the base system (this is the long part)"
run mkdir -p "$rootmnt/etc/yum.repos.d"
# NO --setopt=install_weak_deps=False anywhere in this script. It was here
# originally to keep the install lean, but Fedora leans on Recommends (not
# hard Requires) for things that matter far more than package count:
# per-vendor firmware sub-packages (this Framework 13's amdgpu and iwlwifi
# firmware BOTH come in only via Recommends - stripping weak deps left
# amdgpu unable to load ANY firmware at all, "Fatal error during GPU init",
# permanently black-screening the machine at boot) and systemd's PAM/logind
# integration (also Recommends-only - without it sddm-helper can't open a
# session, so SDDM's greeter compositor can't get a seat either, a second,
# independent failure from the exact same cause). Two different fatal boot
# failures traced back to this one flag; it's not worth the disk savings.
run dnf5 --installroot "$rootmnt" --releasever "$releasever" --use-host-config -y \
    install "${basepacs[@]}"

log "Adding the Hyprland/quickshell COPR ($hypr_copr)"
writefile 0644 "$rootmnt/etc/yum.repos.d/_copr_${hypr_copr//\//-}.repo" <<EOF
[copr:copr.fedorainfracloud.org:${hypr_copr%%/*}:${hypr_copr##*/}]
name=Copr repo for ${hypr_copr##*/} owned by ${hypr_copr%%/*}
baseurl=https://download.copr.fedorainfracloud.org/results/${hypr_copr}/fedora-\$releasever-\$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/${hypr_copr}/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
EOF

log "Installing hardware, desktop and app packages"
# --use-host-config is deliberately DROPPED for this call, unlike the first
# one. That flag makes dnf5 read the LIVE system's own /etc/yum.repos.d
# instead of the installroot's - correct for the first call above, when
# $rootmnt starts with zero repo config of its own, but wrong here: the
# fedora-release package just installed into $rootmnt has already dropped
# real fedora.repo/fedora-updates.repo files into $rootmnt/etc/yum.repos.d,
# and the COPR file above was written to that same directory - not the live
# system's. Keeping --use-host-config here would silently read the LIVE
# system's repo list instead (which has no idea this COPR exists), and the
# COPR packages would fail to resolve with no explanation, which is exactly
# what happened before this was caught.
# -x nwg-panel: it declares `Supplements: hyprland`, which is the REVERSE of
# Recommends - "install me whenever hyprland is installed" - so it arrives
# unasked on every install and cannot be traced by querying what recommends
# it, because nothing does. It is a GTK3 panel, i.e. a second bar doing the
# same job as quickshell's, and it drags in about 9MB of GTK and Python
# including playerctl, gtk-layer-shell, python3-i3ipc and wlr-randr, none of
# which anything here uses.
#
# Excluded by name rather than with --setopt=install_weak_deps=False: that
# flag is deliberately NOT used anywhere in this script, for reasons written
# out at length above the base install - this Framework's amdgpu and iwlwifi
# firmware both arrive only via Recommends, and stripping weak deps left the
# machine unable to load any firmware at all. One unwanted package is excluded
# by name; the mechanism stays on.
run dnf5 --installroot "$rootmnt" --releasever "$releasever" -y \
    -x nwg-panel \
    install "${hwpacs[@]}" "${depacs[@]}" "${apppacs[@]}"

###############################################################################

log "Generating fstab"
runsh "genfstab -U $rootmnt >> $rootmnt/etc/fstab 2>/dev/null || \
       { echo '# genfstab not on this media - writing fstab by hand'; }"
if (( ! DRY )) && ! grep -q "$root_uuid" "$rootmnt/etc/fstab" 2>/dev/null; then
    {
        echo "UUID=$(blkid -s UUID -o value "$esppart")  /boot  vfat  umask=0077  0 2"
        # No subvol= here on purpose - root mounts via the default subvolume
        # set earlier, exactly like a stock Fedora fstab's root line.
        echo "UUID=$root_uuid  /      btrfs  $btrfs_opts               0 0"
        echo "UUID=$root_uuid  /home  btrfs  $btrfs_opts,subvol=home   0 0"
        [[ "$want_swap" == yes ]] && echo "UUID=$swap_uuid  none  swap  defaults  0 0"
    } >> "$rootmnt/etc/fstab"
fi

###############################################################################
# Locale / hostname / users
###############################################################################
log "Setting up the environment"
run rm -f "$rootmnt"/etc/{machine-id,localtime,hostname,locale.conf}
run systemd-firstboot --root "$rootmnt" \
    --keymap="$keymap" --locale="$locale" --locale-messages="$locale" \
    --timezone="$timezone" --hostname="$hostname" \
    --setup-machine-id --welcome=false

writefile 0644 "$rootmnt/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF

log "Creating user $username"
mount_chroot
[[ -z "$user_password" ]] && die "user_password is empty - set a hash in the config block"
run fchroot useradd -m -G wheel -s /bin/bash -p "$user_password" "$username"

# Expire the password immediately, so the first login MUST set a new one.
#
# THE PASSWORD IS DELIBERATELY *NOT* EXPIRED HERE. Read this before adding
# `chage -d 0` back, because it looks like an obvious omission and is not.
#
# Expiring it (shadow field 3 = 0) makes the installed machine UNBOOTABLE.
# agetty --autologin execs `login -f`, which skips authentication but still
# runs PAM account management - and pam_unix REJECTS an expired password
# outright there rather than prompting to change it. There is no interactive
# dialog on that path. So login exits, systemd respawns getty, and the machine
# loops forever without ever reaching a shell or starting Hyprland.
#
# This was believed to work for several versions, and the comment here used to
# assert that PAM "forces a change before handing over to the shell". A VM
# install proved otherwise:
#
#   login[678]: pam_unix(login:account): expired password for user jc (root enforced)
#   getty@tty1.service: Scheduled restart job, restart counter is at 3
#   ... 13 restarts, 0 hyprland/uwsm lines in the whole journal
#
# The forced change still happens - it moved to ~/.bash_profile, which runs
# after login has succeeded and CAN prompt interactively. See the profile
# written further down.
writefile 0440 "$rootmnt/etc/sudoers.d/10-wheel" <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
run fchroot visudo -cf /etc/sudoers.d/10-wheel

# Files this script writes directly (fstab, hosts, sudoers, and the dracut/
# zram/greetd/hypridle/hyprlock configs still to come) bypass rpm's normal
# SELinux labeling. Schedule a full relabel on first boot rather than
# hand-labeling each one - expect the very first boot to take noticeably
# longer than the rest because of it, that's the relabel, not a hang.
run touch "$rootmnt/.autorelabel"

###############################################################################
# initramfs, cmdline, systemd-boot
#
# dracut's hostonly mode (the default) looks at the actual devices under
# $rootmnt and includes crypt/lvm/btrfs support only if they are really
# needed - there is no HOOKS array to hand-assemble here.
###############################################################################
log "Configuring the kernel command line and boot entries"
cmdline="root=UUID=$root_uuid rw rootfstype=btrfs"
if [[ "$encrypt" == yes ]]; then
    cmdline="rd.luks.uuid=$luks_uuid rd.luks.name=$luks_uuid=$mapper_name rd.lvm.lv=$vg_name/root $cmdline"
    [[ "$want_swap" == yes ]] && cmdline+=" rd.lvm.lv=$vg_name/swap"
fi
[[ "$want_swap"  == yes    ]] && cmdline+=" resume=UUID=$swap_uuid"
# Quiet, graphical boot.
#   rhgb                      activates Plymouth
#   quiet + loglevel=3        suppress kernel chatter
#   systemd.show_status=false suppress the "[ OK ] Started ..." lines, which
#                             `quiet` does NOT cover - this is the big one
#   rd.* variants             same, inside the initrd (i.e. around the LUKS
#                             passphrase prompt)
#   vt.global_cursor_default=0  no blinking block cursor on the console
cmdline+=" quiet rhgb loglevel=3 systemd.show_status=false rd.systemd.show_status=false rd.udev.log_level=3 udev.log_level=3 vt.global_cursor_default=0"

writefile 0644 "$rootmnt/etc/kernel/cmdline" <<<"$cmdline"

log "Installing systemd-boot to the ESP"
run fchroot bootctl --esp-path=/boot install

log "Generating the initramfs and BLS boot entry"
kver=""
if (( ! DRY )); then
    kver="$(fchroot rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | tail -n1)"
    [[ -n "$kver" ]] || die "could not determine the installed kernel version"
fi
# kernel-install runs dracut itself and writes /boot/loader/entries/<id>.conf.
# The kernel RPM's own scriptlet usually already did this during the dnf5
# --installroot transaction above; calling it again here is idempotent and
# is the explicit safety net this script relies on rather than trusting that
# silently.
run fchroot kernel-install add "$kver" "/usr/lib/modules/$kver/vmlinuz"

writefile 0644 "$rootmnt/boot/loader/loader.conf" <<'EOF'
timeout 3
console-mode max
EOF

if [[ -n "$zram_size" ]]; then
    log "Configuring zram"
    writefile 0644 "$rootmnt/etc/systemd/zram-generator.conf" <<EOF
[zram0]
zram-size = $zram_size
compression-algorithm = zstd
EOF
    writefile 0644 "$rootmnt/etc/sysctl.d/99-zram.conf" <<'EOF'
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF
fi

###############################################################################
# Hyprland session configuration
#
# uwsm is what makes SDDM/greetd's .desktop launch actually start
# graphical-session.target - without it the polkit agent and hypridle would
# be enabled but never run, same reasoning as the Arch script.
###############################################################################
log "Configuring the Hyprland session"
if (( DRY )) || [[ ! -f "$rootmnt/usr/share/wayland-sessions/hyprland-uwsm.desktop" ]]; then
    writefile 0644 "$rootmnt/usr/local/share/wayland-sessions/hyprland-uwsm.desktop" <<'EOF'
[Desktop Entry]
Name=Hyprland (uwsm-managed)
Comment=Hyprland started through the Universal Wayland Session Manager
Exec=uwsm start -- hyprland.desktop
Type=Application
DesktopNames=Hyprland
EOF
fi

writefile 0644 "$rootmnt/home/$username/.config/hypr/hypridle.conf" <<'EOF'
general {
    lock_cmd         = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd  = hyprctl dispatch dpms on
}
listener {
    timeout    = 300
    on-timeout = loginctl lock-session
}
listener {
    timeout    = 330
    on-timeout = hyprctl dispatch dpms off
    on-resume  = hyprctl dispatch dpms on
}
EOF

writefile 0644 "$rootmnt/home/$username/.config/hypr/hyprlock.conf" <<'EOF'
background {
    monitor =
    color   = rgba(1a1a1aff)
}
input-field {
    monitor           =
    size              = 300, 50
    outline_thickness = 2
    outer_color       = rgba(00000000)
    inner_color       = rgba(ffffff1a)
    font_color        = rgb(cccccc)
    fade_on_empty     = false
    placeholder_text  = <i>Password…</i>
    position          = 0, -20
    halign            = center
    valign            = center
}
label {
    monitor   =
    text      = cmd[update:1000] date +"%H:%M"
    font_size = 55
    color     = rgb(cccccc)
    position  = 0, 100
    halign    = center
    valign    = center
}
EOF

run fchroot chown -R "$username:$username" "/home/$username/.config"

###############################################################################
# Autologin + session start (replaces the display manager)
#
# There is no greeter. getty autologins the user on tty1, and the user's shell
# profile starts Hyprland through uwsm.
#
# Deliberate details:
#   --noissue --nohostname  suppress the "Fedora Linux 44 / Kernel ..." banner
#                           and the hostname, so nothing is printed over the
#                           Plymouth handoff
#   -n                      skip the login prompt entirely
#   NO --noclear            agetty clears the screen before login, which wipes
#                           any leftover boot text (the stock unit passes
#                           --noclear, which is exactly what preserves it)
#
# The default target stays graphical.target. Most autologin guides say to use
# multi-user.target; that BREAKS this setup, because `uwsm check may-start`
# explicitly requires the system to have reached graphical.target. Simply not
# installing a display manager is enough - display-manager.service is only
# Wanted by that target, not Required.
###############################################################################
log "Setting up autologin on tty1"

writefile 0644 "$rootmnt/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/usr/sbin/agetty -n --autologin $username --noissue --nohostname %I \$TERM
EOF

# uwsm start hook. `uwsm check may-start` verifies: login shell, user dbus up,
# system at graphical.target, no graphical-session already active, and the
# foreground VT is 1 - so it stays inert over ssh and on other VTs.
#
# Not `exec`, and not a plain fall-through either. A session that RAN and then
# ended logs out, so no unlocked autologin shell is left on tty1; getty then
# autologins a fresh session. (A crash alone does not end it - start-hyprland
# restarts Hyprland in place, still locked if it was locked.) A compositor that dies within its first seconds leaves the
# shell, so a broken config can be fixed and getty does not respawn in a loop.
# Written in full (rather than appended) so this goes through writefile and is
# therefore dry-run aware and creates its own parent directory. The first half
# reproduces Fedora's /etc/skel/.bash_profile.
writefile 0644 "$rootmnt/home/$username/.bash_profile" <<'PROFILE'
# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# User specific environment and startup programs

# The account ships with the installer's publicly-known password. Force a real
# one before anything else runs, and refuse to go further until it is set.
#
# THIS IS WHY THE PASSWORD IS NOT EXPIRED IN /etc/shadow. An expired password
# is rejected by PAM account management under the `login -f` that
# agetty --autologin uses - it never prompts, login just exits, and getty
# respawns forever. Doing it here instead works because by this point login
# has already succeeded and there is a real terminal to prompt on.
#
# The marker lives in ~/.local/state so a stray ~/.config wipe cannot silently
# disarm the gate.
_pw_marker="${XDG_STATE_HOME:-$HOME/.local/state}/password-changed"
if [ ! -e "$_pw_marker" ]; then
    printf '\n  This account still has the installer default password.\n'
    printf '  Set a real one now - the desktop will not start until you do.\n\n'
    # Ctrl+C, Ctrl+\ and Ctrl+Z are ignored while this runs - and, because an
    # ignored signal is inherited, by passwd as well. Without this, Ctrl+C at
    # the prompt aborted the rest of this profile and left a shell on which
    # sudo still accepted the public default password.
    trap '' INT QUIT TSTP
    while ! passwd; do
        printf '\n  Password not changed. Try again.\n\n'
    done
    trap - INT QUIT TSTP
    mkdir -p "$(dirname "$_pw_marker")"
    : >"$_pw_marker"
    printf '\n  Thank you. Starting the desktop.\n\n'
fi
unset _pw_marker

# Start Hyprland automatically on VT1 after getty autologin.
#
# When the session ENDS, log out - unless it died within its first seconds.
# A plain crash does not end it: uwsm runs Hyprland under start-hyprland, a
# watchdog that restarts it in the same session (in safe mode), and a crash
# while locked comes back still locked - tested. The session ends when the
# watchdog gives up or uwsm stops it, and then this autologin shell must not be
# left behind as an unlocked shell on tty1. Logging out makes getty autologin a
# fresh session instead, which bin/lock-at-login.sh locks on a machine without
# disk encryption. A compositor that dies straight away is a broken config or
# driver, not a session that ran; staying in the shell then is what lets it be
# fixed, and avoids a respawn loop.
if uwsm check may-start -q; then
    _uwsm_state="${XDG_STATE_HOME:-$HOME/.local/state}"
    mkdir -p "$_uwsm_state"
    _uwsm_started=$SECONDS
    uwsm start -e -D Hyprland hyprland.desktop >"$_uwsm_state/uwsm-start.log" 2>&1
    _uwsm_status=$?
    if (( SECONDS - _uwsm_started < 15 )); then
        echo "Hyprland exited after $(( SECONDS - _uwsm_started ))s (status $_uwsm_status)."
        echo "See $_uwsm_state/uwsm-start.log"
    else
        exit 0
    fi
    unset _uwsm_state _uwsm_started _uwsm_status
fi
PROFILE
run fchroot chown "$username:$username" "/home/$username/.bash_profile"

###############################################################################
# Dotfiles (optional)
###############################################################################
if [[ -n "$dotfiles_repo" ]]; then
    log "Cloning dotfiles from $dotfiles_repo"
    dotdir="$(basename "${dotfiles_repo%.git}")"
    if run fchroot sudo -u "$username" git clone --depth 1 "$dotfiles_repo" \
            "/home/$username/Work/$dotdir"; then

        # Symlink the Hyprland config dir at the repo, replacing the minimal
        # one written above. Only if the repo actually has a hypr/ directory -
        # otherwise leave the working stock config in place.
        if [[ -d "$rootmnt/home/$username/Work/$dotdir/hypr" ]]; then
            run rm -rf "$rootmnt/home/$username/.config/hypr"
            run fchroot sudo -u "$username" ln -s \
                "/home/$username/Work/$dotdir/hypr" "/home/$username/.config/hypr"
            log "  ~/.config/hypr -> Work/$dotdir/hypr"
        elif (( DRY )); then
            log "  (dry run: nothing was cloned, so hypr/ and systemd/ cannot"
            log "   be inspected - on a real run they would be linked here)"
        else
            warn "  repo has no hypr/ directory - keeping the stock config"
        fi

        # Every other config directory the repo ships, linked the same way.
        #
        # A LIST, not a hardcoded case per directory. quickshell used to be
        # missing here entirely: the repo was cloned, the Hyprland side
        # worked, `qs -d` started from autostart.lua, and quickshell then
        # found no ~/.config/quickshell/shell.qml and drew nothing. The result
        # booted to a bare desktop that looked like the dotfiles had failed,
        # when in fact only half of them had been linked. Adding a directory
        # to the repo and forgetting to add a branch here is exactly how that
        # happened, so adding one to this list is now the whole job.
        for cfg in quickshell kitty wireplumber; do
            if [[ -d "$rootmnt/home/$username/Work/$dotdir/$cfg" ]]; then
                run rm -rf "$rootmnt/home/$username/.config/$cfg"
                run fchroot sudo -u "$username" ln -s \
                    "/home/$username/Work/$dotdir/$cfg" \
                    "/home/$username/.config/$cfg"
                log "  ~/.config/$cfg -> Work/$dotdir/$cfg"
            elif (( ! DRY )); then
                warn "  repo has no $cfg/ directory - skipping"
            fi
        done

        # Any user units the repo ships get linked and enabled.
        if [[ -d "$rootmnt/home/$username/Work/$dotdir/systemd" ]]; then
            run fchroot sudo -u "$username" mkdir -p "/home/$username/.config/systemd/user"
            for unit in "$rootmnt/home/$username/Work/$dotdir/systemd/"*.service; do
                [[ -e "$unit" ]] || continue
                u="$(basename "$unit")"
                run fchroot sudo -u "$username" ln -sf \
                    "/home/$username/Work/$dotdir/systemd/$u" \
                    "/home/$username/.config/systemd/user/$u"
                # `systemctl --global enable` only searches system-wide user
                # unit directories (/usr/lib/systemd/user, /etc/systemd/user);
                # it cannot see a unit that lives in the user's own
                # ~/.config/systemd/user, so it fails with "Unit ... does not
                # exist". There is no user session in a chroot to run
                # `systemctl --user` against either, so create the WantedBy
                # symlink directly - which is exactly what enabling does.
                wanted=$(grep -m1 '^WantedBy=' "$unit" | cut -d= -f2 | tr -d '[:space:]')
                if [[ -n $wanted ]]; then
                    run fchroot sudo -u "$username" mkdir -p \
                        "/home/$username/.config/systemd/user/$wanted.wants"
                    run fchroot sudo -u "$username" ln -sf \
                        "/home/$username/Work/$dotdir/systemd/$u" \
                        "/home/$username/.config/systemd/user/$wanted.wants/$u"
                    log "  enabled user unit $u (WantedBy=$wanted)"
                else
                    warn "  $u has no WantedBy= - linked but not enabled"
                fi
            done
        fi
        run fchroot chown -R "$username:$username" "/home/$username/Work" \
            "/home/$username/.config"
    else
        warn "dotfiles clone FAILED - the stock config is still in place"
    fi
fi

# Symbols Nerd Font
#
# The bar's Fedora logo and the volume/brightness OSD icons are Nerd Font
# glyphs (Theme.glyphFont). Fedora packages no Nerd Font other than a TeX
# one, so this is the single thing here that comes from outside the distro
# repos.
#
# Symbols-only, not a patched typeface: ~2 MB against ~50 MB for a full
# family, and the glyphs are all that is wanted - text comes from Inter.
#
# Downloaded on the LIVE system rather than inside the chroot, because the
# target has no curl until something happens to pull one in and there is no
# reason to add one just for this.
#
# --no-same-owner matters: tar running as root otherwise restores the
# ownership recorded IN THE ARCHIVE, and this one carries uid 1001 / gid 118.
# That is nobody on the live system, but 1001 is very plausibly a second real
# account on the installed one - which would leave a normal user owning a
# font in /usr/local/share/fonts, able to replace it. Caught by checking the
# file after a VM install rather than by assuming tar does the obvious thing.
#
# NON-FATAL BY DESIGN. A missing font means tofu boxes where the logo and
# the OSD icons should be; it does not stop the desktop coming up, and
# failing the whole install over it - after the disk has already been
# partitioned - would be absurd. It warns and carries on, and the message
# says exactly how to finish the job by hand.
###############################################################################
nerdfont_ver="v3.4.0"
nerdfont_url="https://github.com/ryanoasis/nerd-fonts/releases/download/$nerdfont_ver/NerdFontsSymbolsOnly.tar.xz"
# sha256 of that tarball. Release assets can be replaced after publication, so
# the download is checked against this before anything is extracted. The font
# inside it is byte-identical to fonts/nerd-fonts-symbols/ in the dotfiles repo
# (71db104a...). Change it together with nerdfont_ver, and with
# bin/install-nerd-font.sh, which pins the same pair.
nerdfont_sha256="7f8c090da3b0eaa7108646bf34cbbb6ed13d5358a72460522108b06c7ecd716a"
nerdfont_dir="$rootmnt/usr/local/share/fonts/nerd-fonts-symbols"

# PREFER THE COPY IN THE DOTFILES CHECKOUT. This runs after the clone for
# exactly that reason - it used to sit a few hundred lines earlier, before
# there was anything to copy from.
#
# Fedora packages no Symbols Nerd Font, so it has to come from somewhere, and
# downloading it made this the one step in the whole install that reached the
# public internet and was allowed to fail. When it failed, every glyph in the
# bar, launcher, OSD, power menu and lock screen rendered as an empty box. The
# font is committed at fonts/nerd-fonts-symbols/ (MIT, licence committed
# beside it), so a dotfiles repo that carries it removes the network from this
# step entirely - and pins the version, which a download does not: the repair
# script used to reuse whatever copy it found and installed 3.5.1 against a
# pin of 3.4.0 without anyone noticing.
#
# The download stays as the fallback, for an install with no dotfiles repo -
# it is optional - or one whose repo predates the font being committed.
vendored_font=""
if [[ -n "$dotfiles_repo" ]]; then
    vendored_font="$rootmnt/home/$username/Work/$(basename "${dotfiles_repo%.git}")/fonts/nerd-fonts-symbols/SymbolsNerdFont-Regular.ttf"
fi

log "Installing Symbols Nerd Font ($nerdfont_ver)"
if (( DRY )); then
    run curl -fsSL "$nerdfont_url" -o "(tmp)/NerdFontsSymbolsOnly.tar.xz"
    run tar -xJf "(tmp)/NerdFontsSymbolsOnly.tar.xz" -C "$nerdfont_dir" \
        SymbolsNerdFont-Regular.ttf
else
    # Not a symlink: `install` runs as root outside the chroot and follows
    # links, so a repo committing the "font" as a link to /mnt/etc/shadow would
    # have it copied out world-readable.
    if [[ -n "$vendored_font" && -f "$vendored_font" && ! -L "$vendored_font" ]]; then
        mkdir -p "$nerdfont_dir"
        if install -m 0644 -o root -g root "$vendored_font" \
                "$nerdfont_dir/SymbolsNerdFont-Regular.ttf"; then
            run fchroot fc-cache -f /usr/local/share/fonts >/dev/null 2>&1 || true
            log "  from the dotfiles checkout, no download needed"
            nerdfont_done=1
        fi
    fi

    nerdfont_tmp="$(mktemp -d)"
    if (( ${nerdfont_done:-0} )); then
        :
    # Checked against the pinned sha256, extracted into the temp directory
    # rather than straight into the target, refused if what came out is not a
    # plain file, and only then installed with its owner and mode set by
    # `install`. The old chown/chmod after an in-place extraction followed a
    # symlink, which a tampered archive could have pointed at /mnt/etc/shadow.
    elif curl -fsSL --retry 2 --max-time 120 "$nerdfont_url" \
            -o "$nerdfont_tmp/symbols.tar.xz" \
       && printf '%s  %s\n' "$nerdfont_sha256" "$nerdfont_tmp/symbols.tar.xz" \
              | sha256sum --check --status \
       && tar --no-same-owner --no-same-permissions \
              -xJf "$nerdfont_tmp/symbols.tar.xz" -C "$nerdfont_tmp" \
              SymbolsNerdFont-Regular.ttf \
       && [[ -f "$nerdfont_tmp/SymbolsNerdFont-Regular.ttf" && ! -L "$nerdfont_tmp/SymbolsNerdFont-Regular.ttf" ]] \
       && mkdir -p "$nerdfont_dir" \
       && install -m 0644 -o root -g root "$nerdfont_tmp/SymbolsNerdFont-Regular.ttf" \
              "$nerdfont_dir/SymbolsNerdFont-Regular.ttf"
    then
        # The cache is rebuilt in the target, not on the live system - it is
        # the target's fontconfig that has to know about the file.
        run fchroot fc-cache -f /usr/local/share/fonts >/dev/null 2>&1 || true
        log "  /usr/local/share/fonts/nerd-fonts-symbols/SymbolsNerdFont-Regular.ttf"
    else
        warn "Symbols Nerd Font download or checksum check failed - every glyph in the bar,"
        warn "  launcher, OSD, power menu and lock screen will be an empty box."
        warn "  To fix after first boot, from the dotfiles checkout:"
        warn "    sudo bin/install-nerd-font.sh"
        warn "  It installs the copy committed at fonts/nerd-fonts-symbols/,"
        warn "  so it needs no network at all."
    fi
    rm -rf "$nerdfont_tmp"
fi

###############################################################################
# Services
###############################################################################
log "Enabling services"
services=(NetworkManager bluetooth fstrim.timer systemd-timesyncd)
[[ "$machine" == laptop ]] && services+=(power-profiles-daemon)
run fchroot systemctl enable "${services[@]}"
run fchroot systemctl --global enable hyprpolkitagent.service hypridle.service \
    || warn "could not enable one of the Hyprland user units"

# The power button opens quickshell's power menu instead of shutting the
# machine down on the spot. logind's default is HandlePowerKey=poweroff - one
# press, immediate shutdown, no confirmation - and it reads the key straight
# from /dev/input, so the compositor's own binding cannot override it. Setting
# it to ignore hands the key to Hyprland, where hypr/binds.lua binds
# XF86PowerOff to the menu.
#
# The long press is the fallback and the reason this is safe: it still powers
# off cleanly, so the button keeps working at a text console, or if the
# compositor never starts, or if quickshell has died. Not a laptop-only
# setting - a desktop benefits from it at least as much.
writefile 0644 "$rootmnt/etc/systemd/logind.conf.d/00-power-key.conf" <<'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
EOF

# Chromium theming: a root service writes the policy, the user only asks.
#
# bin/theme.sh colours the browser to match the desktop theme through an
# enterprise policy file, and Chromium reads policy only from /etc. This used
# to be done by making /etc/chromium/policies/managed owned by the user - which
# let ANY program running as the user set any browser policy (force-install an
# extension, set a proxy), not just the colour.
#
# Now the directory stays root's, and bin/chromium-policy-setup.sh installs a
# sandboxed root service that turns a validated "<rrggbb> <light|dark>" request
# from the user's ~/.local/state into color.json and nothing else. It lives in
# the dotfiles because theme.sh, the only thing that uses it, does too - so
# without a dotfiles repo there is nothing to set up. Run INSIDE the target,
# where it resolves the user from the target's own passwd and only enables the
# watcher, since nothing can be started before the first boot.
if [[ "$browser" == chromium && -n "$dotfiles_repo" ]]; then
    _cps="/home/$username/Work/${dotdir:-}/bin/chromium-policy-setup.sh"
    if (( DRY )) || [[ -x "$rootmnt$_cps" ]]; then
        run fchroot "$_cps" --user "$username"
    else
        warn "the dotfiles have no bin/chromium-policy-setup.sh - Chromium will"
        warn "  not follow themes until it is set up"
    fi
    unset _cps
fi

if [[ "$machine" == laptop ]]; then
    writefile 0644 "$rootmnt/etc/systemd/logind.conf.d/00-lid.conf" <<EOF
[Login]
HandleLidSwitch=$( [[ "$want_swap" == yes ]] && echo suspend-then-hibernate || echo suspend )
HandleLidSwitchExternalPower=suspend
EOF
    if [[ "$want_swap" == yes ]]; then
        writefile 0644 "$rootmnt/etc/systemd/sleep.conf.d/00-hibernate.conf" <<'EOF'
[Sleep]
HibernateDelaySec=45min
EOF
    fi
fi

run fchroot usermod -L root

###############################################################################
# Verification
###############################################################################
umount_chroot

if (( DRY )); then
    log "Dry run finished"
    cat <<EOF

  Nothing was written. $target was not touched.

  Disk       : $target
  Encryption : $encrypt
  Swap       : $swap_size$( [[ -n "$zram_size" ]] && echo "   zram: $zram_size" )
  Machine    : $machine        CPU: $cpu_vendor        GPU: $gpu_vendor
  Desktop    : Hyprland + quickshell (autologin on tty1, no display manager)
  Dotfiles   : ${dotfiles_repo:-none}
  Apps       : $browser, $terminal
  cmdline    : $cmdline

  Run it for real with:   sudo $0 -d ${target_given:-$target}
EOF
    exit 0
fi

log "Verifying"
fail=0
check() { if eval "$2"; then printf '  \033[32mok\033[0m   %s\n' "$1"; else printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=1; fi; }

check "kernel present"                 "compgen -G '$rootmnt/boot/loader/entries/*.conf' >/dev/null"
check "initramfs referenced by an entry" "grep -rq '^initrd ' '$rootmnt/boot/loader/entries/' 2>/dev/null"
check "systemd-boot on the ESP"        "[[ -f '$rootmnt/boot/EFI/systemd/systemd-bootx64.efi' ]]"
check "loader.conf written"            "[[ -f '$rootmnt/boot/loader/loader.conf' ]]"
check "root UUID matches fstab"        "grep -q '$root_uuid' '$rootmnt/etc/fstab'"
check "firmware boot entry created"    "efibootmgr | grep -qi 'linux boot manager'"
check "kernel cmdline written"         "[[ -f '$rootmnt/etc/kernel/cmdline' ]]"

if [[ "$encrypt" == yes ]]; then
    check "LUKS2 container on $cryptpart"  "cryptsetup isLuks '$cryptpart'"
    check "rd.luks.uuid= in the entry"     "grep -rq 'rd.luks.uuid=$luks_uuid' '$rootmnt/boot/loader/entries/'"
fi

if [[ "$want_swap" == yes ]]; then
    check "resume=UUID matches swap"   "grep -rq 'resume=UUID=$swap_uuid' '$rootmnt/boot/loader/entries/'"
    check "swap in fstab"              "grep -q '$swap_uuid' '$rootmnt/etc/fstab'"
    swap_bytes=$(blockdev --getsize64 "$swapdev")
    printf '  info swap %s / RAM %s\n' "$(numfmt --to=iec "$swap_bytes")" "$(numfmt --to=iec "$ram_bytes")"
    (( swap_bytes * 5 >= ram_bytes * 2 )) || warn "swap under 2/5 of RAM - hibernation may fail under load"
fi

if [[ -n "$zram_size" ]]; then
    check "zram config written"        "grep -q 'zram-size' '$rootmnt/etc/systemd/zram-generator.conf'"
    check "zram is not the resume dev" "! grep -rq 'resume=.*zram' '$rootmnt/boot/loader/entries/'"
fi

check "hyprland-uwsm session entry"    "[[ -f '$rootmnt/usr/share/wayland-sessions/hyprland-uwsm.desktop' || -f '$rootmnt/usr/local/share/wayland-sessions/hyprland-uwsm.desktop' ]]"
# Run this one INSIDE the chroot. When dotfiles are used, ~/.config/hypr is a
# symlink to an absolute path that is only valid in the target - read from the
# live system as $rootmnt/... it dangles and the check fails spuriously.
check "hypridle config written"        "fchroot grep -q before_sleep_cmd '/home/$username/.config/hypr/hypridle.conf'"
# Same guard as above: no target passwd exists during a dry run, and an
# unguarded awk would end the script before the verification block runs.
target_uid=""
[[ -r "$rootmnt/etc/passwd" ]] && \
    target_uid="$(awk -F: -v u="$username" '$1==u{print $3}' "$rootmnt/etc/passwd" 2>/dev/null || true)"
check "user owns their config dir"     "[[ -n '$target_uid' && \$(stat -c %u '$rootmnt/home/$username/.config') == '$target_uid' ]]"
check "autorelabel scheduled"          "[[ -f '$rootmnt/.autorelabel' ]]"
check "quickshell installed"           "[[ -x '$rootmnt/usr/bin/quickshell' ]]"
# The font download is the one step here that reaches the public internet at
# install time and is allowed to fail without aborting, so it is the one most
# likely to be silently absent. Its warning scrolls past; a FAIL in this
# summary does not. Without it every glyph in the bar, the launcher, the OSD
# and the power menu renders as an empty box.
#
# Checked at its installed path, deliberately. On the development machine the
# font also exists in ~/.local/share/fonts, hand-placed years-old leftover,
# which is what fontconfig actually resolves there - so that machine renders
# correctly for a reason a fresh install does not share and could never have
# revealed a broken font step.
check "Symbols Nerd Font installed"    "[[ -f '$rootmnt/usr/local/share/fonts/nerd-fonts-symbols/SymbolsNerdFont-Regular.ttf' ]]"
# Without a serif, "serif" and Times New Roman resolve to a monospace font.
check "serif + Liberation fonts installed" "[[ -f '$rootmnt/usr/share/fonts/google-noto-vf/NotoSerif[wght].ttf' && -f '$rootmnt/usr/share/fonts/liberation-serif-fonts/LiberationSerif-Regular.ttf' ]]"
check "Qt WebP image plugin (wallpaper, picker)" "[[ -f '$rootmnt/usr/lib64/qt6/plugins/imageformats/libqwebp.so' ]]"
check "no display manager"             "[[ ! -e '$rootmnt/etc/systemd/system/display-manager.service' ]]"
# nwg-panel declares Supplements: hyprland, so it installs itself unless
# excluded by name. Asserted rather than assumed: a weak dependency that
# arrives by reverse-dependency is invisible to every "what pulled this in"
# query, and this one went unnoticed long enough to be blamed on a package
# that had already been removed.
check "nwg-panel not installed"        "! fchroot rpm -q nwg-panel >/dev/null 2>&1"
# Asserted by RUNNING it, not by checking the package is present: the failure
# mode is an installed CLI that throws ModuleNotFoundError on every call, which
# a package check would not notice.
if [[ "$machine" == laptop ]]; then
    check "powerprofilesctl works"     "fchroot powerprofilesctl get >/dev/null 2>&1"
fi
check "getty autologin drop-in"        "grep -q 'autologin $username' '$rootmnt/etc/systemd/system/getty@tty1.service.d/autologin.conf'"
# Both halves of the power-button handover, because half of it is worse than
# neither. logind reads the key straight from /dev/input, so if the drop-in is
# missing the compositor's binding cannot win and the button silently powers
# the machine off mid-session - exactly what the power menu exists to prevent.
# The long-press line is checked too: it is the fallback that makes turning
# the short press off safe at a console or when the session never starts.
check "power key handed to the session" "grep -q '^HandlePowerKey=ignore' '$rootmnt/etc/systemd/logind.conf.d/00-power-key.conf'"
check "power key long press powers off" "grep -q '^HandlePowerKeyLongPress=poweroff' '$rootmnt/etc/systemd/logind.conf.d/00-power-key.conf'"
# Root's, and served by the theme watcher. A user-owned policy directory is the
# old, too-generous setup; a root-owned one with no watcher is a browser that
# silently stops following themes. See bin/chromium-policy-setup.sh.
if [[ "$browser" == chromium && -n "$dotfiles_repo" ]]; then
    check "chromium policy dir is root's"    "[[ \$(stat -c %u '$rootmnt/etc/chromium/policies/managed' 2>/dev/null) == 0 ]]"
    check "chromium theme watcher enabled"   "[[ -L '$rootmnt/etc/systemd/system/multi-user.target.wants/fd44-chromium-theme.path' ]]"
fi
check "uwsm start hook in profile"     "grep -q 'uwsm check may-start' '$rootmnt/home/$username/.bash_profile'"
check "forced password change in profile" "grep -q 'password-changed' '$rootmnt/home/$username/.bash_profile'"
# The inverse of a check, and the important one: field 3 of the shadow entry
# must NOT be 0. An expired password is rejected by PAM account management on
# the `login -f` path that agetty --autologin uses, so the machine loops on
# getty forever and never reaches a session. Guards against the expiry being
# reintroduced as an apparently obvious hardening tweak.
check "password NOT expired (breaks autologin)" "! grep -q '^$username:[^:]*:0:' '$rootmnt/etc/shadow'"
check "plymouth in initrd"             "rpm --root='$rootmnt' -q plymouth >/dev/null 2>&1"
check "rhgb on kernel cmdline"         "grep -q rhgb '$rootmnt/etc/kernel/cmdline'"
check "browser installed"              "rpm --root='$rootmnt' -q '$browser' >/dev/null 2>&1"
check "terminal installed"             "[[ -x \"\$(fchroot which $terminal 2>/dev/null)\" ]] || rpm --root='$rootmnt' -q '$terminal' >/dev/null 2>&1"

sync
if (( fail )); then
    die "some checks failed - fix them before rebooting (the system is still mounted at $rootmnt)"
fi

log "Install complete"
# Root-only: the log records the dotfiles URL, and a private repo's URL can
# carry a token (https://user:TOKEN@host/...).
run install -m 600 "$logfile" "$rootmnt/var/log/fedora-install.log"

# UNQUOTED on purpose - the summary interpolates $target, $username and the
# rest - which means every backtick and $( ) in the text below RUNS, as root.
# Write commands in plain quotes. A backticked `sudo dnf5 install
# python3-<name>` in here was executed while the message printed, and only
# failed harmlessly because <name> parsed as a redirect from a missing file.
cat <<EOF

  Disk       : $target
  Encryption : $encrypt$( [[ "$encrypt" == yes ]] && echo "  (LUKS2 UUID=$luks_uuid -> LVM $vg_name)" )
  Root       : UUID=$root_uuid  (default subvolume: root)
  Swap       : $( [[ "$want_swap" == yes ]] && echo "UUID=$swap_uuid  ($swap_size on disk, hibernation enabled)" || echo "no disk swap" )
  zram       : $( [[ -n "$zram_size" ]] && echo "$zram_size  (compressed, used before disk swap)" || echo "none" )
  Machine    : $machine        CPU: $cpu_vendor        GPU: $gpu_vendor
  Desktop    : Hyprland + quickshell (autologin on tty1, no display manager)
  Dotfiles   : ${dotfiles_repo:-none}
  Apps       : $browser, $terminal
  User       : $username  (sudo requires the password; root is locked)

  Next:
    umount -R $rootmnt$( [[ "$want_swap" == yes ]] && echo " && swapoff -a" )$( [[ "$encrypt" == yes ]] && echo " && cryptsetup close $mapper_name" ) && reboot

  FIRST BOOT WILL TAKE LONGER THAN USUAL - SELinux is relabeling the whole
  filesystem (the .autorelabel this script scheduled, since fstab/sudoers/
  hypridle/hyprlock/zram/dracut/autologin configs were all written directly
  rather than through rpm). The machine reboots itself once when that
  finishes. Normal, let it run.

  FIRST LOGIN WILL ASK YOU TO CHANGE THE PASSWORD. The account ships with the
  publicly-known password "changeme". The password is deliberately NOT
  expired - agetty's autologin runs "login -f", and PAM rejects an expired
  password on that path instead of prompting, which left the machine in a
  getty respawn loop that never reached a desktop. The forced change lives
  in ~/.bash_profile instead, which runs after login has already succeeded
  and can actually prompt. Until you complete it, treat the machine as
  having no password at all.

  THERE IS NO GREETER. The machine autologins $username on tty1 and starts
  Hyprland from ~/.bash_profile via uwsm, which is what starts
  graphical-session.target - the thing that makes the polkit agent, hypridle
  and the portals work.$( [[ "$encrypt" == yes ]] \
    && echo "  Your LUKS passphrase is the only
  authentication at boot; that is the deliberate trade." \
    || echo "  With encryption off there is NO authentication
  at boot at all: powering the machine on lands straight in a session. The
  disk is readable by anyone who can take it out of the case." )

  If Hyprland ever fails to start you land at a shell on tty1 rather than a
  respawn loop (the profile hook does not use exec), and tty2-tty6 always
  give you a normal login. The uwsm output goes to
  ~/.local/state/uwsm-start.log, not the screen.

  QUICKSHELL SHIPS NO DEFAULT CONFIG. It is a QtQuick toolkit, not a bar, so
  it draws NOTHING without a QML config in ~/.config/quickshell/. If you gave
  this installer a dotfiles repo with a quickshell/ directory, that has been
  symlinked for you and the bar, screen frame and launcher are already
  running. Without one you get a bare Hyprland desktop and will need to write
  a config or clone a community one.

  CHECK WHICH CONFIG
  FILE HYPRLAND ACTUALLY GENERATED before editing anything: this COPR ships
  a Hyprland new enough to use ~/.config/hypr/hyprland.lua (Lua syntax)
  rather than the classic hyprland.conf, and most guides online still assume
  the old format. Check with:
    ls ~/.config/hypr/
  $( [[ "$terminal" != kitty ]] && echo "You also chose $terminal - the same
  \$terminal-style variable (or its Lua equivalent) needs updating in
  whichever config file is actually present." )

  NO NOTIFICATION DAEMON IS INSTALLED either - apps that send desktop
  notifications will silently do nothing until you install one (mako,
  dunst, swaync, ...) or quickshell grows one in its config.

  If uwsm crashes with a Python ModuleNotFoundError the first time you
  start a session, that is a real gap in the COPR's uwsm packaging (it has
  hard-imported modules it doesn't declare as dependencies) - read the
  module name out of the traceback and "sudo dnf5 install python3-<name>".
  python3-pyxdg and python3-dbus are already included above for exactly
  this reason; if a COPR update introduces another one, same fix applies.

$( [[ "$want_swap" == yes ]] && cat <<'HINT'
  Confirm hibernation before you rely on it:
    systemctl hibernate

HINT
)  First boot, before anything else:
    sudo dnf upgrade --refresh

  Hyprland/quickshell came from a third-party COPR ($hypr_copr) - if it
  ever goes stale, "sudo dnf copr disable $hypr_copr" and swap in whatever
  COPR has taken over as the maintained one.
EOF
