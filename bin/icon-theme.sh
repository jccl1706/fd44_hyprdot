#!/usr/bin/env bash
# =========================================================================
# icon-theme.sh - install the Reversal icon theme the palettes ask for
# =========================================================================
#
# Usage:
#   bin/icon-theme.sh            install, or repair an install that drifted
#   bin/icon-theme.sh --status   what the palettes name, and what is installed
#   bin/icon-theme.sh --remove   delete the Reversal themes the palettes name
#
# No root: installs to ~/.local/share/icons, the user's own icon directory,
# which GTK searches before the system ones.
#
# OPT-IN, NOT PART OF THE INSTALLER. Icons are appearance, not breakage - the
# desktop is complete without them, because theme.sh falls back to Adwaita
# while Reversal is missing - and fetching them would add one more network
# step able to fail in the middle of an install.
#
# WHAT GETS INSTALLED is read from themes/*.conf, not listed here. Each
# palette's icon_theme names a variant (Reversal-grey-dark, Reversal-purple),
# and this installs exactly the colour sets those names need. Upstream's
# installer always writes a light AND a dark variant of every colour it is
# given; the variants no palette names are deleted afterwards - except a light
# one that a named -dark variant still needs, because -dark does not carry its
# own apps, mimes or status icons: it symlinks into the light variant for them.
#
# PINNED to one upstream commit, verified after the fetch, so a reinstall a
# year from now puts back the icons this was set up with rather than whatever
# master holds that day. To move the pin: look at upstream, update COMMIT, and
# run this again.
#
# Reversal icon theme by yeyushengfan258, GPL-3.0:
#   https://github.com/yeyushengfan258/Reversal-icon-theme

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UPSTREAM="https://github.com/yeyushengfan258/Reversal-icon-theme"
COMMIT="2c8122287e3bad5a6bf860ddd8c7e3b78cf4d451"    # master, 2026-03-17
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/icons"

# Upstream's colour variants (install.sh THEME_VARIANTS), without the dash.
# "" is its default, blue-folder set, which it names plain "Reversal".
COLOURS=" black blue brown cyan green grey lightblue orange pink purple red "

die() { printf 'icon-theme: %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

(( EUID != 0 )) || die "run this as your user, not root - it installs into your own ~/.local/share/icons"

# Every icon_theme named across the palettes, one per line.
wanted() {
    local f
    for f in "$repo"/themes/*.conf; do
        sed -n 's/^icon_theme=\(.*\)$/\1/p' "$f" | head -1
    done | sed '/^$/d' | sort -u
}

# Reversal[-<colour>][-dark] -> the colour ("" for the default set). Fails
# for a name that is not a Reversal variant this can install.
colour_of() {
    local rest="${1#Reversal}"
    [[ $1 == Reversal* ]] || return 1
    rest="${rest%-dark}"
    [[ -z $rest ]] && { printf ''; return 0; }
    [[ $rest == -* && $COLOURS == *" ${rest#-} "* ]] || return 1
    printf '%s' "${rest#-}"
}

# The directories to keep: every named variant, plus the light variant under
# each named -dark one.
keep_set() {
    local name
    while read -r name; do
        printf '%s\n' "$name"
        # An `if`, not `[[ ]] && printf`: under pipefail a false test as the
        # loop's last command fails the whole pipeline, and `keep=$(keep_set)`
        # then kills the script - which is exactly what the first run did.
        if [[ $name == *-dark ]]; then
            printf '%s\n' "${name%-dark}"
        fi
    done < <(wanted) | sort -u
}

status() {
    local name
    printf 'pinned upstream commit: %s\n' "$COMMIT"
    printf 'install directory:      %s\n' "$DEST"
    printf 'GTK icon theme now:     %s\n\n' \
        "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo unknown)"
    while read -r name; do
        if [[ -f "$DEST/$name/index.theme" ]]; then
            printf '  %-24s installed  %s\n' "$name" "$(du -sh "$DEST/$name" 2>/dev/null | cut -f1)"
        else
            printf '  %-24s MISSING\n' "$name"
        fi
    done < <(keep_set)
}

reapply() {
    # So GTK picks the icons up (or drops them) now, not at the next toggle.
    "$repo/bin/theme.sh" restore >/dev/null 2>&1 || true
}

remove() {
    local name
    while read -r name; do
        [[ -d "$DEST/$name" ]] || continue
        log "removing $DEST/$name"
        rm -rf "${DEST:?}/$name"
    done < <(keep_set)
    reapply
    log "GTK icon theme is now $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)"
}

install_themes() {
    command -v git >/dev/null || die "git is needed - sudo dnf install git"
    command -v gtk-update-icon-cache >/dev/null \
        || die "gtk-update-icon-cache is needed - sudo dnf install gtk-update-icon-cache"

    local -a names=() colours=()
    local name c default=0
    mapfile -t names < <(wanted)
    (( ${#names[@]} )) || { log "no palette in themes/ sets icon_theme - nothing to install"; exit 0; }

    for name in "${names[@]}"; do
        c="$(colour_of "$name")" || die "icon_theme=$name is not a Reversal variant this can install"
        if [[ -z $c ]]; then
            default=1
        elif [[ " ${colours[*]} " != *" $c "* ]]; then
            colours+=("$c")
        fi
    done
    log "palettes want: ${names[*]}"

    # Global, not local: the EXIT trap runs after this function has returned,
    # when a local would already be gone and `set -u` would abort the cleanup.
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp:-}"' EXIT

    # A shallow fetch of exactly the pinned commit - GitHub serves a reachable
    # commit by its full hash - and a check that it is what arrived.
    log "fetching Reversal at ${COMMIT:0:12}"
    git init -q "$tmp/src"
    git -C "$tmp/src" fetch -q --depth 1 "$UPSTREAM" "$COMMIT" \
        || die "fetch failed - check the network, or whether $COMMIT still exists upstream"
    git -C "$tmp/src" -c advice.detachedHead=false checkout -q FETCH_HEAD
    [[ "$(git -C "$tmp/src" rev-parse HEAD)" == "$COMMIT" ]] \
        || die "fetched commit is not the pinned one - refusing to install"

    mkdir -p "$DEST"

    # STRAIGHT INTO $DEST, not a staging directory moved into place afterwards:
    # upstream writes one symlink as an absolute path (preferences/22), which
    # would point back into the staging directory after a move. Its installer
    # only ever replaces its own Reversal* directories.
    local -a made=()
    if (( default )); then
        log "installing the default colour set"
        ( cd "$tmp/src" && ./install.sh -d "$DEST" ) >/dev/null
        made+=(Reversal Reversal-dark)
    fi
    if (( ${#colours[@]} )); then
        log "installing colour sets: ${colours[*]}"
        ( cd "$tmp/src" && ./install.sh -d "$DEST" -t "${colours[@]}" ) >/dev/null
        for c in "${colours[@]}"; do made+=("Reversal-$c" "Reversal-$c-dark"); done
    fi

    # Delete what this run wrote but no palette needs. Only what THIS run
    # made: a Reversal colour installed by hand, outside these palettes, is
    # left alone.
    local keep; keep="$(keep_set)"
    for name in "${made[@]}"; do
        if ! grep -qxF "$name" <<<"$keep"; then
            rm -rf "${DEST:?}/$name"
        fi
    done

    for name in "${names[@]}"; do
        [[ -f "$DEST/$name/index.theme" ]] || die "install finished but $DEST/$name is missing"
    done

    reapply
    printf '\n'
    status
}

case "${1:-}" in
    ""|install) install_themes ;;
    --status)   status ;;
    --remove)   remove ;;
    -h|--help)  sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0" ;;
    *)          die "usage: icon-theme.sh [--status|--remove]" ;;
esac
