#!/usr/bin/env bash
# =========================================================================
# lock-battery.sh - battery glyph and percentage for the lock screen
# =========================================================================
#
# Usage:  lock-battery.sh <normal-hex> <warn-hex>
#
# Called from hypr/hyprlock.conf as a label's cmd[]. Prints one line of pango
# markup, or nothing at all when there is no battery - a desktop then shows an
# empty label rather than "0%" or an error.
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
n=0 now=0 full=0 units="" capsum=0 status=""
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

colour="$normal"
if (( cap < 20 )) && [[ $status != Charging ]]; then
    colour="$warn"
fi

printf '<span foreground="#%s"><span font_family="Symbols Nerd Font">%s</span>  %d%%</span>\n' \
    "$colour" "$glyph" "$cap"
