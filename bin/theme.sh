#!/usr/bin/env bash
# =========================================================================
# theme.sh - switch the whole desktop between the themes in themes/
# =========================================================================
#
# One palette file (themes/<name>.conf) is the source of truth. This script
# reads it and fans the values out to four consumers, each of which has its
# own idea of what a config file is and its own way of being told to reload:
#
#   quickshell   the active palette is copied to a file that Theme.qml
#                watches with FileView. QML re-evaluates the bindings, so
#                the bar, frame, launcher and power menu re-colour live.
#                Nothing is restarted - a restart would flash the desktop.
#
#   kitty        kitty.conf has `include theme.conf`; that file is written
#                here and every running kitty is sent SIGUSR1, which is the
#                documented "re-read your config" signal. Instant, and it
#                does not disturb what is on screen.
#
#   GTK apps     gsettings color-scheme + gtk-theme. GTK3 and GTK4 apps both
#                watch these over dbus and restyle themselves. No new theme
#                package: Adwaita ships light and dark and picks by scheme.
#
#                This reaches further than GTK. xdg-desktop-portal republishes
#                the setting as org.freedesktop.appearance color-scheme, and
#                that is what Chromium, Electron apps and anything else
#                portal-aware actually read - verified with:
#                  busctl --user call org.freedesktop.portal.Desktop \
#                    /org/freedesktop/portal/desktop \
#                    org.freedesktop.portal.Settings ReadOne ss \
#                    org.freedesktop.appearance color-scheme
#                which returns 1 for dark and 2 for light as this switches.
#                So Chromium follows the toggle with nothing installed, as
#                long as its Appearance > Mode is left on Device (the
#                default). It follows in generic light/dark, not in this
#                palette: a Chrome theme is an extension, and no outside
#                process can swap one without restarting the browser.
#
#   Hyprland     hyprctl eval, applied live. NOT `hyprctl keyword`, which
#                this Hyprland refuses outright - "keyword can't work with
#                non-legacy parsers, use eval" - because the config is Lua.
#                The argument is a real hl.config{} call, the same shape
#                hypr/look.lua uses, which is also the only form that can
#                express the two-stop border gradient.
#                Borders are off by default so this is usually invisible, but
#                it keeps the compositor honest if they are switched on.
#
# WHY A SCRIPT AND NOT A QUICKSHELL-ONLY TOGGLE: three of the four consumers
# are not quickshell and know nothing about it. Anything outside the bar has
# to be driven from a process that can write files and signal other programs.
#
# The choice is remembered in ~/.local/state, NOT in the repository - it is
# per-machine state, and committing it would make every theme switch a diff.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
theme_dir="$repo/themes"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/fd44-hyprdot"
state_file="$state_dir/theme"
# The copy quickshell watches. A copy rather than a symlink: FileView watches
# a path, and swapping a symlink underneath it does not reliably produce the
# change notification that a rewritten file does.
active_file="$state_dir/theme-active.conf"

default_theme="dark"

die() { printf 'theme: %s\n' "$*" >&2; exit 1; }

themes() {
    local f
    for f in "$theme_dir"/*.conf; do
        [[ -f $f ]] || continue
        basename "$f" .conf
    done
}

current() {
    if [[ -f $state_file ]]; then
        cat "$state_file"
    else
        printf '%s\n' "$default_theme"
    fi
}

# Read one key out of a theme file. Deliberately not `source`: these files
# are data, and sourcing them would execute anything that found its way in
# and would also dump 41 names into this script's namespace.
val() {
    local file="$1" key="$2"
    sed -n "s/^${key}=\(.*\)$/\1/p" "$file" | head -1
}

apply() {
    local name="$1"
    local file="$theme_dir/$name.conf"
    [[ -f $file ]] || die "no such theme: $name (have: $(themes | tr '\n' ' '))"

    mkdir -p "$state_dir"
    printf '%s\n' "$name" > "$state_file"

    # --- quickshell ----------------------------------------------------
    # Written to a temp file in the same directory and moved into place, so
    # a FileView reading it can never catch a half-written palette.
    local tmp
    tmp="$(mktemp "$active_file.XXXXXX")"
    cat "$file" > "$tmp"
    mv -f "$tmp" "$active_file"

    # --- kitty ---------------------------------------------------------
    local kitty_dir="$HOME/.config/kitty"
    if [[ -d $kitty_dir ]]; then
        local ktmp
        ktmp="$(mktemp "$kitty_dir/theme.conf.XXXXXX")"
        {
            printf '# Generated by bin/theme.sh from themes/%s.conf - do not edit.\n' "$name"
            printf '# Edit the theme file and re-run `theme.sh set %s` instead.\n\n' "$name"
            printf 'background %s\n'        "$(val "$file" term_bg)"
            printf 'foreground %s\n'        "$(val "$file" term_fg)"
            printf 'cursor %s\n'            "$(val "$file" term_cursor)"
            printf 'selection_background %s\n' "$(val "$file" term_sel_bg)"
            printf 'selection_foreground %s\n' "$(val "$file" term_sel_fg)"
            printf 'background_opacity %s\n' "$(val "$file" term_opacity)"
            local i
            for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
                printf 'color%d %s\n' "$i" "$(val "$file" "term_color$i")"
            done
        } > "$ktmp"
        chmod 644 "$ktmp"
        mv -f "$ktmp" "$kitty_dir/theme.conf"

        # SIGUSR1 is kitty's documented reload-config signal. Failure here is
        # not fatal: no kitty running is the normal case at login.
        pkill -USR1 -x kitty 2>/dev/null || true
    fi

    # --- GTK -----------------------------------------------------------
    local appearance; appearance="$(val "$file" appearance)"
    if command -v gsettings >/dev/null 2>&1; then
        local scheme=prefer-dark gtk=Adwaita-dark
        if [[ $appearance == light ]]; then scheme=prefer-light; gtk=Adwaita; fi
        local iface=org.gnome.desktop.interface
        gsettings set "$iface" color-scheme "$scheme" 2>/dev/null || true
        gsettings set "$iface" gtk-theme    "$gtk"    2>/dev/null || true
    fi

    # GTK3 apps that predate the dbus setting read this file at startup. It
    # will not restyle anything already running - gsettings above does that -
    # but without it a newly launched GTK3 app comes up in the wrong theme.
    local g3="$HOME/.config/gtk-3.0" g4="$HOME/.config/gtk-4.0"
    local prefer=0; [[ $appearance == dark ]] && prefer=1
    local d
    for d in "$g3" "$g4"; do
        mkdir -p "$d"
        printf '[Settings]\ngtk-application-prefer-dark-theme=%d\n' "$prefer" \
            > "$d/settings.ini"
    done

    # --- Hyprland ------------------------------------------------------
    if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        local lua
        lua="hl.config({ general = { col = {"
        lua+=" active_border = { colors = { \"$(val "$file" border_active_a)\","
        lua+=" \"$(val "$file" border_active_b)\" }, angle = $(val "$file" border_angle) },"
        lua+=" inactive_border = \"$(val "$file" border_inactive)\" } },"
        lua+=" decoration = { shadow = { color = $(val "$file" shadow) } } })"
        hyprctl eval "$lua" >/dev/null 2>&1 || true
    fi

    printf 'theme: %s\n' "$name"
}

case "${1:-}" in
    set)     [[ -n ${2:-} ]] || die "usage: theme.sh set <name>"; apply "$2" ;;
    toggle)
        # Two themes, so toggle means "the other one". With more than two it
        # walks the list in order and wraps, which is what a toggle key does
        # on anything with more than two states.
        mapfile -t all < <(themes)
        (( ${#all[@]} )) || die "no themes in $theme_dir"
        cur="$(current)"; next="${all[0]}"
        for i in "${!all[@]}"; do
            if [[ ${all[$i]} == "$cur" ]]; then
                next="${all[$(( (i + 1) % ${#all[@]} ))]}"
                break
            fi
        done
        apply "$next"
        ;;
    current) current ;;
    list)    themes ;;
    # No argument re-applies the remembered theme. This is what runs at login:
    # gsettings and kitty's theme.conf survive a reboot, but re-applying is
    # cheap and makes a half-configured machine self-correct.
    ""|restore) apply "$(current)" ;;
    *)       die "usage: theme.sh [set <name>|toggle|current|list|restore]" ;;
esac
