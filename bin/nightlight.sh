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
# TWO BACKENDS, AND THE REASON IS FLICKER.
#
# wl-gammarelay-rs IS PREFERRED WHERE IT EXISTS. It is a daemon that holds the
# gamma ramp and takes a new temperature over D-Bus while running, so changing
# the warmth is a property write and the screen moves straight to it. Its own
# description is "control display temperature and brightness under wayland
# without flickering", which is the problem exactly.
#
# wlsunset, THE FALLBACK, sets its temperature once at startup - no signal, no
# socket, no D-Bus - so every change of temperature is a new process. And niri
# drops the gamma ramp whenever a client disconnects, so every one of those
# restarts flashes the screen white on the way past. Killing instead of
# stopping does not help; neither does overlapping two instances. Both were
# tried.
#
# The schedule is this script's own arithmetic on the relay path, updated once a
# minute, which also makes the dusk transition smooth rather than stepped.
#
# wl-gammarelay-rs is not packaged for Fedora: `cargo install wl-gammarelay-rs`
# puts it in ~/.cargo/bin, which is not on PATH, so it is looked for there too.
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
RELAY_UNIT=fd44-gammarelay

# This script, through any symlink, because the schedule runs as a unit whose
# ExecStart is this file again with `ramp`. ~/.config/fd44/bin is a symlink into
# the checkout, so a bare $0 would be the link and not the file.
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

# ~/.cargo/bin IS NOT ON PATH on this machine, and `command -v` therefore says
# the relay is not installed when it is - which is how a whole evening went into
# working around a flicker that the installed tool does not have.
relay_bin() {
    if command -v wl-gammarelay-rs >/dev/null 2>&1; then
        command -v wl-gammarelay-rs
    elif [[ -x "$HOME/.cargo/bin/wl-gammarelay-rs" ]]; then
        printf '%s' "$HOME/.cargo/bin/wl-gammarelay-rs"
    fi
}
have_relay() { [[ -n "$(relay_bin)" ]]; }

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
    # THE RELAY PATH, WHERE IT EXISTS. The daemon holds the ramp and this
    # script's own loop keeps the temperature right, so a change of warmth is a
    # D-Bus write rather than a new process - which is the whole difference
    # between a smooth adjustment and a white flash.
    if have_relay; then
        relay_up || return 1
        systemctl --user stop "$UNIT" 2>/dev/null
        systemd-run --user --collect --unit="$UNIT" \
            --description="Night light schedule, driven by bin/nightlight.sh" \
            "$SELF" ramp >/dev/null 2>&1 \
            || { warn "could not start $UNIT"; return 1; }
        if always_on; then say "night light on  (${NIGHT_TEMP}K, held all day)"
        else say "night light on  (${NIGHT_TEMP}K at night, ${DAY_TEMP}K by day, smooth)"
        fi
        return 0
    fi

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
# --- the relay backend ----------------------------------------------------

relay_running() { systemctl --user is-active --quiet "$RELAY_UNIT" 2>/dev/null; }

relay_up() {
    relay_running && return 0
    systemd-run --user --collect --unit="$RELAY_UNIT" \
        --description="wl-gammarelay-rs, the gamma daemon for fd44 night light" \
        "$(relay_bin)" run >/dev/null 2>&1 \
        || { warn "could not start $RELAY_UNIT"; return 1; }
    # The D-Bus name takes a moment to appear; without this the first
    # set-property after a cold start is lost.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        busctl --user status rs.wl-gammarelay >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    return 0
}

relay_set() {   # kelvin - instant, no restart, no flicker
    busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay \
        Temperature q "$1" >/dev/null 2>&1
}

relay_down() {
    # 6500 first so the screen is left neutral rather than whatever it was:
    # stopping the daemon drops the ramp anyway, but doing it in this order
    # means the one visible change is to normal rather than through it.
    relay_running && { relay_set "$DAY_TEMP"; sleep 0.2; }
    systemctl --user stop "$RELAY_UNIT" 2>/dev/null
}

# WHAT THE TEMPERATURE SHOULD BE RIGHT NOW, in kelvin.
#
# Held, that is simply the night temperature. On a schedule it is the day value
# until dusk, the night value after it, and a straight line through the half
# hour either side of sunset and sunrise - which is the part wlsunset does in
# steps and this does smoothly, because a property write costs nothing.
target_temp() {
    local now sunrise sunset
    now=$(date +%s)
    read -r sunrise sunset <<<"$(sun_times)"
    [[ -n ${sunrise:-} && -n ${sunset:-} ]] || { printf '%s' "$NIGHT_TEMP"; return; }

    local fade=1800                      # half an hour either side
    python3 -I -c '
import sys
now, sunrise, sunset, fade, day, night = (int(x) for x in sys.argv[1:])
def lerp(a, b, t): return int(a + (b - a) * max(0.0, min(1.0, t)))
if sunset - fade <= now <= sunset + fade:          # dusk: day -> night
    print(lerp(day, night, (now - (sunset - fade)) / (2 * fade)))
elif sunrise - fade <= now <= sunrise + fade:      # dawn: night -> day
    print(lerp(night, day, (now - (sunrise - fade)) / (2 * fade)))
elif sunrise + fade < now < sunset - fade:
    print(day)
else:
    print(night)
' "$now" "$sunrise" "$sunset" "$fade" "$DAY_TEMP" "$NIGHT_TEMP" 2>/dev/null \
        || printf '%s' "$NIGHT_TEMP"
}

# Today's sunrise and sunset as epoch seconds, from the same daylight.py that
# supplies the coordinates - one place knows where the machine is.
sun_times() {
    python3 -I -c '
import datetime, subprocess, sys, os
out = subprocess.run([os.path.expanduser("~/Work/fd44_hyprdot/bin/daylight.py"),
                      "--status"], capture_output=True, text=True).stdout
vals = {}
for line in out.splitlines():
    parts = line.split()
    if len(parts) >= 2 and parts[0] in ("sunrise", "sunset"):
        vals[parts[0]] = parts[1]
if "sunrise" not in vals or "sunset" not in vals:
    sys.exit(1)
today = datetime.date.today()
def ep(hhmm):
    h, m = (int(x) for x in hhmm.split(":"))
    return int(datetime.datetime.combine(today, datetime.time(h, m)).timestamp())
print(ep(vals["sunrise"]), ep(vals["sunset"]))
' 2>/dev/null
}

# The service body on the relay path: set the right temperature, then keep it
# right. A minute is far finer than the eye needs for a half-hour fade and costs
# one D-Bus write.
ramp_loop() {
    # RE-READ EVERY TICK. NIGHT_TEMP is captured once when the script starts,
    # and this loop runs inside that same long-lived process - so using it here
    # pinned the loop to whatever the setting was when the service began, and
    # every adjustment was quietly undone within the minute: the slider moved
    # the screen, and then the loop put it back.
    #
    # The same mistake as power-mode.sh reading its levels once at startup.
    # A loop that outlives a setting has to go and look at it.
    #
    # TWENTY SECONDS, NOT SIXTY. Nothing here is expensive - a file read and a
    # D-Bus write - and sixty seconds is long enough that a stale value looks
    # like a bug rather than a lag.
    while :; do
        NIGHT_TEMP="$(night_temp)"
        if always_on; then relay_set "$NIGHT_TEMP"
        else relay_set "$(target_temp)"; fi
        sleep 20
    done
}

reset_gamma() {
    command -v wlsunset >/dev/null 2>&1 || return 0
    # A one-shot instance at the day temperature, killed as soon as it has
    # applied it: there is no "reset" verb, and this is the shape the project's
    # own README suggests for undoing a ramp.
    timeout 1 wlsunset -T "$DAY_TEMP" -t $(( DAY_TEMP - 1 )) \
        -S 00:00 -s 23:59 >/dev/null 2>&1 || true
}

stop_it() {
    # The relay is stopped as well as the schedule, or the daemon would sit
    # holding whatever ramp it last applied with nothing left to update it.
    relay_down
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
    set)
        # set <kelvin> - put that temperature on the screen RIGHT NOW and do
        # nothing else: no unit restart, no settings write, no schedule change.
        #
        # THIS IS WHAT THE SLIDER CALLS WHILE YOU DRAG IT. `apply` is the honest
        # way to change the temperature - it rereads the setting and restarts
        # the schedule - but restarting a unit takes long enough to feel like
        # lag, and a slider that answers a moment after you let go is a slider
        # that feels broken.
        #
        # The ramp loop re-asserts the right value on its next tick, so this
        # cannot drift: it is a preview of a value that is about to be stored,
        # not a second source of truth.
        have_relay || { warn "set needs wl-gammarelay-rs"; exit 1; }
        [[ ${2:-} =~ ^[0-9]+$ ]] || { warn "set needs a temperature"; exit 2; }
        relay_up || exit 1
        relay_set "$2"
        exit 0
        ;;

    ramp)
        # The service body on the relay path. Not for typing: `start` runs it.
        ramp_loop
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
        if have_relay; then
            # No restart, so no flash: set it, hold it, put it back.
            relay_up || exit 1
            local back; back="$(target_temp)"
            always_on && back="$NIGHT_TEMP"
            relay_set "$k"
            sleep "$secs"
            relay_set "$back"
            exit 0
        fi
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
        if have_relay; then
            printf '  %-12s %s\n' backend "wl-gammarelay-rs (live, no flicker)"
            printf '  %-12s %s\n' relay "$(relay_running && echo running || echo stopped)"
        else
            printf '  %-12s %s\n' backend "wlsunset (restarts to change, flickers)"
            printf '  %-12s %s\n' wlsunset "$(command -v wlsunset >/dev/null && echo installed || echo 'NOT INSTALLED')"
        fi
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
