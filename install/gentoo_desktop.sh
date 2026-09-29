#!/usr/bin/env bash
# =========================================================================
# gentoo_desktop.sh - the fd44 desktop on Gentoo: Hyprland and quickshell
# =========================================================================
#
# Usage:  sudo install/gentoo_desktop.sh --list     what the overlays offer
#         sudo install/gentoo_desktop.sh           install it
#
# Run ON the Gentoo machine, after the driver works.
#
# HYPRLAND AND QUICKSHELL ARE NOT IN ::gentoo. They live in GURU, which is
# Gentoo's user-contributed repository: reviewed by its own contributors
# rather than by Gentoo developers, kept in the official repository list, and
# the usual home for things moving faster than a distribution wants to track.
# That is a real difference in guarantee, and it is the price of running the
# same desktop here as on the other two machines.
#
# ~amd64 IS EXPECTED HERE. Nothing in GURU is stable-keyworded; the packages
# named below are accepted individually rather than opening testing across
# the system, so an unrelated `emerge -u` cannot quietly pull unstable
# versions of anything else.
#
# IT LISTS BEFORE IT INSTALLS. GURU changes, and a script that assumes a
# package name is a script that fails confusingly six months from now. --list
# prints what is actually there.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sdesktop:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

LIST_ONLY=0
[[ ${1-} == --list ]] && LIST_ONLY=1

(( EUID == 0 )) || die "must run as root"
[[ -f /etc/gentoo-release ]] || die "this is for the Gentoo install"

# What the fd44 desktop is made of. Split by where it comes from, because the
# main tree needs no ceremony and GURU does.
MAIN=(
    x11-terms/kitty                 # the terminal the config themes
    gui-apps/grim gui-apps/slurp    # screenshots, which bin/ scripts call
    gui-apps/wl-clipboard
    app-misc/jq
    sys-apps/dbus
)
GURU=(
    gui-wm/hyprland
    gui-apps/quickshell
    gui-apps/hypridle
    gui-apps/hyprlock
    gui-apps/hyprpolkitagent
    gui-libs/xdg-desktop-portal-hyprland
)

# TWO OVERLAYS, BECAUSE THEY CARRY DIFFERENT HALVES. GURU has quickshell and
# nothing else on this list; Hyprland and its companions live in hyproverlay
# (codeberg.org/hyproverlay/hyproverlay), which is likewise in Gentoo's
# official repository listing. Checked rather than assumed: GURU alone
# reported six of the eight packages missing.
note "enabling the overlays"
emerge --getbinpkg --noreplace app-eselect/eselect-repository >/dev/null
for repo in guru hyproverlay; do
    eselect repository list -i 2>/dev/null | grep -qE "\b$repo\b" || eselect repository enable "$repo"
    note "syncing $repo"
    emaint sync --repo "$repo" >/dev/null 2>&1 || emaint sync --repo "$repo"
done

# --- what is actually available -------------------------------------------

available=()
missing=()
printf '\n  %s%-40s %s%s\n' "$bold" "package" "newest ebuild" "$reset"
for p in "${MAIN[@]}" "${GURU[@]}"; do
    # `|| true` BECAUSE OF pipefail. The script asks for `set -o pipefail`,
    # and when a package is absent the leading `ls` fails, which fails the
    # whole pipeline, which under `set -e` kills the script - in the middle
    # of the very listing whose job is to report absences calmly. It stopped
    # silently at the first package that was not there.
    v="$(ls /var/db/repos/*/"$p"/*.ebuild 2>/dev/null | sed 's|.*/||; s|\.ebuild$||' | sort -V | tail -1 || true)"
    if [[ -n $v ]]; then
        printf '  %-40s %s\n' "$p" "$v"
        available+=("$p")
    else
        printf '  %-40s %snot found%s\n' "$p" "$dim" "$reset"
        missing+=("$p")
    fi
done
printf '\n'

(( ${#missing[@]} )) && warn "${#missing[@]} not found: ${missing[*]}"
(( LIST_ONLY )) && exit 0
(( ${#available[@]} )) || die "nothing to install"

# --- keywords, per package ------------------------------------------------

# ~amd64 IS NOT ENOUGH FOR A LIVE EBUILD. Everything hyproverlay carries is
# -9999 - built from git master rather than a release - and a live ebuild has
# no KEYWORDS at all, so ~amd64 does not unmask it. `**` does, and means
# exactly "I accept an ebuild with no keywords".
#
# WORTH KNOWING WHAT THAT SIGNS UP FOR: these packages follow Hyprland's git
# master, so an update can bring today's upstream breakage, and the version
# you have is whatever the tree looked like when you emerged. It is the only
# form on offer for Hyprland on Gentoo.
note "accepting these packages, live ones with ** and the rest with ~amd64"
mkdir -p /etc/portage/package.accept_keywords
{
    printf '# Written by install/gentoo_desktop.sh (fd44_hyprdot).\n'
    printf '# Named individually rather than a blanket ACCEPT_KEYWORDS, so an\n'
    printf '# unrelated `emerge -u` cannot pull unstable versions of the system.\n'
    for p in "${available[@]}"; do
        v="$(ls /var/db/repos/*/"$p"/*.ebuild 2>/dev/null | sed 's|.*/||; s|\.ebuild$||' | sort -V | tail -1 || true)"
        if [[ $v == *-9999 ]]; then printf '%s **\n' "$p"; else printf '%s ~amd64\n' "$p"; fi
    done
} > /etc/portage/package.accept_keywords/fd44-desktop
printf '\n'; cat /etc/portage/package.accept_keywords/fd44-desktop | grep -v '^#' | sed 's/^/    /'

note "installing ${#available[@]} packages - quickshell is Qt6 and will compile"
# KEYWORDS RESOLVED BY PORTAGE, the same as the gaming stage - and for the
# same reason, which I had already learned there and failed to apply here:
# these packages' DEPENDENCIES are keyworded too, and they cannot be
# enumerated from outside. dev-cpp/sdbus-c++, pulled in by the Hyprland
# portal, was the one that stopped this.
#
# Licences stay manual; nothing on this list is non-free.
emerge --getbinpkg --autounmask --autounmask-continue \
    --autounmask-keep-keywords=n "${available[@]}"

note "done"
printf '\n  %sthe Symbols Nerd Font is packaged nowhere; the repo fetches it:%s\n' "$dim" "$reset"
printf '    bin/install-nerd-font.sh\n'
printf '  %sthe config comes from the checkout, as on the other machines:%s\n' "$dim" "$reset"
printf '    bin/link-dotfiles.sh\n'
printf '  %sthen start it from the tty:%s  Hyprland\n\n' "$dim" "$reset"
