#!/usr/bin/env bash
# =========================================================================
# gtk-theme.sh - install the Rosé Pine GTK theme the palettes ask for
# =========================================================================
#
# Usage:
#   bin/gtk-theme.sh            install, or repair an install that drifted
#   bin/gtk-theme.sh --status   what the palettes name, and what is installed
#   bin/gtk-theme.sh --remove   delete the GTK themes the palettes name
#
# No root: installs to ~/.local/share/themes, the user's own theme directory.
#
# WHY A THEME AND NOT GENERATED CSS. bin/theme.sh generates the colours for
# every other consumer, and could not for this one. GTK never re-reads
# ~/.config/gtk-N.0/gtk.css - measured with a probe window whose stylesheet was
# rewritten underneath it, which stayed its original colour on both GTK3 and
# GTK4. What GTK3 DOES do is reload when gtk-theme-name changes, because that
# is a different theme rather than the same file again:
#
#   probe under one theme    #ff0000 100%
#   switched to another      #00cc00 100%   same process, no restart
#
# So the palette has to arrive as a NAMED THEME. Generating one was tried and
# is a trap: @define-color overrides after an @import of Adwaita are ignored,
# because Adwaita resolves its own colour names first, and overriding it with
# explicit rules instead means hand-writing a GTK theme - every widget, every
# state - which is exactly the maintenance this repo avoids elsewhere.
#
# Upstream already ships one, and it is the RIGHT one: both palettes in
# themes/ are Rosé Pine, so its Dawn and Moon variants and this repo's cream
# and dark agree by construction rather than by copying hex values about.
#
# PINNED to one upstream commit, verified after the fetch, so a reinstall a
# year from now produces what was reviewed rather than whatever master has
# become.
#
# Rosé Pine GTK theme by the Rosé Pine team, MIT:
#   https://github.com/rose-pine/gtk

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UPSTREAM="https://github.com/rose-pine/gtk"
COMMIT="3a11f84e11685aacaa749deea1e9f02872b99fdf"    # main, 2026-09-17
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/themes"

die() { printf 'gtk-theme: %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

(( EUID != 0 )) || die "run this as your user, not root - it installs into your own ~/.local/share/themes"

# Every gtk_theme named across the palettes, one per line.
wanted() {
    local f
    for f in "$repo"/themes/*.conf; do
        sed -n 's/^gtk_theme=\(.*\)$/\1/p' "$f" | head -1
    done | sed '/^$/d' | sort -u
}

# The GTK4 stylesheet that goes with a GTK3 theme directory. Upstream names
# them differently - gtk3/rose-pine-moon-gtk beside gtk4/rose-pine-moon.css -
# so the "-gtk" suffix comes off.
css_for() { printf '%s.css\n' "${1%-gtk}"; }

status() {
    printf 'pinned upstream commit: %s\n' "$COMMIT"
    printf 'install directory:      %s\n' "$DEST"
    printf 'GTK theme now:          %s\n\n' \
        "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo '(no gsettings)')"
    local name
    while read -r name; do
        if [[ -f "$DEST/$name/index.theme" ]]; then
            printf '  %-24s installed  %s  gtk4 css: %s\n' "$name" \
                "$(du -sh "$DEST/$name" 2>/dev/null | cut -f1)" \
                "$([[ -f "$DEST/$name/gtk-4.0/gtk.css" ]] && echo yes || echo MISSING)"
        else
            printf '  %-24s MISSING\n' "$name"
        fi
    done < <(wanted)
}

remove() {
    local name
    while read -r name; do
        [[ $name == rose-pine*-gtk || $name == rose-pine-gtk ]] \
            || { printf 'gtk-theme: not removing %s - not a Rosé Pine variant\n' "$name" >&2; continue; }
        rm -rf "${DEST:?}/$name" && log "removed $name"
    done < <(wanted)
    printf '\nGTK apps fall back to Adwaita until this is run again.\n'
}

install_themes() {
    local -a names
    mapfile -t names < <(wanted)
    (( ${#names[@]} )) || { log "no palette in themes/ sets gtk_theme - nothing to install"; exit 0; }
    log "palettes want: ${names[*]}"

    # Global, not local: the EXIT trap runs after this function has returned,
    # when a local would already be gone and `set -u` would abort the cleanup.
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp:-}"' EXIT

    # A shallow fetch of exactly the pinned commit, and a check that it is what
    # arrived.
    log "fetching Rosé Pine GTK at ${COMMIT:0:12}"
    git init -q "$tmp/src"
    git -C "$tmp/src" fetch -q --depth 1 "$UPSTREAM" "$COMMIT" \
        || die "fetch failed - check the network, or whether $COMMIT still exists upstream"
    git -C "$tmp/src" -c advice.detachedHead=false checkout -q FETCH_HEAD
    [[ "$(git -C "$tmp/src" rev-parse HEAD)" == "$COMMIT" ]] \
        || die "fetched commit is not the pinned one - refusing to install"

    mkdir -p "$DEST"

    local name css
    for name in "${names[@]}"; do
        [[ -d "$tmp/src/gtk3/$name" ]] \
            || die "gtk_theme=$name is not a variant this upstream ships (looked for gtk3/$name)"

        # Replaced whole, not merged: a partial theme left over from an older
        # commit would be worse than no theme at all, and upstream owns every
        # file under this directory.
        rm -rf "${DEST:?}/$name"
        cp -r "$tmp/src/gtk3/$name" "$DEST/$name"

        # THE GTK4 STYLESHEET GOES INSIDE THE THEME. Upstream keeps the two
        # apart; here they travel together, because bin/theme.sh copies this
        # file to ~/.config/gtk-4.0/gtk.css when the theme is selected and
        # needs to find it without knowing anything about upstream's layout.
        # libadwaita apps read only that copy - they ignore gtk-theme-name
        # entirely - so this is the only route the palette has into GTK4.
        css="$(css_for "$name")"
        if [[ -f "$tmp/src/gtk4/$css" ]]; then
            mkdir -p "$DEST/$name/gtk-4.0"
            cp "$tmp/src/gtk4/$css" "$DEST/$name/gtk-4.0/gtk.css"
        else
            printf 'gtk-theme: warning - upstream has no gtk4/%s; GTK4 apps will not follow %s\n' \
                "$css" "$name" >&2
        fi
        log "installed $name"
    done

    for name in "${names[@]}"; do
        [[ -f "$DEST/$name/index.theme" ]] || die "install finished but $DEST/$name is missing"
    done

    printf '\n'
    status
    printf '\nRun bin/theme.sh set <theme> to apply it.\n'
}

case "${1:-}" in
    ""|install) install_themes ;;
    --status)   status ;;
    --remove)   remove ;;
    -h|--help)  sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0" ;;
    *)          die "usage: gtk-theme.sh [--status|--remove]" ;;
esac
