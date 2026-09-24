#!/usr/bin/env bash
#
# Point ~/.config at this checkout, so a reinstalled machine is two steps:
# clone, then run this.
#
# WHY A SCRIPT AND NOT A LIST IN THE README. The list was in four places and
# none of them was complete: the README linked four directories in one block
# and tmux in another 176 lines later, fd44_nixos/modules/desktop.nix named
# three, and starship and MangoHud were made by their own setup scripts. A
# machine rebuilt from any one of those came back missing things, and the two
# machines had already drifted apart without anyone noticing.
#
# NOTHING HERE IS DECLARATIVE, deliberately. These are files edited daily; a
# symlink means an edit is live, while putting them in the Nix store means a
# rebuild to change a colour. home-manager would only cover the NixOS machine
# anyway, and every time this configuration has differed between machines it has
# produced a bug.
#
# Safe to run as often as you like: a link that is already right is left alone,
# one pointing somewhere else is repointed, and a REAL file or directory in the
# way is reported rather than replaced - that is somebody's configuration, and a
# fresh install writes several of these itself.
#
# Usage:
#   bin/link-dotfiles.sh              # make the links
#   bin/link-dotfiles.sh --dry-run    # say what it would do
#   bin/link-dotfiles.sh --all        # include the ones this machine skips

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
# konsole keeps profiles and colour schemes under the DATA directory, not the
# config one, so linking them needs this as well.
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

dry_run=false
force_all=false
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) dry_run=true ;;
        -a|--all)     force_all=true ;;
        -h|--help)    sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed 's/^#//; s/^ //'; exit 0 ;;
        *) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

made=0 already=0 fixed=0 skipped=0 blocked=0

note()    { printf '  %s\n' "$*"; }
ok()      { printf '  \033[32m%-9s\033[0m %s\n' "$1" "$2"; }
warn()    { printf '  \033[33m%-9s\033[0m %s\n' "$1" "$2"; }
blocked() { printf '  \033[31m%-9s\033[0m %s\n' "$1" "$2"; }

# link <source relative to the repo> <destination>
link() {
    local src="$REPO/$1" dst="$2" shown="${2/#$HOME/\~}"
    if [ ! -e "$src" ]; then
        warn "missing" "$shown - $1 is not in the checkout"
        skipped=$((skipped + 1))
        return
    fi
    if [ -L "$dst" ]; then
        local current
        current="$(readlink -f "$dst" 2>/dev/null)"
        if [ "$current" = "$(readlink -f "$src")" ]; then
            ok "ok" "$shown"
            already=$((already + 1))
            return
        fi
        # A link somewhere else is ours to correct; a real file is not.
        if $dry_run; then
            warn "would fix" "$shown (points at ${current:-nothing})"
        else
            ln -sfn "$src" "$dst" && warn "repointed" "$shown (was ${current:-nothing})"
        fi
        fixed=$((fixed + 1))
        return
    fi
    if [ -e "$dst" ]; then
        blocked "in the way" "$shown is a real $( [ -d "$dst" ] && echo directory || echo file ) - move it aside first"
        blocked=$((blocked + 1))
        return
    fi
    if $dry_run; then
        note "would link $shown -> ${src/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst" && ok "linked" "$shown"
    fi
    made=$((made + 1))
}

# --- what this machine has ------------------------------------------------
#
# Several of these are not wanted everywhere, and linking them regardless would
# put configuration on machines that have nothing to read it.
#
# THE TEST IS ALWAYS "IS THE THING THAT READS THIS INSTALLED", never which
# desktop was chosen or what the hostname is. A machine that has kitty wants
# the kitty configuration whichever compositor it runs, and a machine without
# Hyprland has no use for hypr/ no matter how it was built.

has_battery()  { compgen -G "/sys/class/power_supply/BAT*" >/dev/null; }
have()         { command -v "$1" >/dev/null 2>&1; }

# A DESKTOP that owns the CPU governor - see the power-mode block.
#
# Keyed on plasmashell, not on power-profiles-daemon. PPD is installed on
# every laptop this repository builds, Hyprland ones included, and power-mode
# has coexisted with it there since it was written - so testing for PPD would
# stop linking this unit on the machine it was written for. What actually
# conflicts is powerdevil, which ships with Plasma and drives PPD itself.
has_desktop_power() { have plasmashell; }

# wants <program> <what the link is for>
#
# Prints the skip line and counts it, so a machine that is missing something
# says so rather than quietly linking less than it did last time.
wants() {
    if have "$1" || $force_all; then return 0; fi
    note "skipped   $2 - $1 is not installed here (--all to link anyway)"
    skipped=$((skipped + 1))
    return 1
}

printf '\nlinking into %s\n\n' "${REPO/#$HOME/\~}"

# The Hyprland desktop's own configuration. On a machine running something
# else - the installer can build KDE Plasma instead - these are three symlinks
# into a checkout that nothing ever reads.
wants Hyprland  "hypr"       && link hypr       "$CONFIG/hypr"
wants quickshell "quickshell" && link quickshell "$CONFIG/quickshell"
wants kitty     "kitty"      && link kitty      "$CONFIG/kitty"

# These three do not care what draws the screen.
link tmux                   "$CONFIG/tmux"
link starship/starship.toml "$CONFIG/starship.toml"
link wireplumber            "$CONFIG/wireplumber"

# Nerd Font fallback, and it is not decoration: without it the icons in the
# tmux bar and the starship prompt are empty boxes in any terminal that does
# not do kitty's font fallback. They are Material Design glyphs in plane-15
# private use area, carried by exactly one installed font - Symbols Nerd Font,
# which is a symbols-only face that nothing picks up on its own. kitty finds
# it; konsole, going through Qt and fontconfig, does not.
#
# NO `wants` TEST, because the thing that reads it is fontconfig, which is on
# every machine here. It is also not Hyprland's: the machines that NEED it are
# the ones not running kitty, so a test for kitty would have it backwards.
#
# FILE, NOT DIRECTORY, like MangoHud above: conf.d is a shared drop-in
# directory and other packages put their own files in it, so it is not ours to
# own.
link fontconfig/99-nerd-fallback.conf "$CONFIG/fontconfig/conf.d/99-nerd-fallback.conf"

# Sub-pixel rendering, for the machines Fedora leaves out. kde-settings
# enables it for KDE by testing the desktop name, so Plasma gets it and every
# Hyprland session on the same release gets grey-scale antialiasing instead -
# measured, and most of why the Plasma laptop's text looked better than the
# others. Same reasoning as the fallback above: no `wants` test, because
# fontconfig is everywhere and the machines that NEED this are the ones not
# running KDE.
link fontconfig/99-subpixel-rgb.conf "$CONFIG/fontconfig/conf.d/99-subpixel-rgb.conf"

# konsole's palette, where there is a konsole. Two files under DATA rather
# than CONFIG, which is where konsole looks for profiles and schemes.
#
# THE SCHEME IS THE TMUX BAR'S COLOURS. tmux.conf names ANSI colours instead
# of hex so the bar follows the terminal, which puts the choice of palette
# here. konsole 26 ships no scheme files at all - they are compiled into the
# binary - and starts on the classic palette, not Breeze, so the only way to
# be sure what is in the ANSI slots is to write them out.
#
# SELECTING the profile is NOT done here. konsolerc is a file konsole
# rewrites, so it cannot be a symlink; set it once per machine with
#
#     kwriteconfig6 --file konsolerc --group "Desktop Entry" \
#                   --key DefaultProfile fd44.profile
#
if wants konsole "konsole profile and Breeze colours"; then
    link konsole/fd44.profile          "$DATA/konsole/fd44.profile"
    link konsole/Breeze-fd44.colorscheme "$DATA/konsole/Breeze-fd44.colorscheme"
fi

# MangoHud, where there is a MangoHud. Linked file by file rather than as a
# directory: other things write into ~/.config/MangoHud, so it is not ours to own.
if have mangohud || $force_all; then
    link mangohud/MangoHud.conf "$CONFIG/MangoHud/MangoHud.conf"
    link mangohud/presets.conf  "$CONFIG/MangoHud/presets.conf"
else
    note "skipped   MangoHud - not installed here (--all to link anyway)"
    skipped=$((skipped + 2))
fi

# The power-mode unit switches the CPU governor on AC and battery, so it has
# nothing to do on a machine that is always on mains.
#
# AND NOTHING TO DO WHERE A DESKTOP ALREADY OWNS THE GOVERNOR. On KDE Plasma
# powerdevil does this through power-profiles-daemon, so enabling this unit as
# well gives two things opposite opinions about the same sysfs files - and the
# next line this script prints is the command to enable it, which makes that
# an easy mistake to be talked into.
#
# Hyprland laptops keep it: they have PPD installed too, but nothing in that
# session drives it, which is exactly why this unit exists there.
if ! has_battery && ! $force_all; then
    note "skipped   power-mode.service - no battery here (--all to link anyway)"
    skipped=$((skipped + 1))
elif has_desktop_power && ! $force_all; then
    note "skipped   power-mode.service - Plasma's powerdevil already manages the governor"
    skipped=$((skipped + 1))
else
    link systemd/power-mode.service "$CONFIG/systemd/user/power-mode.service"
fi

# The USB notifier has nothing machine-specific about it: any session with a
# notification daemon wants to be told what was just plugged in, desktop or
# laptop. The unit's own ConditionPathExists handles the case this script
# cannot see - being run somewhere that will never have Hyprland.
# The browser shim, on PATH under a name that cannot collide with a real
# browser. The YouTube entry below calls it by name rather than by path,
# because the Exec key reserves the characters a $HOME path would need.
# $HOME/.local/bin and not $DATA/../bin: they resolve to the same place by
# default, but ~/.local/bin is its own convention rather than anything under
# XDG_DATA_HOME, and it is the literal path systemd puts on the user PATH.
link bin/browser.sh "$HOME/.local/bin/fd44-browser"

# Web apps: desktop entries for sites that are better without a browser
# around them. They go under DATA rather than CONFIG - XDG puts application
# entries in ~/.local/share/applications - and the launcher picks them up
# with everything else, no restart needed.
link applications/youtube.desktop "$DATA/applications/youtube.desktop"

link systemd/usb-notify.service "$CONFIG/systemd/user/usb-notify.service"

# The display notifier, for the other half of the same question - a monitor
# is a drm event and never touches the usb subsystem.
link systemd/display-notify.service "$CONFIG/systemd/user/display-notify.service"

printf '\n  %d linked, %d already right, %d repointed, %d skipped, %d in the way\n' \
    "$made" "$already" "$fixed" "$skipped" "$blocked"

if [ "$blocked" -gt 0 ]; then
    printf '\n  Something real is where a link should go. Look at it, move it aside,\n'
    printf '  and run this again - it was not overwritten.\n'
fi

if [ "$made" -gt 0 ] || [ "$fixed" -gt 0 ]; then
    $dry_run || cat <<'NEXT'

  Two of these need telling:
    systemctl --user restart wireplumber
    systemctl --user daemon-reload
    systemctl --user enable --now power-mode.service usb-notify.service display-notify.service

  And the rest of a fresh machine, each opt-in and each explaining itself:
    bin/icon-bridge.sh       so quickshell can see the icon theme at all
    bin/starship-setup.sh    the two-line prompt
    bin/icon-theme.sh        the Reversal icons the palettes ask for
    bin/gaming-setup.sh      MangoHud, gamemode and the Steam pieces
    bin/plasma-setup.sh      the Plasma settings that cannot be symlinked
NEXT
fi

exit $(( blocked > 0 ? 1 : 0 ))
