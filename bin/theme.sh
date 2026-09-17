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
#   GTK apps     gsettings color-scheme + gtk-theme + icon-theme. GTK3 and
#                GTK4 apps all watch these over dbus and restyle themselves.
#                No new GTK theme package: Adwaita ships light and dark. GTK3
#                only needs a one-line "Adwaita-dark" user theme pointing at
#                its built-in dark stylesheet, written at the GTK step below.
#                Icons are the palette's icon_theme (Reversal, installed by
#                bin/icon-theme.sh), or Adwaita until it is.
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
#   hyprlock     colour variables written next to its config, which sources
#                them. Nothing to reload - hyprlock reads its config on
#                start, and it starts fresh every time the screen locks.
#
#   Chromium     an enterprise policy file under /etc, applied live with
#                --refresh-platform-policy. Not an extension: nothing outside
#                the browser can swap one of those without restarting it.
#                Needs root, so it is attempted only when root happens to be
#                free - see the comment at that step.
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

# Is icon theme $1 installed anywhere GTK looks? The same search path GTK
# uses: the user's data dir, the legacy ~/.icons, then every XDG data dir.
icon_theme_installed() {
    local d
    local -a dirs=("${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons")
    local IFS=:
    for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs+=("$d/icons"); done
    unset IFS
    for d in "${dirs[@]}"; do
        [[ -f "$d/$1/index.theme" ]] && return 0
    done
    return 1
}

# Theme files are data, and some of their values end up somewhere that
# executes: pasted into a Lua string for `hyprctl eval`, and into a hyprlock
# cmd[] line that a shell runs. So every value used that way must have exactly
# the shape of a colour or a number - checked BEFORE anything is written, so a
# bad file changes nothing. A new theme with a typo fails loudly here instead.
check_theme() {
    local file="$1" bad=0 k v re
    local -A shape=(
        [bg]=hex [surfaceHigh]=hex [outline]=hex [fg]=hex [dim]=hex
        [accent]=hex [accentFg]=hex [danger]=hex [surface]=hex
        [lock_shadow]=hex8
        [border_active_a]=rgba [border_active_b]=rgba [border_inactive]=rgba
        [shadow]=argb [border_angle]=int
    )
    local -A pattern=(
        [hex]='^#[0-9A-Fa-f]{6}$'
        [hex8]='^#?[0-9A-Fa-f]{8}$'
        [rgba]='^rgba\([0-9A-Fa-f]{8}\)$'
        [argb]='^0x[0-9A-Fa-f]{8}$'
        [int]='^[0-9]{1,3}$'
    )
    for k in "${!shape[@]}"; do
        v="$(val "$file" "$k")"
        re="${pattern[${shape[$k]}]}"
        if ! [[ $v =~ $re ]]; then
            printf 'theme: %s: %s=%q is not a valid %s value\n' \
                "$(basename "$file")" "$k" "$v" "${shape[$k]}" >&2
            bad=1
        fi
    done
    return "$bad"
}

apply() {
    local name="$1"
    local file="$theme_dir/$name.conf"
    [[ -f $file ]] || die "no such theme: $name (have: $(themes | tr '\n' ' '))"
    check_theme "$file" || die "not applying $name - fix the values above"

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
            # shellcheck disable=SC2016  # the backticks are text in the generated file
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

    # --- hyprlock ------------------------------------------------------
    #
    # Written as hyprlang variables that hypr/hyprlock.conf sources, so the
    # layout lives in one file and only the colours are generated. Written
    # into the config directory rather than ~/.local/state because hyprlang
    # resolves `source` against the working directory, and the lock screen is
    # started by hypridle from somewhere unpredictable - an absolute path
    # under $HOME is the only form that is reliable. That directory is a
    # symlink into the checkout, so the file is gitignored.
    #
    # Nothing needs reloading: hyprlock reads its config when it starts, and
    # it starts fresh every time the screen locks.
    #
    # The alpha suffixes are deliberate. The card is slightly translucent
    # (ee) so the shadow beneath it reads as depth, and the shadow itself is
    # low-alpha black on both themes - a shadow tinted with the theme would
    # stop looking like shade and start looking like a coloured halo.
    local hypr_dir="$HOME/.config/hypr"
    if [[ -d $hypr_dir ]]; then
        local htmp
        htmp="$(mktemp "$hypr_dir/hyprlock-colors.conf.XXXXXX")"
        {
            printf '# Generated by bin/theme.sh from themes/%s.conf - do not edit.\n' "$name"
            # shellcheck disable=SC2016  # the backticks are text in the generated file
            printf '# Edit the theme file and re-run `theme.sh set %s` instead.\n\n' "$name"
            # rgba() takes RRGGBBAA with NO leading '#' - hyprlang reports
            # "rgba() expects length of 8 characters" if one survives. The
            # theme files store colours the way every other consumer wants
            # them, with the hash, so it is stripped here.
            local k v
            for k in bg surfaceHigh outline fg dim accent accentFg danger; do
                v="$(val "$file" "$k")"
                printf '$%-11s = rgba(%sff)\n' "$k" "${v#\#}"
            done
            v="$(val "$file" surface)";     printf '$%-11s = rgba(%see)\n' surface "${v#\#}"
            v="$(val "$file" lock_shadow)"; printf '$%-11s = rgba(%s)\n'   shadow  "${v#\#}"

            # Plain hex as well, for the two strings that are pango markup
            # rather than config values. Pango wants #RRGGBB and hyprlang
            # wants rgba(RRGGBBAA), so the same colour has to be emitted in
            # both forms - and inside the config a literal '#' has to be
            # written '##', because a single one starts a comment.
            for k in dim danger; do
                v="$(val "$file" "$k")"
                printf '$%-11s = %s\n' "${k}Hex" "${v#\#}"
            done
        } > "$htmp"
        chmod 644 "$htmp"
        mv -f "$htmp" "$hypr_dir/hyprlock-colors.conf"
    fi

    # --- GTK -----------------------------------------------------------
    local appearance; appearance="$(val "$file" appearance)"

    # Icon theme: the palette's icon_theme if it is actually installed,
    # Adwaita otherwise. CHECKED, not trusted - gsettings accepts any string,
    # and naming a theme that is not there leaves GTK apps drawing
    # missing-image icons. Reversal is opt-in (bin/icon-theme.sh), so a
    # machine without it must still come out looking right.
    local icons; icons="$(val "$file" icon_theme)"
    if [[ -z $icons ]] || ! icon_theme_installed "$icons"; then
        icons=Adwaita
    fi

    # The theme name and scheme are decided OUTSIDE the gsettings check, because
    # the settings.ini files further down use $gtk whether or not gsettings is
    # here. They used to be declared inside it, and on a machine without
    # gsettings `set -u` then killed the whole function at the first use of
    # $gtk - taking settings.ini, Chromium and hyprlock with it, silently,
    # because the theme had already been written for quickshell and kitty by
    # then so the switch looked half-applied rather than failed. Found on
    # NixOS, where glib's command-line tools are a package you have to ask for
    # rather than something every desktop drags in.
    local gtk=Adwaita-dark gtk_scheme=prefer-dark
    if [[ $appearance == light ]]; then gtk="Adwaita"; gtk_scheme="prefer-light"; fi

    if command -v gsettings >/dev/null 2>&1; then
        local iface=org.gnome.desktop.interface
        gsettings set "$iface" color-scheme "$gtk_scheme" 2>/dev/null || true
        gsettings set "$iface" gtk-theme    "$gtk"        2>/dev/null || true
        # Live: running GTK apps watch this over dbus and swap icons in place.
        gsettings set "$iface" icon-theme   "$icons"      2>/dev/null || true
    else
        # Not fatal - settings.ini below still styles GTK apps at startup - but
        # it is the difference between apps restyling live and only after a
        # restart, and xdg-desktop-portal republishes this same setting as
        # org.freedesktop.appearance color-scheme, so without it Chromium and
        # every Electron app stop following the toggle too.
        printf 'theme: gsettings not found - GTK apps will only pick this up when restarted\n' >&2
    fi

    # GTK3 has no theme called "Adwaita-dark". Its dark Adwaita is built in,
    # but only reachable as "Adwaita" plus prefer-dark - a name it cannot find
    # falls back to LIGHT Adwaita, and prefer-dark does not rescue it. Measured
    # on gtk3 3.24.52: a label under "Adwaita-dark" drew with the light
    # theme's text colour, prefer-dark on or off. What showed it: the GTK
    # portal's Open File dialog (Chromium's) came up white on a dark desktop.
    #
    # "Adwaita" + prefer-dark would work at startup but not live: prefer-dark
    # comes only from settings.ini, which running apps never reread, so a
    # theme switch would leave them behind. Instead, give the name something
    # to find - a user theme that imports GTK3's own built-in dark stylesheet.
    # No package. Skipped if a real Adwaita-dark is installed system-wide.
    local dark_css="$HOME/.local/share/themes/Adwaita-dark/gtk-3.0/gtk.css"
    if [[ ! -d /usr/share/themes/Adwaita-dark ]]; then
        mkdir -p "${dark_css%/*}"
        printf '%s\n' '@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");' \
            > "$dark_css"
    fi

    # GTK3 apps that predate the dbus setting read these files at startup,
    # and X11 GTK3 apps get nothing else. They do not restyle anything already
    # running - gsettings above does that.
    #
    # GTK3's file NEVER sets prefer-dark: the theme name alone picks light or
    # dark. prefer-dark read at startup sticks for the life of the process, and
    # it turns plain "Adwaita" dark too - so a GTK3 app started under the dark
    # theme stayed dark after a switch to cream, however gsettings changed.
    # Seen on the GTK portal's Open File dialog, which starts once per login.
    # GTK4 has no Adwaita-dark user theme to find, so its file keeps
    # prefer-dark (libadwaita apps follow color-scheme live regardless).
    local g3="$HOME/.config/gtk-3.0" g4="$HOME/.config/gtk-4.0"
    local prefer=0; [[ $appearance == dark ]] && prefer=1
    mkdir -p "$g3" "$g4"
    printf '[Settings]\ngtk-theme-name=%s\ngtk-application-prefer-dark-theme=0\ngtk-icon-theme-name=%s\n' \
        "$gtk" "$icons" > "$g3/settings.ini"
    printf '[Settings]\ngtk-application-prefer-dark-theme=%d\ngtk-icon-theme-name=%s\n' \
        "$prefer" "$icons" > "$g4/settings.ini"

    # --- Chromium ------------------------------------------------------
    #
    # No sudo. bin/chrome-theme.sh only writes a request - colour and scheme -
    # into ~/.local/state; a root service installed once by
    # `sudo bin/chromium-policy-setup.sh` validates it and writes the policy
    # file. The policy directory stays root's, so nothing running as the user
    # can set any other browser policy.
    #
    # LUMINANCE GUARD. The seed's own brightness beats the colour scheme - a
    # near-black seed under scheme "light" renders a near-black browser, the
    # inverse of what was asked for. So a seed that contradicts its scheme is
    # swapped for a mid-tone that cannot. Computed rather than hardcoded per
    # theme, so a theme added later is covered without editing this.
    local seed scheme safe_seed
    seed="$(val "$file" browser_seed)"
    scheme=dark; [[ $appearance == light ]] && scheme=light

    # In bash, not python3. This used to shell out to python for one weighted
    # sum, and on a machine without it the command substitution failed, `set -e`
    # took the exit status of the assignment, and the whole switch died right
    # here - silently, with the fallback on the very next line never reached,
    # and Chromium and Hyprland never told about the new theme. Integer
    # arithmetic the shell can do itself cannot fail that way.
    if [[ -n $seed && -x "$repo/bin/chrome-theme.sh" ]]; then
        safe_seed="$seed"
        local hex="${seed#\#}"
        if [[ $hex =~ ^[0-9a-fA-F]{6}$ ]]; then
            # 0.299R + 0.587G + 0.114B, times 1000 to stay in integers. The
            # range is 0..255000, so 0.75 is 191250 and 0.25 is 63750.
            local w=$(( 299 * 16#${hex:0:2} + 587 * 16#${hex:2:2} + 114 * 16#${hex:4:2} ))
            if { [[ $scheme == dark  ]] && (( w > 191250 )); } ||
               { [[ $scheme == light ]] && (( w < 63750  )); }; then
                safe_seed="$(val "$file" outline)"
            fi
        fi
        [[ -n $safe_seed ]] || safe_seed="$seed"
        "$repo/bin/chrome-theme.sh" "${safe_seed#\#}" "$scheme" >/dev/null 2>&1 || true
    fi

    # --- Wallpaper -----------------------------------------------------
    #
    # quickshell draws the wallpaper (quickshell/Wallpaper.qml) by watching
    # ~/.local/state/wallpaper, so bin/wallpaper.sh only has to write that file
    # and the crossfade happens by itself - there is no daemon to talk to and
    # nothing to restart.
    #
    # A MANUAL CHOICE WINS. The wallpaper is only replaced when the one on
    # screen is another theme's - or none is set yet. Anything picked in the
    # picker is left alone, for as long as it is picked.
    #
    # Without that rule this step quietly overwrites a choice the themes know
    # nothing about: measured on the laptop, which was showing
    # tokyo-night-quattro and had it replaced by re-applying the theme it was
    # already on. A theme switch is not a request to undo a wallpaper you chose.
    #
    # A theme naming a file that is not there is reported rather than passed
    # on, because wallpaper.sh would otherwise fail the whole switch through
    # `set -e` for a cosmetic step.
    local wp
    wp="$(val "$file" wallpaper)"
    if [[ -n $wp && -x "$repo/bin/wallpaper.sh" ]]; then
        if [[ ! -f "$repo/wallpapers/$wp" ]]; then
            printf 'theme: %s names wallpaper %s, which is not in wallpapers/\n' \
                "$name" "$wp" >&2
        else
            local now theme_owned=0 t other
            now="$(basename "$("$repo/bin/wallpaper.sh" current 2>/dev/null || true)")"
            [[ -z $now ]] && theme_owned=1          # nothing chosen yet
            while read -r t; do
                other="$(val "$theme_dir/$t.conf" wallpaper)"
                [[ -n $other && $now == "$other" ]] && theme_owned=1
            done < <(themes)
            if (( theme_owned )); then
                "$repo/bin/wallpaper.sh" set "$repo/wallpapers/$wp" >/dev/null 2>&1 \
                    || printf 'theme: could not set the wallpaper %s\n' "$wp" >&2
            fi
        fi
    fi

    # --- Hyprland ------------------------------------------------------
    if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        local lua bg
        bg="$(val "$file" bg)"
        lua="hl.config({ general = { col = {"
        lua+=" active_border = { colors = { \"$(val "$file" border_active_a)\","
        lua+=" \"$(val "$file" border_active_b)\" }, angle = $(val "$file" border_angle) },"
        lua+=" inactive_border = \"$(val "$file" border_inactive)\" } },"
        # What shows for the moment quickshell restarts and its wallpaper
        # surface is gone - see misc in hypr/look.lua.
        lua+=" misc = { background_color = \"rgb(${bg#\#})\" },"
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
