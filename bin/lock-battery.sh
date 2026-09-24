#!/usr/bin/env bash
# =========================================================================
# lock-battery.sh - battery glyph and percentage for the lock screen
# =========================================================================
#
# Usage:  lock-battery.sh <normal-hex> <warn-hex>
#         lock-battery.sh --tmux
#
# Called from hypr/hyprlock.conf as a label's cmd[]. Prints one line of pango
# markup, or nothing at all when there is no battery - a desktop then shows an
# empty label rather than "0%" or an error.
#
# --tmux prints the same glyph and percentage for tmux's status-right instead
# (tmux/tmux.conf): plain text with a trailing gap before whatever follows it,
# red through tmux's own #[fg=...] when the line would be the warning colour.
# ANSI red rather than a theme hex, like the rest of that status bar. kitty
# finds the glyph in Symbols Nerd Font by fallback, so no font is named.
#
# WHY MARKUP RATHER THAN PLAIN TEXT. A hyprlock label has ONE font_family, and
# this needs two: the glyph is in Symbols Nerd Font and the digits should be
# Inter like everything else. Rendering the label as markup lets the glyph
# carry its own font while the rest of the line inherits the label's. Same
# reason the password field's placeholder is markup.
#
# The two colours are passed in rather than hardcoded so they come from the
# active theme: hyprlock.conf spells them $dimHex and $dangerHex, which
# bin/theme.sh generates alongside the rgba() forms. Below 20% and not
# charging, the whole line switches to the warning colour - a lock screen is
# often the last thing seen before a machine is left alone, and "you are about
# to lose power" is worth more than consistency with the clock beside it.

set -euo pipefail

mode=pango
if [[ ${1:-} == --tmux ]]; then
    mode=tmux
    shift
fi
normal="${1:-9893a5}"
warn="${2:-b4637a}"

# EVERY battery, summed. A ThinkPad T480 has an internal BAT0 and a removable
# BAT1, and the first one found is not the whole story: measured there,
# BAT0 15 Wh at 33% (not charging) and BAT1 59 Wh at 41% (charging).
#
# Weighted by what each holds, not averaged: that pair is 29.6 of 74.6 Wh,
# 40%, where averaging the two percentages says 37%. Energy (µWh) where the
# battery reports it, charge (µAh) where it does not - the Framework only has
# charge_*. Units cannot be mixed, so a set that mixes them, or reports
# neither, falls back to the mean of the capacity files.
#
# Status: Charging if any battery is, else Discharging if any is, else the
# first reported ("Not charging" at a charge limit, "Full").
n=0 now=0 full=0 rate=0 units="" capsum=0 status=""
for d in /sys/class/power_supply/BAT*; do
    [[ -d $d ]] || continue
    n=$((n + 1))
    c="$(cat "$d/capacity" 2>/dev/null || echo "")"
    [[ $c =~ ^[0-9]+$ ]] && capsum=$((capsum + c))
    if [[ -r $d/energy_now && -r $d/energy_full ]]; then u=energy
    elif [[ -r $d/charge_now && -r $d/charge_full ]]; then u=charge
    else u=none
    fi
    [[ -z $units ]] && units=$u
    [[ $u == "$units" ]] || units=mixed
    if [[ $u != none ]]; then
        now=$((now + $(< "$d/${u}_now")))
        full=$((full + $(< "$d/${u}_full")))

        # The DRAW, for the time estimate further down. Which file holds it
        # follows the unit the battery reports in: a charge-based battery
        # measures current in uA, an energy-based one power in uW. Summed
        # across batteries like the rest - the T480 has two and the pack
        # empties at their combined rate.
        #
        # ABSOLUTE VALUE, because some firmware signs the reading by direction
        # and reports a negative current while charging. The status field
        # already says which way it is going, so the sign is redundant at best
        # and gives a negative time at worst.
        r=""
        [[ $u == charge && -r $d/current_now ]] && r="$(< "$d/current_now")"
        [[ $u == energy && -r $d/power_now   ]] && r="$(< "$d/power_now")"
        if [[ $r =~ ^-?[0-9]+$ ]]; then
            (( r < 0 )) && r=$(( -r ))
            rate=$((rate + r))
        fi
    fi
    s="$(cat "$d/status" 2>/dev/null || echo Unknown)"
    case $s in
        Charging)    status=Charging ;;
        Discharging) [[ $status == Charging ]] || status=Discharging ;;
        *)           [[ -n $status ]] || status=$s ;;
    esac
done

# No battery is not an error - print nothing and let the label be empty.
(( n )) || exit 0

if [[ $units == energy || $units == charge ]] && (( full > 0 )); then
    cap=$(( (now * 100 + full / 2) / full ))
else
    cap=$(( capsum / n ))
fi
(( cap > 100 )) && cap=100

# Overrides, for checking the branches that need a nearly flat battery to
# reach. The warning colour and the alert glyph are otherwise only verifiable
# by waiting for the machine to almost die:
#   LOCK_BATTERY_CAP=8 LOCK_BATTERY_STATUS=Discharging bin/lock-battery.sh
cap="${LOCK_BATTERY_CAP:-$cap}"
status="${LOCK_BATTERY_STATUS:-$status}"
[[ $cap =~ ^[0-9]+$ ]] || exit 0

# ---- how long is left ----------------------------------------------------
#
# now / rate is hours, in whatever unit the battery reports: uAh over uA, or
# uWh over uW. The units cancel, so nothing has to be converted and no voltage
# has to be guessed at. Checked against upower on the Framework - 2386000 over
# 593000 gave 4h02 where upower said 4.1 hours.
#
# DISCHARGING COUNTS DOWN FROM `now`, CHARGING COUNTS UP TO `full`. They are
# different sums, and getting them the right way round is the whole of it.
#
# BLANK WHENEVER THE ANSWER WOULD BE A GUESS, which is more often than it
# looks. A rate of zero means nothing is moving - true on this laptop whenever
# it sits at the BIOS charge limit reporting "Not charging" - and a status
# that is neither charging nor discharging has no direction to count in. No
# estimate is better than a confident wrong one, and the bar then shows the
# percentage exactly as it did before.
remain=""
if (( rate > 0 )) && [[ $units == energy || $units == charge ]]; then
    left=0
    case $status in
        Discharging) left=$now ;;
        Charging)    (( full > now )) && left=$(( full - now )) ;;
    esac
    if (( left > 0 )); then
        mins=$(( (left * 60 + rate / 2) / rate ))
        # A reading taken as a load changes can be absurd: a machine that has
        # just woken reports a draw near zero and "99h". Over a day is not
        # information.
        if (( mins > 0 && mins < 1440 )); then
            if (( mins >= 60 )); then
                remain="$(( mins / 60 ))h$(printf '%02d' $(( mins % 60 )))"
            else
                remain="${mins}m"
            fi
        fi
    fi
fi

# Material Design Icons battery set, the same family the bar's glyphs come
# from. Written as \U escapes rather than pasted characters so the codepoints
# are readable and checkable here - a pasted glyph in a shell script is
# indistinguishable from any other glyph on inspection.
#
# Charging gets its own glyph rather than a colour change: at a glance a
# colour says "how full" and a shape says "what is happening".
if [[ $status == Charging ]]; then
    glyph=$'\UF0084'                        # battery-charging
elif (( cap >= 95 )); then glyph=$'\UF0079'  # battery (full)
elif (( cap >= 85 )); then glyph=$'\UF0082'  # battery-90
elif (( cap >= 75 )); then glyph=$'\UF0081'  # battery-80
elif (( cap >= 65 )); then glyph=$'\UF0080'  # battery-70
elif (( cap >= 55 )); then glyph=$'\UF007F'  # battery-60
elif (( cap >= 45 )); then glyph=$'\UF007E'  # battery-50
elif (( cap >= 35 )); then glyph=$'\UF007D'  # battery-40
elif (( cap >= 25 )); then glyph=$'\UF007C'  # battery-30
elif (( cap >= 15 )); then glyph=$'\UF007B'  # battery-20
elif (( cap >=  5 )); then glyph=$'\UF007A'  # battery-10
else                       glyph=$'\UF0083'  # battery-alert
fi

low=0
# AT OR BELOW 20, not under it, which is how quickshell/Battery.qml and the
# "Battery low" notification both read it. `< 20` left exactly 20% as the one
# reading where the shell said low and this did not.
(( cap <= 20 )) && [[ $status != Charging ]] && low=1

if [[ $mode == tmux ]]; then
    # The estimate is dimmed. The percentage is a fact; the time is a
    # projection from the draw of this instant and moves about as the machine
    # does. brightblack says "supporting detail" rather than putting a second
    # thing in the corner of the bar competing for attention.
    t=""
    [[ -n $remain ]] && t="#[fg=brightblack] $remain#[default]"
    if (( low )); then
        printf '#[fg=red]%s %d%%#[default]%s  ' "$glyph" "$cap" "$t"
    else
        printf '%s %d%%%s  ' "$glyph" "$cap" "$t"
    fi
    exit 0
fi

colour="$normal"
(( low )) && colour="$warn"

printf '<span foreground="#%s"><span font_family="Symbols Nerd Font">%s</span>  %d%%</span>\n' \
    "$colour" "$glyph" "$cap"
