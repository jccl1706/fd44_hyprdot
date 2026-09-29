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
    media-fonts/nerd-fonts          # Symbols Nerd Font: every glyph in the bar
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

note "enabling GURU"
emerge --getbinpkg --noreplace app-eselect/eselect-repository >/dev/null
eselect repository list -i 2>/dev/null | grep -q '\bguru\b' || eselect repository enable guru
emaint sync --repo guru >/dev/null 2>&1 || emaint sync --repo guru

# --- what is actually available -------------------------------------------

available=()
missing=()
printf '\n  %s%-40s %s%s\n' "$bold" "package" "newest ebuild" "$reset"
for p in "${MAIN[@]}" "${GURU[@]}"; do
    v="$(ls /var/db/repos/*/"$p"/*.ebuild 2>/dev/null | sed 's|.*/||; s|\.ebuild$||' | sort -V | tail -1)"
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

note "accepting ~amd64 for these packages only"
mkdir -p /etc/portage/package.accept_keywords
{
    printf '# Written by install/gentoo_desktop.sh (fd44_hyprdot).\n'
    printf '# GURU carries no stable keywords, and the fd44 desktop moves faster than\n'
    printf '# stable would allow anyway. Named individually so that an unrelated\n'
    printf '# `emerge -u` cannot pull unstable versions of the rest of the system.\n'
    for p in "${available[@]}"; do printf '%s ~amd64\n' "$p"; done
} > /etc/portage/package.accept_keywords/fd44-desktop

note "installing ${#available[@]} packages - quickshell is Qt6 and will compile"
emerge --getbinpkg --autounmask-continue "${available[@]}"

note "done"
printf '\n  %sthe config comes from the checkout, as on the other machines:%s\n' "$dim" "$reset"
printf '    bin/link-dotfiles.sh\n'
printf '  %sthen start it from the tty:%s  Hyprland\n\n' "$dim" "$reset"
