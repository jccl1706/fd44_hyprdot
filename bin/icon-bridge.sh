#!/usr/bin/env bash
# =========================================================================
# icon-bridge.sh - let quickshell see the icon theme the desktop is set to
# =========================================================================
#
# Usage:  bin/icon-bridge.sh            build or refresh the bridge
#         bin/icon-bridge.sh --status   what it currently points at
#         bin/icon-bridge.sh --remove   take it out again
#
# THE BUG THIS EXISTS FOR. Quickshell 0.3.1 resolves an icon name through
# Qt, and Qt has no icon theme in a bare Hyprland session - nothing sets
# QIcon::themeName(), so it uses the platform theme's fallback, which is
# "hicolor". Measured with Quickshell.hasThemeIcon(): names that live in
# hicolor resolve, names that live in the selected theme do not.
#
#     hasThemeIcon("start-here")            true    - in hicolor
#     hasThemeIcon("chromium-browser")      true    - in hicolor
#     hasThemeIcon("media-flash")           false   - Adwaita only
#     hasThemeIcon("drive-removable-media") false   - Adwaita only
#
# The visible symptom is that every notification sent with a themed icon
# name draws the missing-icon chequerboard rather than an icon.
#
# WHAT WAS TRIED FIRST, so nobody repeats it: QT_QPA_PLATFORMTHEME at gtk3,
# gnome and xdgdesktopportal, and XDG_CURRENT_DESKTOP at GNOME and KDE, each
# verified as actually reaching the process through /proc/PID/environ. None
# of them changed the answer. Quickshell 0.3.1 exposes no icon theme
# property of its own either - the singleton has iconPath and hasThemeIcon
# and nothing to set the theme with.
#
# WHAT THIS DOES INSTEAD. The icon spec has every theme search every base
# directory, and the user's own ~/.local/share/icons comes before
# /usr/share/icons. So a user-level "hicolor" whose category directories are
# symlinks into the selected theme puts that theme's icons where the only
# theme quickshell can see will find them. Confirmed: with
# hicolor/scalable/devices pointing at Adwaita's, hasThemeIcon("media-flash")
# became true.
#
# NO index.theme IS WRITTEN, and that is the part that makes this safe.
# Qt reads the directory list from the first index.theme it finds for the
# theme, which stays the system's - all 649 entries of it. Writing our own
# would mean copying that list and keeping it in step forever. Without one,
# the system file still describes hicolor and our directories are simply
# extra places to look for the categories it already lists.
#
# ONLY SYMLINKS ARE REMOVED on refresh. Applications install their own icons
# into ~/.local/share/icons/hicolor, and those are real directories and real
# files; deleting the tree wholesale would take them with it.
#
# bin/theme.sh calls this after it switches the icon theme, so the bridge
# follows the palette rather than being pinned to whatever was selected the
# day it was first built.
#
# KNOWN LIMITATION: ONLY THEMES LAID OUT LIKE hicolor GET THROUGH. The links
# are named after hicolor's own directories - 16x16/devices, scalable/apps -
# and a theme is used for one only if it has a directory of that same name.
# Adwaita does, so the Framework bridges 45 categories straight from it.
#
# Reversal does not. Its layout is the inverse - devices/16, actions/symbolic,
# context first and size second - so none of hicolor's names match, and on the
# NixOS desktop, where Reversal-grey-dark is the selected theme, all 8 links
# fell through the Inherits chain to Adwaita instead. Icons resolve; they are
# simply the wrong theme's.
#
# Fixing it means translating each theme's own Directories into hicolor's
# shape using the Size and Context its index.theme declares, which is a real
# piece of work and is not done. `--status` prints what each link points at,
# which is where this was noticed.

set -uo pipefail

bold=$'\033[1m'; green=$'\033[1;32m'; dim=$'\033[2m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }

OVERLAY="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
HICOLOR_INDEX=""

# --- what the desktop is set to ------------------------------------------
# gsettings is what theme.sh writes last and what GTK4 reads; the GTK3
# settings.ini is the same answer written again for GTK3's benefit.
current_icon_theme() {
    local t
    t=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "\"'")
    if [[ -n $t && $t != "@as"* ]]; then printf '%s' "$t"; return; fi
    t=$(sed -n 's/^gtk-icon-theme-name=//p' \
            "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | tail -1)
    [[ -n $t ]] && { printf '%s' "$t"; return; }
    printf 'Adwaita'
}

# Every base directory a theme can live in, in the order the spec searches.
icon_bases() {
    local dirs d
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    printf '%s\n' "$HOME/.icons" "${XDG_DATA_HOME:-$HOME/.local/share}/icons"
    for d in "${dirs[@]}"; do printf '%s\n' "$d/icons"; done
}

# The themes to draw from, nearest first: the selected one, then whatever it
# inherits, then Adwaita. Adwaita is on the end for the same reason
# bin/usb-notify.sh puts it there - it is the platform default and the theme
# theme.sh itself falls back to, and a theme with no icon for a category
# should borrow a reasonable one rather than leave a hole.
theme_chain() {
    local theme=$1 base line
    printf '%s\n' "$theme"
    while read -r base; do
        [[ -f $base/$theme/index.theme ]] || continue
        line=$(sed -n 's/^Inherits=//p' "$base/$theme/index.theme" | head -1)
        [[ -n $line ]] && printf '%s\n' ${line//,/ }
        break
    done < <(icon_bases)
    printf 'Adwaita\n'
}

# THE SYSTEM'S hicolor INDEX, not ours - we deliberately do not write one.
# Only the directories it lists are ever searched, so linking anything else
# would create a directory nothing looks in.
find_hicolor_index() {
    local base
    while read -r base; do
        [[ -f $base/hicolor/index.theme && $base != "$OVERLAY"* ]] || continue
        [[ -L $base/hicolor ]] && continue
        printf '%s' "$base/hicolor/index.theme"; return 0
    done < <(icon_bases)
    return 1
}

hicolor_dirs() {
    sed -n 's/^Directories=//p' "$HICOLOR_INDEX" | head -1 | tr ',' '\n' | sed '/^$/d'
}

# The first theme in the chain that actually has this category.
source_for() {
    local dir=$1 theme base
    while read -r theme; do
        [[ -z $theme || $theme == hicolor ]] && continue
        while read -r base; do
            [[ $base == "${XDG_DATA_HOME:-$HOME/.local/share}/icons" ]] && continue
            [[ -d $base/$theme/$dir ]] || continue
            printf '%s' "$base/$theme/$dir"; return 0
        done < <(icon_bases)
    done < <(theme_chain "$(current_icon_theme)")
    return 1
}

# --- the three things it can do ------------------------------------------

# Only ever symlinks, and only under the overlay. A real directory there
# belongs to an application that installed its icons the ordinary way.
clear_links() {
    local n=0 p
    [[ -d $OVERLAY ]] || return 0
    while IFS= read -r -d '' p; do
        rm -f "$p"; n=$((n + 1))
    done < <(find "$OVERLAY" -type l -print0 2>/dev/null)
    # Tidy up the empty scaffolding the links used to sit in, deepest first.
    find "$OVERLAY" -mindepth 1 -type d -empty -delete 2>/dev/null
    rmdir "$OVERLAY" 2>/dev/null
    printf '%s' "$n"
}

build() {
    local theme; theme=$(current_icon_theme)
    local removed; removed=$(clear_links)
    [[ $removed -gt 0 ]] && note "cleared $removed old link(s)"

    local made=0 dir src
    while read -r dir; do
        src=$(source_for "$dir") || continue
        mkdir -p "$OVERLAY/$(dirname "$dir")"
        # A real directory here is an application's own; leave it alone.
        [[ -e $OVERLAY/$dir && ! -L $OVERLAY/$dir ]] && continue
        ln -sfn "$src" "$OVERLAY/$dir" && made=$((made + 1))
    done < <(hicolor_dirs)

    note "bridged $made categor$([[ $made == 1 ]] && echo y || echo ies) from ${bold}$theme${reset}"
    printf '    %sinto %s%s\n' "$dim" "$OVERLAY" "$reset"
    printf '    %squickshell reads icons through hicolor - see the note at the top%s\n' \
           "$dim" "$reset"
}

status() {
    printf '  selected icon theme : %s\n' "$(current_icon_theme)"
    printf '  chain               : %s\n' "$(theme_chain "$(current_icon_theme)" | tr '\n' ' ')"
    if [[ ! -d $OVERLAY ]]; then
        printf '  bridge              : not built\n'; return
    fi
    local n; n=$(find "$OVERLAY" -type l 2>/dev/null | wc -l)
    printf '  bridge              : %s link(s) under %s\n' "$n" "$OVERLAY"
    find "$OVERLAY" -type l -printf '    %P -> %l\n' 2>/dev/null | sort | head -8
    [[ $n -gt 8 ]] && printf '    %s… and %d more%s\n' "$dim" "$((n - 8))" "$reset"
}

HICOLOR_INDEX=$(find_hicolor_index) || {
    warn "no system hicolor/index.theme found - nothing to bridge against"
    exit 1
}

case "${1-}" in
    ""|--build|--refresh) build ;;
    --status) status ;;
    --remove)
        n=$(clear_links)
        note "removed $n link(s)"
        ;;
    *) echo "usage: $0 [--build|--status|--remove]" >&2; exit 2 ;;
esac
