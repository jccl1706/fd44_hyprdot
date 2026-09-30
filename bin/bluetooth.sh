#!/usr/bin/env bash
# =========================================================================
# bluetooth.sh - what the adapter and its devices are doing, for the bar
# =========================================================================
#
# Usage:  bin/bluetooth.sh status            the adapter and what is connected
#         bin/bluetooth.sh devices           the paired devices, as JSON
#         bin/bluetooth.sh connect MAC
#         bin/bluetooth.sh disconnect MAC
#         bin/bluetooth.sh power on|off
#
# WHY A SCRIPT AND NOT Quickshell.Bluetooth. That module does exist in
# quickshell 0.3.1 - the import resolves and the singleton carries
# defaultAdapter, adapters and devices - but MEASURED on the Framework it
# reports `defaultAdapter = null` and zero adapters while bluetoothctl shows
# hci0 powered, paired and connected at the same moment. A module that answers
# "no adapter" on a machine with one would draw an icon that is simply wrong,
# so this asks bluez the way the rest of the repository asks its system: a
# script that answers, and QML that only draws.
#
# EVERY PATH EXITS 0 AND EMITS JSON, including the failures. An indicator whose
# backend crashed should read "unknown" and disappear, not leave the bar showing
# the last thing that happened to be true.
#
# NO PAIRING HERE, deliberately. Pairing is a one-time, occasionally
# interactive act - a PIN, a confirmation, a device in the right mode - and a
# panel that offers it has to handle all of that or lie about it. Connecting
# and disconnecting something already paired is the daily operation, and that
# is what the bar does; `bluetoothctl` pairs.

set -uo pipefail

esc() { printf '%s' "${1//\\/\\\\}" | sed 's/"/\\"/g'; }

have() { command -v bluetoothctl >/dev/null 2>&1; }

# Battery is optional and only some devices report it. bluez prints it as
#   Battery Percentage: 0x50 (80)
# and the decimal in brackets is the one to read - 0x50 would be 80 anyway, but
# not every device is that tidy.
battery_of() { # mac
    timeout 5 bluetoothctl info "$1" 2>/dev/null \
        | sed -n 's/.*Battery Percentage:.*(\([0-9]\+\)).*/\1/p' | head -1
}

name_of() { # mac
    timeout 5 bluetoothctl info "$1" 2>/dev/null \
        | sed -n 's/^[[:space:]]*Name:[[:space:]]*//p' | head -1
}

cmd_status() {
    local powered="false" present="false" connected=0 name="" battery=-1 mac=""
    if ! have; then
        printf '{"present":false,"powered":false,"connected":0,"name":"","battery":-1,"error":"no bluetoothctl"}\n'
        return 0
    fi
    # No adapter at all - a desktop without a dongle - is not an error, it is a
    # machine with no Bluetooth, and the bar draws nothing. Same shape as
    # thermal.sh on a laptop with no discrete card.
    if [[ -n "$(timeout 5 bluetoothctl list 2>/dev/null)" ]]; then
        present="true"
        timeout 5 bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && powered="true"
    fi

    # The FIRST connected device, because the bar shows one glyph. Two headsets
    # at once is possible and rare; the panel lists them all.
    while read -r _ m rest; do
        [[ -n $m ]] || continue
        connected=$(( connected + 1 ))
        if [[ -z $mac ]]; then mac="$m"; name="$rest"; fi
    done < <(timeout 5 bluetoothctl devices Connected 2>/dev/null)

    if [[ -n $mac ]]; then
        local b; b="$(battery_of "$mac")"
        [[ -n $b ]] && battery="$b"
    fi

    printf '{"present":%s,"powered":%s,"connected":%d,"name":"%s","mac":"%s","battery":%d,"error":""}\n' \
        "$present" "$powered" "$connected" "$(esc "$name")" "$(esc "$mac")" "$battery"
}

cmd_devices() {
    have || { printf '[]\n'; return 0; }
    local first=1 mac name conn trusted batt
    printf '['
    # PAIRED, not "everything in range". A scan turns up every lock, television
    # and LED strip in the building - twenty-six of them here - and none of that
    # belongs in a list whose rows are all connect buttons.
    while read -r _ mac name; do
        [[ -n $mac ]] || continue
        conn=false; trusted=false; batt=-1
        local info; info="$(timeout 5 bluetoothctl info "$mac" 2>/dev/null)"
        grep -q "Connected: yes" <<<"$info" && conn=true
        grep -q "Trusted: yes"   <<<"$info" && trusted=true
        local b; b="$(sed -n 's/.*Battery Percentage:.*(\([0-9]\+\)).*/\1/p' <<<"$info" | head -1)"
        [[ -n $b ]] && batt="$b"
        # The icon bluez itself assigns - audio-headset, input-mouse, phone -
        # so the panel can draw the right glyph without guessing from the name.
        local icon; icon="$(sed -n 's/^[[:space:]]*Icon:[[:space:]]*//p' <<<"$info" | head -1)"
        (( first )) || printf ','
        first=0
        printf '{"mac":"%s","name":"%s","connected":%s,"trusted":%s,"battery":%d,"icon":"%s"}' \
            "$(esc "$mac")" "$(esc "$name")" "$conn" "$trusted" "$batt" "$(esc "$icon")"
    done < <(timeout 5 bluetoothctl devices Paired 2>/dev/null)
    printf ']\n'
}

case "${1:-status}" in
    status)  cmd_status ;;
    devices) cmd_devices ;;
    # 20 seconds: a headset that is asleep in its case takes several to answer,
    # and a connect that gives up in two looks like a failure that is not one.
    connect)    timeout 20 bluetoothctl connect "${2:?mac}"    >/dev/null 2>&1; cmd_status ;;
    disconnect) timeout 10 bluetoothctl disconnect "${2:?mac}" >/dev/null 2>&1; cmd_status ;;
    power)      timeout 10 bluetoothctl power "${2:?on|off}"   >/dev/null 2>&1; cmd_status ;;
    -h|--help|help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) printf 'bluetooth: unknown command: %s\n' "$1" >&2; exit 2 ;;
esac
