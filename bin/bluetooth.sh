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
#         bin/bluetooth.sh scan on|off       look for devices nearby
#         bin/bluetooth.sh discovered [all]  what is nearby and not paired
#         bin/bluetooth.sh pair MAC          pair, trust and connect
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
# PAIRING IS HERE NOW, AND WAS NOT AT FIRST. The original reasoning was that
# pairing is occasionally interactive - a PIN, a confirmation, a device held in
# the right mode - and that a panel offering it has to handle all of that or lie.
# What that reasoning missed is the case that actually happened: a headset
# dropped out of bluez entirely, and a panel that only lists PAIRED devices then
# shows an empty list and offers nothing at all. The daily operation stopped
# being possible from the bar at exactly the moment it was needed.
#
# So: `scan on` discovers, `discovered` lists what is nearby and not already
# known, and `pair` does the pair/trust/connect sequence in one. A device that
# wants a PIN still needs `bluetoothctl` - that has not changed, and the panel
# says so rather than pretending.
#
# SCANNING IS TIME-LIMITED AT THE SOURCE. `bluetoothctl --timeout` stops the
# discovery itself, so a panel left open, a crash or a forgotten toggle cannot
# leave the adapter scanning for the rest of the day - which costs battery on the
# laptop and floods the list with every lock and lightbulb in the building.

set -uo pipefail

# BLUETOOTHCTL COLOURS ITS OUTPUT, and that is not cosmetic here.
#
#     ^[[1;30mDevice 24:24:B7:03:62:B1 JULIO's Buds3 Pro^[[0m
#
# A raw ESC inside a JSON string is an invalid control character, so the name
# above made this script's own output unparseable - JSON.parse threw in
# Bluetooth.qml, the catch set present=false, and the icon vanished from the
# bar. It only happened WITH A DEVICE CONNECTED, because that is when `name` is
# non-empty, which is why it looked like the icon "kept disappearing" rather
# than never working.
strip_ansi() { sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g'; }

# AND IT INTERLEAVES ITS EVENT STREAM with command output:
#
#     [^[[0;93mCHG^[[0m] Device 0C:95:05:19:FF:42 RSSI: 0xffffffc4 (-60)
#
# That is a notification about a device in range, not a listing. The loops
# below read field 2 as the address, which on such a line is the literal word
# "Device" - counted as a connected device, so `connected` drifted upwards as
# events arrived. A line is only a listing if it starts with Device and the
# next field is an address.
is_mac() { [[ $1 =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; }

# Quotes and backslashes for JSON, AND any control character - a device name is
# whatever its maker typed, and one stray byte invalidates the whole object.
esc() { printf '%s' "${1//\\/\\\\}" | sed -e 's/"/\\"/g' -e 's/[[:cntrl:]]//g'; }

have() { command -v bluetoothctl >/dev/null 2>&1; }

# Battery is optional and only some devices report it. bluez prints it as
#   Battery Percentage: 0x50 (80)
# and the decimal in brackets is the one to read - 0x50 would be 80 anyway, but
# not every device is that tidy.
battery_of() { # mac
    timeout 5 bluetoothctl info "$1" 2>/dev/null | strip_ansi \
        | sed -n 's/.*Battery Percentage:.*(\([0-9]\+\)).*/\1/p' | head -1
}

name_of() { # mac
    timeout 5 bluetoothctl info "$1" 2>/dev/null | strip_ansi \
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
    #
    # ASKED OF THE KERNEL, NOT OF bluetoothctl. `bluetoothctl list` prints
    # nothing both when there is no adapter and when the call simply does not
    # get an answer - a busy daemon, a D-Bus hiccup, the 5s timeout above
    # expiring - and those two are indistinguishable in its output. The bar
    # LATCHES on the answer (Bluetooth.qml stops polling once told there is no
    # adapter, so as not to fork a process every ten seconds forever on a
    # machine that has none), which turns one bad answer into an icon that
    # never comes back until quickshell restarts. That is how it presented on
    # framework00: adapter up, service active, rfkill clear, and no icon.
    #
    # /sys/class/bluetooth/hci* is the kernel's own view. No daemon, no IPC, no
    # timeout, nothing to be busy - it cannot answer wrongly.
    if compgen -G "/sys/class/bluetooth/hci*" >/dev/null; then
        present="true"
        # bluetoothctl is still the right tool for everything BELOW presence:
        # powered, connected, names. Those are daemon state and have no kernel
        # equivalent - and being wrong about them for ten seconds is a stale
        # glyph, not a vanished one.
        timeout 5 bluetoothctl show 2>/dev/null | strip_ansi | grep -q "Powered: yes" && powered="true"
    fi

    # The FIRST connected device, because the bar shows one glyph. Two headsets
    # at once is possible and rare; the panel lists them all.
    while read -r kw m rest; do
        # A LISTING, not an event - see is_mac above. "[CHG] Device <mac> RSSI:"
        # arrives on this stream too and used to be counted as a connection.
        [[ $kw == Device ]] || continue
        is_mac "$m" || continue
        connected=$(( connected + 1 ))
        if [[ -z $mac ]]; then mac="$m"; name="$rest"; fi
    done < <(timeout 5 bluetoothctl devices Connected 2>/dev/null | strip_ansi)

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
        local info; info="$(timeout 5 bluetoothctl info "$mac" 2>/dev/null | strip_ansi)"
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
    done < <(timeout 5 bluetoothctl devices Paired 2>/dev/null | strip_ansi)
    printf ']\n'
}

# Discovery runs as a detached bluetoothctl, because bluez ties a scan to the
# D-Bus client that asked for it: a one-shot `busctl call StartDiscovery` stops
# the moment the caller exits, which is immediately.
scan_pidfile() { printf '%s/fd44-bt-scan.pid' "${XDG_RUNTIME_DIR:-/tmp}"; }

scan_running() {
    local pid
    pid="$(cat "$(scan_pidfile)" 2>/dev/null)" || return 1
    [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null
}

cmd_scan() {
    case "${1:-}" in
        on)
            scan_running && return 0
            # 120 seconds: long enough to catch a headset being put into pairing
            # mode, short enough that forgetting about it costs nothing.
            setsid bluetoothctl --timeout 120 scan on >/dev/null 2>&1 &
            printf '%s' "$!" > "$(scan_pidfile)"
            ;;
        off)
            local pid
            pid="$(cat "$(scan_pidfile)" 2>/dev/null)" || true
            [[ -n ${pid:-} ]] && kill "$pid" 2>/dev/null
            rm -f "$(scan_pidfile)"
            ;;
        *) printf 'bluetooth: scan on|off\n' >&2; return 2 ;;
    esac
    cmd_status
}

# What is nearby and NOT already paired. Named devices only, by default: a scan
# here turns up twenty-six locks, televisions and LED strips, and a list whose
# every row is a "pair with this" button has no business offering them. Pass
# `all` to see the unnamed ones too.
cmd_discovered() {
    have || { printf '[]\n'; return 0; }
    local want_all="${1:-named}" first=1 mac name paired icon info
    local -A is_paired=()
    while read -r _ mac _; do [[ -n $mac ]] && is_paired["$mac"]=1; done \
        < <(timeout 5 bluetoothctl devices Paired 2>/dev/null | strip_ansi)
    printf '['
    while read -r _ mac name; do
        [[ -n $mac ]] || continue
        [[ -n ${is_paired[$mac]:-} ]] && continue
        # bluez names an unknown device after its own address, with dashes. That
        # is not a name, it is the absence of one.
        if [[ $want_all != all && ( -z $name || $name == "${mac//:/-}" ) ]]; then
            continue
        fi
        info="$(timeout 5 bluetoothctl info "$mac" 2>/dev/null | strip_ansi)"
        icon="$(sed -n 's/^[[:space:]]*Icon:[[:space:]]*//p' <<<"$info" | head -1)"
        (( first )) || printf ','
        first=0
        printf '{"mac":"%s","name":"%s","icon":"%s"}' \
            "$(esc "$mac")" "$(esc "$name")" "$(esc "$icon")"
    done < <(timeout 5 bluetoothctl devices 2>/dev/null | strip_ansi)
    printf ']\n'
}

# Pair, trust, connect - the three that always go together for a headset. trust
# is the one people skip and then wonder why it does not come back by itself
# after a reboot.
cmd_pair() {
    local mac="${1:?mac}"
    # PAIRABLE FIRST, AND THIS IS NOT A FORMALITY. An adapter that is not in
    # bondable mode makes bluez answer "No Bonding" in the IO capability
    # exchange, so the link key the headset offers is generated, delivered and
    # then discarded - pairing succeeds, audio works, and nothing is stored, so
    # the device can never reconnect by itself. Caught with btmon:
    #
    #   < IO Capability Request Reply   Authentication: No Bonding      (us)
    #   > IO Capability Response        Authentication: General Bonding (the buds)
    #   > Link Key Notification         ...and then no [LinkKey] on disk
    #
    # It cost an afternoon because every symptom pointed elsewhere: the pairing
    # "disappearing", a device that was Paired but not Bonded, a Trusted flag on
    # a device with no key.
    timeout 5 bluetoothctl pairable on >/dev/null 2>&1
    timeout 30 bluetoothctl pair "$mac"    >/dev/null 2>&1
    timeout 10 bluetoothctl trust "$mac"   >/dev/null 2>&1
    timeout 20 bluetoothctl connect "$mac" >/dev/null 2>&1
    cmd_status
}

case "${1:-status}" in
    status)  cmd_status ;;
    devices) cmd_devices ;;
    # 20 seconds: a headset that is asleep in its case takes several to answer,
    # and a connect that gives up in two looks like a failure that is not one.
    connect)    timeout 20 bluetoothctl connect "${2:?mac}"    >/dev/null 2>&1; cmd_status ;;
    disconnect) timeout 10 bluetoothctl disconnect "${2:?mac}" >/dev/null 2>&1; cmd_status ;;
    power)      timeout 10 bluetoothctl power "${2:?on|off}"   >/dev/null 2>&1; cmd_status ;;
    scan)       cmd_scan "${2:-}" ;;
    discovered) cmd_discovered "${2:-named}" ;;
    pair)       cmd_pair "${2:?mac}" ;;
    -h|--help|help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) printf 'bluetooth: unknown command: %s\n' "$1" >&2; exit 2 ;;
esac
