#!/usr/bin/env bash
# =========================================================================
# theme.sh - switch the whole desktop between the themes in themes/
# =========================================================================
#
# One palette file (themes/<name>.conf) is the source of truth. This script
# reads it and fans the values out to the consumers below, each of which has its
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
#   btop         a generated .theme file plus three keys in btop.conf.
#                THE ONE CONSUMER THAT DOES NOT FOLLOW A LIVE SWITCH: btop
#                reads its theme once at startup and has no reload signal, so
#                a running instance keeps the old colours until it is closed
#                and reopened. That costs nothing here, because btop lives in
#                the special:btop scratchpad and is opened on demand rather
#                than left running - see hypr/rules.lua.
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
# WHY A SCRIPT AND NOT A QUICKSHELL-ONLY TOGGLE: most of the consumers
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
#
# CACHED, because a switch reads about forty keys and this used to be a `sed`
# per key - forty processes to read one small file forty times. Parsing it
# once into an array took the whole switch from 0.64s to about half that, and
# the difference is visible: this runs on a keypress.
#
# The cache is keyed on the path, so the two calls that read a DIFFERENT file
# (the validator, and the toggle working out what to switch to) still get the
# right answer - they just reload it.
#
# `IFS='=' read -r k v` splits on the FIRST = only, because there are two
# variables and the rest of the line lands in the second. Values containing an
# = survive. First definition wins, matching the `head -1` this replaces.
declare -A _vals=()
_vals_file=""
load_vals() {
    local file="$1" k v
    [[ $_vals_file == "$file" ]] && return 0
    _vals=()
    while IFS='=' read -r k v; do
        [[ -z $k || $k == \#* ]] && continue
        [[ -v _vals[$k] ]] && continue
        _vals[$k]="$v"
    done < "$file"
    _vals_file="$file"
}

# AND THE HOT PATHS DO NOT USE THIS. `$(val ...)` forks a subshell for every
# key, and writing kitty's colours alone reads twenty-two of them - measured at
# 0.13s for that step, with btop's another 0.13s, out of a 0.65s switch. After
# load_vals the array is right here, so those steps say "${_vals[term_bg]}"
# and fork nothing. This form stays for the handful of places that want a
# string, or that read a different file.
val() {
    load_vals "$1"
    printf '%s\n' "${_vals[$2]-}"
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

# Is GTK theme $1 installed anywhere GTK looks? Same search path as the icon
# theme above, minus the legacy ~/.icons, plus /usr/share/themes.
gtk_theme_installed() {
    local d
    local -a dirs=("${XDG_DATA_HOME:-$HOME/.local/share}/themes")
    local IFS=:
    for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs+=("$d/themes"); done
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
    load_vals "$file"
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

    # check_theme loaded it; this is here so the order of the two can change
    # without every "${_vals[...]}" below quietly reading an empty array.
    load_vals "$file"

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
            printf 'background %s\n'        "${_vals[term_bg]-}"
            printf 'foreground %s\n'        "${_vals[term_fg]-}"
            printf 'cursor %s\n'            "${_vals[term_cursor]-}"
            printf 'selection_background %s\n' "${_vals[term_sel_bg]-}"
            printf 'selection_foreground %s\n' "${_vals[term_sel_fg]-}"
            printf 'background_opacity %s\n' "${_vals[term_opacity]-}"
            local i
            for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
                printf 'color%d %s\n' "$i" "$(val "$file" "term_color$i")"
            done
        } > "$ktmp"
        chmod 644 "$ktmp"
        mv -f "$ktmp" "$kitty_dir/theme.conf"

        # SIGUSR1 is kitty's documented reload-config signal. Failure here is
        # not fatal: no kitty running is the normal case at login.
        # Backgrounded: pkill walks /proc and costs about 50ms, and nothing
        # here needs its result - the signal is sent either way. Two of these
        # were a sixth of the whole switch.
        { pkill -USR1 -x kitty 2>/dev/null || true; } &
    fi

    # --- btop ----------------------------------------------------------
    #
    # btop keeps themes as files in ~/.config/btop/themes and picks one by
    # name in btop.conf. Both are written here, but differently: the theme is
    # generated wholesale, while btop.conf has only three keys edited in
    # place. That is deliberate - btop REWRITES ITS WHOLE CONFIG ON EXIT, so
    # generating that file would throw away anything changed from inside the
    # program the next time the theme was switched.
    local btop_dir="$HOME/.config/btop"
    if command -v btop >/dev/null 2>&1; then
        mkdir -p "$btop_dir/themes"
        local btmp
        btmp="$(mktemp "$btop_dir/themes/fd44.theme.XXXXXX")"

        # The load colours. Green through yellow to red, straight out of the
        # palette's own terminal colours rather than its UI tokens: a
        # temperature graph that runs from accent to accent tells you nothing,
        # and "hot" has a colour everyone already knows.
        local g y r
        g="${_vals[term_color2]-}"
        y="${_vals[term_color3]-}"
        r="${_vals[term_color1]-}"

        {
            printf '# Generated by bin/theme.sh from themes/%s.conf - do not edit.\n' "$name"
            # shellcheck disable=SC2016  # the backticks are text in the generated file
            printf '# Edit the theme file and re-run `theme.sh set %s` instead.\n\n' "$name"

            # EMPTY, NOT A COLOUR. btop treats an empty main_bg as "use the
            # terminal's background", which is what lets kitty's own
            # translucency show through instead of being painted over with an
            # opaque rectangle. theme_background=False below is the other half.
            printf 'theme[main_bg]=""\n'

            printf 'theme[main_fg]="%s"\n'     "${_vals[fg]-}"
            printf 'theme[title]="%s"\n'       "${_vals[fg]-}"
            printf 'theme[hi_fg]="%s"\n'       "${_vals[accent]-}"
            printf 'theme[selected_bg]="%s"\n' "${_vals[surfaceHigh]-}"
            printf 'theme[selected_fg]="%s"\n' "${_vals[fg]-}"
            printf 'theme[inactive_fg]="%s"\n' "${_vals[dim]-}"
            printf 'theme[graph_text]="%s"\n'  "${_vals[dim]-}"
            printf 'theme[meter_bg]="%s"\n'    "${_vals[surface]-}"
            printf 'theme[proc_misc]="%s"\n'   "${_vals[accent]-}"

            # The four box frames and the divider, all the palette's hairline.
            local box
            for box in cpu_box mem_box net_box proc_box div_line; do
                printf 'theme[%s]="%s"\n' "$box" "${_vals[outline]-}"
            done

            # Anything that means "how loaded is this" gets the same three
            # stops, so a glance reads the same way in every box.
            local grad
            for grad in temp cpu used download upload process; do
                printf 'theme[%s_start]="%s"\n' "$grad" "$g"
                printf 'theme[%s_mid]="%s"\n'   "$grad" "$y"
                printf 'theme[%s_end]="%s"\n'   "$grad" "$r"
            done

            # ...and anything where MORE IS BETTER is flat, not a gradient.
            # Running free memory through green-to-red would colour a healthy
            # machine red, which is exactly backwards.
            printf 'theme[free_start]="%s"\n'      "$g"
            printf 'theme[free_mid]=""\ntheme[free_end]=""\n'
            printf 'theme[available_start]="%s"\n' "${_vals[term_color6]-}"
            printf 'theme[available_mid]=""\ntheme[available_end]=""\n'
            printf 'theme[cached_start]="%s"\n'    "${_vals[term_color4]-}"
            printf 'theme[cached_mid]=""\ntheme[cached_end]=""\n'
        } > "$btmp"
        chmod 644 "$btmp"
        mv -f "$btmp" "$btop_dir/themes/fd44.theme"

        # Three keys, edited in place or appended if this is the first run.
        # btop owns the rest of this file.
        local conf="$btop_dir/btop.conf"
        [[ -f $conf ]] || printf '#? Config file for btop v. 1.4\n\n' > "$conf"
        local kv
        for kv in 'color_theme="fd44"' 'theme_background=False' 'truecolor=True'; do
            local k="${kv%%=*}"
            if grep -qE "^${k} *=" "$conf"; then
                sed -i "s|^${k} *=.*|${kv/=/ = }|" "$conf"
            else
                printf '%s\n' "${kv/=/ = }" >> "$conf"
            fi
        done

        # AND STOP ANY RUNNING btop, because it will never pick this up on its
        # own: it reads the theme once at startup and has no reload signal -
        # no SIGUSR1 like kitty, no IPC, nothing. An instance left open keeps
        # the old palette indefinitely, which looks exactly like the theme
        # switch having failed. It is the only consumer here with that
        # problem.
        #
        # Stopping it is safe BECAUSE OF WHERE IT LIVES. btop runs in the
        # special:btop scratchpad, as the only command of its kitty, so this
        # closes that window - and hypr/rules.lua relaunches it from
        # on_created_empty the next time the scratchpad is opened. The cost is
        # a scratchpad you were probably not looking at; the alternative is a
        # window that silently disagrees with the rest of the desktop.
        #
        # -x, not -f: `pkill -f btop` would match this script's own command
        # line, which is a trap this repo has fallen into before.
        { pkill -x btop 2>/dev/null || true; } &
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
            v="${_vals[surface]-}";     printf '$%-11s = rgba(%see)\n' surface "${v#\#}"
            v="${_vals[lock_shadow]-}"; printf '$%-11s = rgba(%s)\n'   shadow  "${v#\#}"

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
    local appearance; appearance="${_vals[appearance]-}"

    # Icon theme: the palette's icon_theme if it is actually installed,
    # Adwaita otherwise. CHECKED, not trusted - gsettings accepts any string,
    # and naming a theme that is not there leaves GTK apps drawing
    # missing-image icons. Reversal is opt-in (bin/icon-theme.sh), so a
    # machine without it must still come out looking right.
    local icons; icons="${_vals[icon_theme]-}"
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
    # THE PALETTE'S OWN GTK THEME, and this is what makes GTK3 apps follow a
    # live switch. GTK never re-reads a user stylesheet - measured on both GTK3
    # and GTK4 with a probe whose CSS was rewritten underneath it - but GTK3
    # reloads when gtk-theme-name changes, because that is a different theme
    # rather than the same file again. So the colours have to arrive as a
    # named theme, which bin/gtk-theme.sh installs.
    #
    # CHECKED, not trusted, exactly as the icon theme above: gsettings accepts
    # any string, and a theme that is not there leaves GTK apps on their
    # default. Rosé Pine is opt-in, so a machine without it must still come out
    # looking right - Adwaita ships light and dark and is always present.
    local gtk gtk_scheme=prefer-dark
    [[ $appearance == light ]] && gtk_scheme="prefer-light"
    gtk="${_vals[gtk_theme]-}"
    if [[ -z $gtk ]] || ! gtk_theme_installed "$gtk"; then
        gtk=Adwaita-dark
        [[ $appearance == light ]] && gtk="Adwaita"
    fi

    # GTK3 has no theme called "Adwaita-dark" - its dark Adwaita is built in and
    # only reachable as "Adwaita" plus prefer-dark, and a name it cannot find
    # falls back to LIGHT Adwaita. So when the palette's own theme is missing
    # and the fallback above picked that name, give the name something to find:
    # a user theme that imports GTK3's own built-in dark stylesheet. No package.
    # Skipped if a real Adwaita-dark is installed system-wide, and not written
    # at all when a proper theme is in use.
    # gtk_theme_installed rather than a bare /usr/share test: that directory
    # does not exist on NixOS, so the hardcoded check could only ever answer
    # "not installed" there. It happens to give the right answer on this
    # machine, but by luck - the helper above searches everywhere GTK does.
    if [[ $gtk == Adwaita-dark ]] && ! gtk_theme_installed Adwaita-dark; then
        local dark_css="$HOME/.local/share/themes/Adwaita-dark/gtk-3.0/gtk.css"
        mkdir -p "${dark_css%/*}"
        printf '%s\n' '@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");' \
            > "$dark_css"
    fi

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

    # GTK4 / libadwaita, which needs its own copy and gets no live switch.
    #
    # libadwaita ignores gtk-theme-name entirely - measured: nudging that
    # setting did nothing to a running Nautilus - so the theme directory above
    # cannot reach it. What it does read is ~/.config/gtk-4.0/gtk.css, once, at
    # startup. bin/gtk-theme.sh puts the matching stylesheet inside the theme,
    # so this is a copy rather than anything generated here.
    #
    # The consequence is honest and unavoidable: GTK4 apps pick up a palette
    # change when they are next started, while GTK3 apps follow immediately.
    # Removing the file when no theme provides one matters as much as writing
    # it - a stale stylesheet from a previous theme would outrank whatever
    # Adwaita would otherwise do, and pin those apps to the old palette.
    local g4_css="$HOME/.local/share/themes/$gtk/gtk-4.0/gtk.css"
    if [[ -f $g4_css ]]; then
        cp -f "$g4_css" "$g4/gtk.css"
    else
        rm -f "$g4/gtk.css"
    fi

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
    seed="${_vals[browser_seed]-}"
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
                safe_seed="${_vals[outline]-}"
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
    wp="${_vals[wallpaper]-}"
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
        bg="${_vals[bg]-}"
        lua="hl.config({ general = { col = {"
        lua+=" active_border = { colors = { \"${_vals[border_active_a]-}\","
        lua+=" \"${_vals[border_active_b]-}\" }, angle = ${_vals[border_angle]-} },"
        lua+=" inactive_border = \"${_vals[border_inactive]-}\" } },"
        # What shows for the moment quickshell restarts and its wallpaper
        # surface is gone - see misc in hypr/look.lua.
        lua+=" misc = { background_color = \"rgb(${bg#\#})\" },"
        lua+=" decoration = { shadow = { color = ${_vals[shadow]-} } } })"
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
