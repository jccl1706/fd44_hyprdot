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

# WHERE A THEME KEEPS ITS ICONS, TRANSLATED INTO hicolor's NAMES.
#
# The first version of this looked for a directory in the theme with the same
# name as the hicolor one - 16x16/devices, scalable/apps - which works only
# because Adwaita happens to be laid out that way. Reversal is not: its
# directories are devices/16, actions/symbolic, context first and size
# second. Nothing matched, so on the NixOS desktop every link fell through to
# Adwaita and the selected theme was never used at all.
#
# So the theme's own index.theme is read instead. Every section it declares
# carries the two facts needed to place it - Context says what kind of icons
# are in there, Size and Type say how big - and hicolor's name for that
# combination is size x size / context, or scalable/context. A theme laid out
# like Adwaita produces section names identical to the paths they map to, so
# the same code covers both without a special case.
#
# CONTEXT, NOT THE DIRECTORY NAME. Reversal keeps its MimeTypes icons in a
# directory called "mimes" and hicolor calls that "mimetypes"; reading the
# declared Context is what makes those meet. The table below is the
# freedesktop context names and the directory hicolor gives each - notably
# Applications is "apps", which is the one that would silently lose every
# application icon if it were guessed from the name.
theme_dir_map() {
    local index=$1
    awk '
        BEGIN {
            ctxdir["applications"] = "apps"
            ctxdir["mimetypes"]    = "mimetypes"
            ctxdir["devices"]      = "devices"
            ctxdir["actions"]      = "actions"
            ctxdir["places"]       = "places"
            ctxdir["status"]       = "status"
            ctxdir["emblems"]      = "emblems"
            ctxdir["emotes"]       = "emotes"
            ctxdir["categories"]   = "categories"
            ctxdir["animations"]   = "animations"
            ctxdir["filesystems"]  = "filesystems"
            ctxdir["international"]= "intl"
        }
        /^\[/ {
            sec = substr($0, 2, length($0) - 2)
            if (sec != "Icon Theme") order[++n] = sec
            next
        }
        sec == "" || sec == "Icon Theme" { next }
        /^Size=/    { size[sec] = substr($0, 6) }
        /^Type=/    { type[sec] = substr($0, 6) }
        /^Context=/ { ctx[sec]  = tolower(substr($0, 9)) }
        END {
            for (i = 1; i <= n; i++) {
                d = order[i]
                c = ctxdir[ctx[d]]
                if (c == "") continue                  # a context hicolor has no place for
                if (type[d] == "Scalable") h = "scalable/" c
                else if (size[d] != "")    h = size[d] "x" size[d] "/" c
                else continue
                print h "\t" d
            }
        }
    ' "$index"
}

# Every hicolor directory this machine can fill, as "<hicolor path>\t<source
# directory>", nearest theme first and first claim winning. Printed once and
# read twice - build() links it and status() shows it.
bridge_map() {
    local theme base index line h d
    declare -A taken=()
    while read -r theme; do
        [[ -z $theme || $theme == hicolor ]] && continue
        while read -r base; do
            # NO SKIPPING THE USER'S OWN ICON DIRECTORY, which the first two
            # versions of this did to avoid the overlay feeding on its own
            # links. That was both unnecessary and the second reason Reversal
            # never got used: the overlay is one theme inside that base -
            # hicolor - and hicolor is already excluded above, while Reversal
            # is installed into the very directory that was being skipped.
            # bin/icon-theme.sh puts it there on purpose, needing no root.
            index=$base/$theme/index.theme
            [[ -f $index ]] || continue
            while IFS=$'\t' read -r h d; do
                [[ -z ${taken[$h]-} ]] || continue
                [[ -d $base/$theme/$d ]] || continue
                taken[$h]=1
                printf '%s\t%s\n' "$h" "$base/$theme/$d"
            done < <(theme_dir_map "$index")
            break
        done < <(icon_bases)
    done < <(theme_chain "$(current_icon_theme)")
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
    # ONLY WHAT hicolor ACTUALLY LISTS. Qt searches the directories the
    # system's index declares and no others, so a link outside that set would
    # be a directory nothing ever looks in.
    local want; want=$(hicolor_dirs)
    while IFS=$'\t' read -r dir src; do
        grep -qxF "$dir" <<< "$want" || continue
        mkdir -p "$OVERLAY/$(dirname "$dir")"
        # A real directory here is an application's own; leave it alone.
        [[ -e $OVERLAY/$dir && ! -L $OVERLAY/$dir ]] && continue
        ln -sfn "$src" "$OVERLAY/$dir" && made=$((made + 1))
    done < <(bridge_map)

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
