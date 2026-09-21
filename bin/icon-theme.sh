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

# Apps Reversal has no icon for, drawn with one of its own icons instead, as
# "<icon the app asks for>=<Reversal icon it borrows>". Without an alias such
# an app falls back to its packaged icon and sits in the launcher in a
# different style from everything around it.
#
# Symlinks in the light set's apps/scalable, re-added on every run (upstream's
# installer replaces the whole directory). The -dark variants reach that
# directory through a symlink of their own, so they need nothing extra.
#
# Apps with no Reversal icon of their own, mapped to one it does ship.
# `--status` re-runs that check across every displayed desktop entry on the
# machine, so this list is verifiable rather than remembered.
#
# Each of these was chosen by looking at what Reversal actually has - all four
# are close matches rather than generic stand-ins, and the first three were
# only found because the gap check was fixed to scan every XDG data dir instead
# of /usr/share alone, which on NixOS meant scanning nothing.
#
#   btop         htop is the same kind of program - a terminal monitor, rather
#                than the GNOME-style graph utilities-system-monitor draws.
#   nix-snowflake  distributor-logo-nixos IS the NixOS logo, which is what
#                nix-snowflake means. Used by the NixOS Manual entry.
#   CoolerControl  coolero is the same program under its former name; upstream
#                renamed itself and Reversal still ships the old icon.
#   protonup-qt  protontricks is its nearest sibling - both manage Proton and
#                Wine runners for Steam. Not identical, but the same shelf.
ALIASES=(
    "btop=htop"
    "nix-snowflake=distributor-logo-nixos"
    "org.coolercontrol.CoolerControl=coolero"
    "protonup-qt=protontricks"
)

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

    local gaps; gaps="$(icon_gaps)"
    printf '\napps with no Reversal icon (add an alias to ALIASES):\n%s\n' "${gaps:-  none}"
}

apply_aliases() {
    local name dir pair missing target
    while read -r name; do
        dir="$DEST/$name/apps/scalable"
        # A -dark variant's apps/scalable IS the light set's, through a
        # symlink - linking there too would only write the same file twice.
        [[ -d $dir && ! -L $dir ]] || continue
        for pair in "${ALIASES[@]}"; do
            missing="${pair%%=*}"
            target="${pair#*=}"
            if [[ ! -e "$dir/$target.svg" ]]; then
                printf 'icon-theme: alias %s: %s has no %s.svg to borrow\n' "$missing" "$name" "$target" >&2
                continue
            fi
            # Upstream shipped a real icon since the alias was written - use it.
            if [[ -e "$dir/$missing.svg" && ! -L "$dir/$missing.svg" ]]; then
                continue
            fi
            ln -sfn "$target.svg" "$dir/$missing.svg"
        done
    done < <(keep_set)

    # GTK and Qt both trust icon-theme.cache over the directory itself, so a
    # cache written before the links were made hides them. Rebuild every set,
    # -dark included: its cache indexes the light set's icons through the link.
    while read -r name; do
        if [[ -d "$DEST/$name" ]]; then
            gtk-update-icon-cache -q -f "$DEST/$name" >/dev/null 2>&1 || true
        fi
    done < <(keep_set)
}

# Displayed desktop entries whose Icon= the first installed Reversal set has
# no app icon for. Those fall back to their own, differently styled icon.
icon_gaps() {
    local set="" name f icon
    while read -r name; do
        [[ -d "$DEST/$name/apps/scalable" ]] && { set="$DEST/$name/apps/scalable"; break; }
    done < <(keep_set)
    [[ -n $set ]] || return 0
    # EVERY XDG DATA DIR, not /usr/share alone. On Fedora those are the same
    # place and this looked correct for a year; on NixOS there is no
    # /usr/share at all and the loop scanned nothing, reporting "no gaps"
    # because it had examined no applications - a false clean bill of health.
    # Measured there: 0 desktop files found where 20 exist under
    # /run/current-system/sw/share/applications.
    local -a appdirs=("${XDG_DATA_HOME:-$HOME/.local/share}/applications")
    local dd
    local IFS=:
    for dd in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do appdirs+=("$dd/applications"); done
    unset IFS
    for f in "${appdirs[@]}"/*.desktop; do
        [[ -f $f ]] || continue
        grep -q '^NoDisplay=true' "$f" && continue
        icon="$(sed -n 's/^Icon=//p' "$f" | head -1)"
        [[ -z $icon || $icon == /* ]] && continue
        [[ -e "$set/$icon.svg" ]] || printf '  %-36s Icon=%s\n' "$(basename "$f")" "$icon"
    done
}

reapply() {
    # So GTK picks the icons up (or drops them) now, not at the next toggle.
    "$repo/bin/theme.sh" restore >/dev/null 2>&1 || true
}

remove() {
    local name
    while read -r name; do
        # Only names this script could have installed. A palette naming some
        # other theme - or a path like ../.. - must never reach rm -rf.
        if ! colour_of "$name" >/dev/null; then
            printf 'icon-theme: not removing %s - not a Reversal variant\n' "$name" >&2
            continue
        fi
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

    apply_aliases
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
