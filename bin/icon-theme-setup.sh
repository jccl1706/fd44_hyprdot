#!/usr/bin/env bash
# =========================================================================
# icon-theme-setup.sh - the Tela icon theme, from upstream
# =========================================================================
#
# Usage:  bin/icon-theme-setup.sh [--go] [VARIANT]
#         bin/icon-theme-setup.sh --remove
#
# NOT PACKAGED BY FEDORA, so it comes from its own repository. This clones
# it into ~/.local/src, runs its installer into ~/.local/share/icons and
# selects it - no root at any point, because the theme belongs to this
# account rather than the system.
#
# NOT THE KDE STORE COPY EITHER. The store upload is whatever the author
# last exported there - ten months old when this was written - while the
# repository is current, and `git pull` updates it.
#
# WHAT THE UPSTREAM INSTALLER DOES, checked before it was first run: it
# picks ~/.local/share/icons when not root, writes only under that
# directory, and its single rm -rf targets the theme folder it is about to
# replace. It never calls sudo.
set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sicons:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

REPO_URL="https://github.com/vinceliuice/Tela-icon-theme.git"
SRC="$HOME/.local/src/Tela-icon-theme"
NAME="Tela"

(( EUID == 0 )) && die "run this as yourself - it installs into your home"
command -v git >/dev/null || die "git is not installed"

GO=0; VARIANT=""
for a in "$@"; do
    case "$a" in
        --go) GO=1 ;;
        --remove) [[ -x $SRC/install.sh ]] || die "not installed from $SRC"
                  "$SRC/install.sh" -r; exit 0 ;;
        *) VARIANT="$a" ;;
    esac
done

if (( ! GO )); then
    note "would clone or update $REPO_URL into $SRC"
    note "would run install.sh ${VARIANT:-(standard)} -> ~/.local/share/icons"
    note "would set the icon theme to ${NAME}${VARIANT:+-$VARIANT}"
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

mkdir -p "$(dirname "$SRC")"
if [[ -d $SRC/.git ]]; then
    note "updating the checkout"
    git -C "$SRC" pull --ff-only
else
    note "cloning"
    git clone --depth 1 "$REPO_URL" "$SRC"
fi
note "at $(git -C "$SRC" log --oneline -1)"

note "installing"
( cd "$SRC" && ./install.sh ${VARIANT:+"$VARIANT"} )

theme="$NAME${VARIANT:+-$VARIANT}"
note "selecting $theme"
kwriteconfig6 --file kdeglobals --group Icons --key Theme "$theme"
# plasmashell caches icons for its own panels; applications pick the change up
# as they start.
systemctl --user restart plasma-plasmashell.service 2>/dev/null || true
note "done - $(kreadconfig6 --file kdeglobals --group Icons --key Theme)"
