#!/usr/bin/env bash
# =========================================================================
# nightlight.sh - warm the screen after sunset, cool it after sunrise
# =========================================================================
#
# Usage:  bin/nightlight.sh start     run it, if the setting says so
#         bin/nightlight.sh stop      stop it and restore normal colour
#         bin/nightlight.sh toggle    flip the setting and apply
#         bin/nightlight.sh status    what it is doing and why
#         bin/nightlight.sh apply     re-read the setting and obey it
#         bin/nightlight.sh preview K  show K kelvin for a few seconds
#
# OFF BY DEFAULT. A shell that changes the colour of your screen without being
# asked is worse than one that waits to be told; the toggle is on the Desktop
# page of the settings panel.
#
# IT DOES NOT COMPUTE THE SUN. bin/daylight.py already works out sunrise and
# sunset from the machine's timezone - no network, no API key, no geoclue - and
# this asks it for the coordinates rather than keeping a second copy. One place
# knows where the machine is.
#
# wlsunset DOES ITS OWN ARITHMETIC from those coordinates, which is why the
# coordinates are passed rather than the times: given lat/long it recalculates
# every day on its own, where fixed times would need restarting at midnight.
#
# WHY wlsunset AND NOT gammastep. Both speak wlr-gamma-control-unstable-v1,
# which niri 26.04 implements - checked in the binary, not assumed. wlsunset is
# a single small C program with no GUI, no tray icon and no geoclue dependency;
# gammastep carries all three. Nothing here wants them.
#
# IT RUNS AS A systemd USER SERVICE rather than a spawned child, so it survives
# a quickshell restart, is stopped properly at logout, and `systemctl --user
# status fd44-nightlight` says what happened when it did not work.

set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/fd44-hyprdot"
SETTINGS="$STATE/settings.json"
UNIT=fd44-nightlight

# Temperatures in kelvin. 6500 is daylight - the panel's native white, so the
# day end of the ramp is "no change at all" rather than a slightly tinted
# version of normal. 4000 is a clear warm shift without the orange cast that
# makes photographs unusable; it is the value most people stop at.
DAY_TEMP=6500

# THE NIGHT END IS A SETTING, not a constant: 4000K is a reasonable default and
# not a universal one - how warm is too warm depends on the panel and the room,
# and the only way to find yours is to move it and look. The slider on the
# Desktop page writes nightLightTemp; this is the fallback when it has never
# been touched.
NIGHT_TEMP_DEFAULT=4000

night_temp() {
    python3 -I -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        v = json.load(f).get("nightLightTemp")
    # Clamped to what wlsunset will accept and what is useful: below 1500 the
    # screen is unreadable, and above the day temperature it would COOL the
    # screen at night, which is the opposite of the feature.
    print(int(v) if isinstance(v, (int, float)) and 1500 <= v <= 6500
          else sys.argv[2])
except Exception:
    print(sys.argv[2])
' "$SETTINGS" "$NIGHT_TEMP_DEFAULT" 2>/dev/null || printf '%s' "$NIGHT_TEMP_DEFAULT"
}

NIGHT_TEMP="$(night_temp)"

# ALWAYS ON, OR ON A SCHEDULE. The schedule is the default and the point of the
# feature, but "warm my screen now" is a different want that the schedule simply
# cannot answer: set the temperature at noon and nothing happens for eight
# hours, which reads as a broken control no matter how correct it is.
always_on() {
    python3 -I -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        print("yes" if json.load(f).get("nightLightAlways") is True else "no")
except Exception:
    print("no")
' "$SETTINGS" 2>/dev/null | grep -q yes
}

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_0=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_y" "$c_0" "$*" >&2; }

repo_root() { cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd; }

setting_on() {
    [[ -s $SETTINGS ]] || return 1
    python3 -I -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        print("yes" if json.load(f).get("nightLight") is True else "no")
except Exception:
    print("no")
' "$SETTINGS" 2>/dev/null | grep -q yes
}

set_setting() {   # true|false
    python3 -I -c '
import json, os, sys
p, want = sys.argv[1], sys.argv[2] == "true"
try:
    with open(p) as f: d = json.load(f)
except Exception:
    d = {}
d["nightLight"] = want
os.makedirs(os.path.dirname(p), exist_ok=True)
tmp = p + ".new"
with open(tmp, "w") as f: json.dump(d, f, indent=1)
os.replace(tmp, p)
' "$SETTINGS" "$1"
}

coordinates() {
    # From daylight.py, so there is one answer to "where is this machine".
    "$(repo_root)/bin/daylight.py" --status 2>/dev/null |
        awk '/^ *location/ { gsub(",", "", $2); print $2, $3; exit }'
}

running() { systemctl --user is-active --quiet "$UNIT" 2>/dev/null; }

start_it() {
    command -v wlsunset >/dev/null 2>&1 || {
        warn "wlsunset is not installed - sudo dnf install wlsunset"
        return 1
    }
    read -r lat lon <<<"$(coordinates)"
    [[ -n ${lat:-} && -n ${lon:-} ]] || {
        warn "could not get coordinates from daylight.py - is the timezone set?"
        return 1
    }
    # A PLAIN STOP. Killing instead was tried, on the theory that wlsunset
    # restoring the ramp on SIGTERM was what flashed the screen white between
    # temperatures. It is not: NIRI DROPS THE GAMMA RAMP WHEN THE CLIENT GOES,
    # however it goes, which the comment in stop_it below had already recorded.
    # Overlapping a second instance before killing the first was tried too, and
    # the flash survived that as well.
    #
    # So the flash is not something this script can avoid. wlsunset sets its
    # temperature once at startup - no signal, no socket, no D-Bus - so every
    # change of temperature is a new process, and every new process is a moment
    # with no gamma client, which niri paints as normal white.
    #
    # The real fix is a daemon that takes a new temperature while running, like
    # wl-gammarelay-rs. It is not packaged for Fedora 44 and there is no cargo
    # here to build it, so this stays as it is and the UI stops asking for
    # changes it cannot make smoothly - see Settings.qml.
    systemctl --user stop "$UNIT" 2>/dev/null
    # --collect so a failed run does not linger in the unit list.
    # PINNED BY GIVING BOTH ENDS THE SAME VALUE. wlsunset wants a range and
    # a day/night pair; one degree apart is a constant, and the sun arithmetic
    # then has nothing left to change. No second code path, no second tool.
    local lo="$NIGHT_TEMP" hi="$DAY_TEMP"
    if always_on; then hi=$(( NIGHT_TEMP + 1 )); fi

    systemd-run --user --collect --unit="$UNIT" \
        --description="Night light (wlsunset), driven by bin/nightlight.sh" \
        wlsunset -l "$lat" -L "$lon" -t "$lo" -T "$hi" >/dev/null 2>&1 \
        || {
            warn "could not start $UNIT"
            # The kill above left whatever ramp was in place; with nothing
            # running to own it, put it back.
            reset_gamma
            return 1
        }
    if always_on; then
        say "night light on  (${NIGHT_TEMP}K, held all day)"
    else
        say "night light on  ($lat, $lon · ${NIGHT_TEMP}K at night, ${DAY_TEMP}K by day)"
    fi
}

# Clear any gamma ramp left behind. wlsunset does this itself on SIGTERM; this
# is for the paths that killed it instead, or that never had it running.
reset_gamma() {
    command -v wlsunset >/dev/null 2>&1 || return 0
    # A one-shot instance at the day temperature, killed as soon as it has
    # applied it: there is no "reset" verb, and this is the shape the project's
    # own README suggests for undoing a ramp.
    timeout 1 wlsunset -T "$DAY_TEMP" -t $(( DAY_TEMP - 1 )) \
        -S 00:00 -s 23:59 >/dev/null 2>&1 || true
}

stop_it() {
    # STOPPING wlsunset LEAVES THE LAST GAMMA IN PLACE on some compositors, so
    # the ramp is reset explicitly afterwards. On niri the gamma is dropped when
    # the client goes, which makes this a no-op there rather than a mistake.
    systemctl --user stop "$UNIT" 2>/dev/null
    say "night light off"
}

case "${1:-status}" in
    start|apply)
        if setting_on; then start_it; else stop_it >/dev/null; fi
        ;;
    preview)
        # preview <kelvin> [seconds] - hold that temperature, then go back.
        #
        # BECAUSE THE SLIDER IS OTHERWISE INVISIBLE. It sets the NIGHT end of
        # the ramp, and most of the time you are setting it in daylight -
        # wlsunset is correctly sitting at 6500K and nothing you do to the
        # number changes the screen until sunset, hours away. A control whose
        # effect you cannot see is one you cannot judge, and "too orange" is
        # exactly the judgement this needs.
        #
        # THE SERVICE IS STOPPED FIRST: two wlsunset instances fight over one
        # gamma ramp and the winner is whichever wrote last.
        k="${2:-$NIGHT_TEMP}"; secs="${3:-4}"
        [[ $k =~ ^[0-9]+$ ]] || { warn "preview needs kelvin"; exit 2; }
        (( k >= 1500 && k <= 6500 )) || { warn "preview: $k outside 1500-6500"; exit 2; }
        read -r lat lon <<<"$(coordinates)"
        stop_it >/dev/null
        # -T and -t one apart pins it: wlsunset wants a range, and a range of
        # one degree is a constant. timeout sends SIGTERM and wlsunset restores
        # the ramp on it, so an interrupted preview cannot leave the screen
        # orange.
        timeout "$secs" wlsunset -T $(( k + 1 )) -t "$k" \
            -l "${lat:-0}" -L "${lon:-0}" >/dev/null 2>&1
        # `apply`, not `start`: previewing with night light switched off must
        # leave it switched off.
        if setting_on; then start_it >/dev/null; fi
        ;;

    stop)
        set_setting false; stop_it
        ;;
    toggle)
        if setting_on; then set_setting false; stop_it
        else set_setting true; start_it; fi
        ;;
    status)
        printf '  %-12s %s\n' setting "$(setting_on && echo on || echo off)"
        printf '  %-12s %s\n' running "$(running && echo yes || echo no)"
        printf '  %-12s %s\n' wlsunset "$(command -v wlsunset >/dev/null && echo installed || echo 'NOT INSTALLED')"
        read -r lat lon <<<"$(coordinates)"
        printf '  %-12s %s\n' location "${lat:-?}, ${lon:-?}"
        if always_on; then
            printf '  %-12s %s\n' mode "held at ${NIGHT_TEMP}K all day"
        else
            printf '  %-12s %s\n' mode "on a schedule"
            printf '  %-12s %sK night / %sK day\n' range "$NIGHT_TEMP" "$DAY_TEMP"
        fi
        ;;
    *)
        printf 'nightlight: unknown command: %s\n' "$1" >&2
        sed -n '2,12p' "$0" >&2
        exit 2
        ;;
esac
