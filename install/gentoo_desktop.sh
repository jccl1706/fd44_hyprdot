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

# THE FONTS, WHICH ARE NOT DECORATION HERE. Two of them are named by the
# configs this repo links, and fontconfig answers a name it does not have with
# a SUBSTITUTION rather than an error - so a missing font costs you nothing
# visible at install time and everything afterwards. On a first Gentoo desktop
# only Liberation was present, and the result was a bar rendered in Liberation
# Sans and a terminal in Liberation Mono, with nothing anywhere reporting a
# problem.
#
#   Inter Variable    quickshell/Theme.qml font
#   Noto Sans Mono    kitty.conf font_family
#   Symbols Nerd Font quickshell/Theme.qml glyphFont - every icon in the bar
#
# THE REST IS WHAT FEDORA HAS, because that is the comparison that matters:
# Noto for the generic families, DejaVu beside it, emoji so that a browser can
# draw them at all, and CJK so that pages in those scripts are text rather than
# boxes. Liberation stays - it is what answers when a document asks for Arial
# or Times by name, which is the job it exists for.
FONTS=(
    media-fonts/inter               # GURU; rsms upstream, as Fedora packages
    media-fonts/noto
    media-fonts/noto-emoji
    media-fonts/noto-cjk
    media-fonts/dejavu
    media-fonts/jetbrains-mono
    media-fonts/symbols-nerd-font   # in ::gentoo, unlike on Fedora
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
for p in "${MAIN[@]}" "${GURU[@]}" "${FONTS[@]}"; do
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

# --- fontconfig -----------------------------------------------------------
#
# THE RENDERING KNOBS ARE ALREADY RIGHT on a stock Gentoo - hinting-slight,
# yes-antialias and lcdfilter-default are enabled by default, and freetype is
# built with harfbuzz, cleartype-hinting and adobe-cff. Fedora does the same
# and enables no subpixel config either; both are grayscale antialiased. There
# was nothing to fix there, which is worth writing down because it is where
# everyone looks first.
#
# WHAT DIFFERS IS WHICH FONT ANSWERS A GENERIC NAME. Fedora ships a per-font
# priority config for each family it packages, numbered so they sort - Noto at
# 56, DejaVu at 57, Liberation at 59. Gentoo ships none of them, so the static
# list in 60-latin.conf decides and Liberation wins every unstyled page.
note "fontconfig: the generics, and the configs that need these fonts to exist"

# Small sizes and non-latin faces look better unhinted; these configs could not
# be enabled before because the fonts they name were not installed.
for c in 20-unhint-small-dejavu-sans.conf \
         20-unhint-small-dejavu-sans-mono.conf \
         20-unhint-small-dejavu-serif.conf \
         25-unhint-nonlatin.conf \
         75-noto-emoji-fallback.conf; do
    eselect fontconfig enable "$c" >/dev/null 2>&1 \
        && printf '    enabled  %s\n' "$c" \
        || printf '    skipped  %s%s (not available)%s\n' "$dim" "$c" "$reset"
done

# `|| true` BECAUSE OF set -e: with no local.conf to save, the && chain returns
# non-zero and takes the whole script down - on the ordinary first install.
if [[ -e /etc/fonts/local.conf ]]; then
    cp -a /etc/fonts/local.conf "/etc/fonts/local.conf.before-fd44-$(date +%F)" || true
    note "existing local.conf saved beside it"
fi
cat > /etc/fonts/local.conf <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!--
  Written by install/gentoo_desktop.sh (fd44_hyprdot).

  Prefer Noto for the generic families, which is what Fedora resolves to.
  Gentoo does not ship Fedora's per-font priority configs, so without this the
  static list in 60-latin.conf wins and everything unstyled renders in
  Liberation - a metric-compatible Arial/Times stand-in, meant for matching
  document layout rather than for reading all day.
-->
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Sans</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>Noto Serif</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>Noto Sans Mono</family></prefer>
  </alias>
</fontconfig>
XML
note "written /etc/fonts/local.conf"
fc-cache -fr >/dev/null 2>&1 || true

# Named rather than assumed: a substitution here is silent, so it is checked.
printf '\n  %s%-20s %s%s\n' "$bold" "asked for" "resolves to" "$reset"
for f in "Inter Variable" "Symbols Nerd Font" "Noto Sans Mono" sans-serif serif monospace emoji; do
    printf '  %-20s %s\n' "$f" "$(fc-match "$f" 2>/dev/null | sed 's/:.*//')"
done
printf '\n'

note "done"
# Unlike on Fedora, where the only Nerd Font in the repositories is a TeX one
# and bin/install-nerd-font.sh has to fetch it, ::gentoo packages it - so it is
# in FONTS above and there is nothing to download by hand here.
printf '  %sthe config comes from the checkout, as on the other machines:%s\n' "$dim" "$reset"
printf '    bin/link-dotfiles.sh\n'
printf '  %sthen start it from the tty:%s  Hyprland\n\n' "$dim" "$reset"
