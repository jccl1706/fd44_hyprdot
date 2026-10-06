#!/usr/bin/env bash
# =========================================================================
# tela-battery-profiles.sh - the battery icons Tela does not ship
# =========================================================================
#
# Usage:  bin/tela-battery-profiles.sh [--go] [--remove]
#
# WHY THE BATTERY LOOKED WRONG. Plasma 6's battery applet does not ask for
# "battery-040". With a power profile active - which bin/plasma-setup.sh
# sets - it asks for
#
#     battery-040-profile-balanced
#     battery-040-charging-profile-performance
#
# and so on. Breeze ships all of those; Tela ships only the plain names. So
# the one icon in the tray that had no Tela version fell back to Breeze and
# sat there looking like a different icon theme, because it was one.
#
# WHAT THIS DOES: for every charge level Tela already draws, it adds the
# profile spellings as SYMLINKS to that same file. The profile is then not
# distinguishable from the icon - which is the trade - but the tray is one
# theme again, and the profile is readable from the applet itself.
#
# Symlinks rather than copies: 90 names pointing at 30 files, and an upstream
# update that redraws a battery redraws all of its spellings at once.
set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%stela:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

THEME="${ICON_THEME:-Tela}"
ROOT="$HOME/.local/share/icons/$THEME"
PROFILES=(balanced performance powersave)

[[ -d $ROOT ]] || die "$ROOT is not there - run bin/icon-theme-setup.sh first"

mode="${1:---dry}"
made=0; removed=0

# THE @2x DIRECTORIES ARE SYMLINKS TO THEIR BASE - 22@2x -> 22, and so on for
# every size Tela ships. Walking them too counts and creates everything twice:
# the dry run said 414 where the real number is 207, and a second --go would
# have reported "nothing to do" for links it had just made through the other
# name. -P on the loop variable is not enough; the directory itself has to be
# tested.
for dir in "$ROOT"/*/panel; do
    [[ -d $dir ]] || continue
    [[ -L "$(dirname "$dir")" ]] && continue
    for src in "$dir"/battery-[0-9]*.svg; do
        [[ -f $src ]] || continue
        base="$(basename "$src" .svg)"
        # Skip anything that is already a profile spelling.
        [[ $base == *-profile-* ]] && continue
        for p in "${PROFILES[@]}"; do
            link="$dir/$base-profile-$p.svg"
            if [[ $mode == --remove ]]; then
                [[ -L $link ]] && { rm -f "$link"; removed=$(( removed + 1 )); }
            elif [[ ! -e $link ]]; then
                if [[ $mode == --go ]]; then
                    ln -s "$base.svg" "$link"
                fi
                made=$(( made + 1 ))
            fi
        done
    done
done

case "$mode" in
    --remove) note "removed $removed symlinks"; gtk-update-icon-cache -f "$ROOT" >/dev/null 2>&1 || true ;;
    --go)     note "created $made symlinks under $ROOT"
              gtk-update-icon-cache -f "$ROOT" >/dev/null 2>&1 || true
              note "log out and back in, or restart plasmashell, to see them" ;;
    *)        note "would create $made symlinks under $ROOT"
              warn "DRY RUN. Re-run with --go." ;;
esac
