#!/usr/bin/env bash
# =========================================================================
# icon-theme-hatter.sh - install the Hatter icon theme the palettes ask for
# =========================================================================
#
# Usage:
#   bin/icon-theme-hatter.sh            install, or repair an install that drifted
#   bin/icon-theme-hatter.sh --status   what is installed, and what is selected
#   bin/icon-theme-hatter.sh --remove   delete it again
#
# No root: installs to ~/.local/share/icons, which GTK and Qt search before the
# system directories.
#
# OPT-IN, NOT PART OF THE INSTALLER, for the same reason bin/icon-theme.sh is
# not: icons are appearance, not breakage. theme.sh falls back to Adwaita while
# this is missing, so a machine without it has a complete desktop in the wrong
# icons rather than a broken one.
#
# WHY IT IS NOT COSMETIC ANYWAY. Adwaita has no icon for alacritty, which ships
# its only icon as /usr/share/pixmaps/Alacritty.svg - a legacy path no icon
# theme lookup searches. With Adwaita selected, the bar's focused-window pill
# had nothing to draw and showed Qt's missing-image checkerboard. Hatter
# carries scalable/apps/Alacritty.svg, so selecting it fixes that as a side
# effect. kitty is unaffected either way because it installs into hicolor
# itself, which is why only one of the two terminals ever looked wrong.
#
# THE -kde VARIANTS ARE NOT INSTALLED. Upstream ships Hatter-kde, -kde-dark and
# -kde-light, which inherit Breeze - not present on these machines - so every
# icon they do not draw themselves would have no fallback. The plain variant
# inherits Adwaita, which is always there.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sicon-theme-hatter:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

(( EUID == 0 )) && die "do not run this with sudo - it installs into your home directory"

DEST="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
SRC="$HOME/.local/src/Hatter"
URL="https://github.com/Mibea/Hatter.git"
NAME="Hatter"

case "${1-}" in
    --status)
        printf 'installed:  '
        if [[ -f "$DEST/$NAME/index.theme" ]]; then
            printf '%s  %s\n' "$NAME" "$(du -sh "$DEST/$NAME" 2>/dev/null | cut -f1)"
        else
            printf 'no\n'
        fi
        printf 'selected:   %s\n' \
            "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
        printf 'palettes:   %s\n' \
            "$(grep -h '^icon_theme' "$(dirname "${BASH_SOURCE[0]}")/../themes/"*.conf 2>/dev/null \
               | cut -d= -f2 | sort -u | tr '\n' ' ')"
        exit 0
        ;;
    --remove)
        rm -rf "${DEST:?}/$NAME"
        log "removed $DEST/$NAME"
        log "run bin/theme.sh set \"\$(bin/theme.sh current)\" to fall back to Adwaita"
        exit 0
        ;;
    "") ;;
    *) die "unknown argument: $1" ;;
esac

# A SHALLOW CLONE, KEPT. The repository is the only distribution upstream
# offers - there is no release archive - and keeping it means the next run
# updates rather than re-downloads 450 MB of variants.
command -v git >/dev/null || die "git is not installed"
if [[ -d $SRC/.git ]]; then
    log "updating $SRC"
    git -C "$SRC" fetch -q --depth 1 origin && git -C "$SRC" reset -q --hard origin/HEAD
else
    log "cloning $URL"
    mkdir -p "$(dirname "$SRC")"
    git clone -q --depth 1 "$URL" "$SRC"
fi

[[ -d "$SRC/$NAME" ]] || die "upstream has no '$NAME' directory - it was renamed"

log "installing $NAME into $DEST"
mkdir -p "$DEST"
rm -rf "${DEST:?}/$NAME"
cp -a "$SRC/$NAME" "$DEST/$NAME"
gtk-update-icon-cache -q -f "$DEST/$NAME" >/dev/null 2>&1 || true

printf '\n'
log "installed: $(du -sh "$DEST/$NAME" | cut -f1)"
log "select it with: bin/theme.sh set \"\$(bin/theme.sh current)\""
log "then rebuild the bridge quickshell reads: bin/icon-bridge.sh"
