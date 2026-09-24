#!/usr/bin/env bash
# =========================================================================
# usb-notify.sh - say something when a USB device is plugged in or pulled out
# =========================================================================
#
# Usage:  bin/usb-notify.sh watch            follow udev and notify (the unit)
#         bin/usb-notify.sh test < file      feed it a recorded event stream
#         bin/usb-notify.sh probe <devpath>  just the storage lookup
#
# Covers anything that enumerates as a USB device, which on this hardware is
# both ports and every expansion card: flash drives, keyboards, docks, the
# Framework's own HDMI and USB-A cards. There is no separate handling for
# USB-A against USB-C because the kernel does not distinguish them here - a
# stick in either port arrives as the same kind of event.
#
# WHAT IT DOES NOT SEE, so that the gaps are known rather than discovered:
#   - a charger, which is a power_supply device. bin/power-mode.sh watches
#     those and switches the governor on them.
#   - a monitor on USB-C in DisplayPort alt mode, which is a drm connector
#     and never touches the usb subsystem at all.
#   - Thunderbolt/USB4 peripherals, which come up on the thunderbolt
#     subsystem first; a USB device behind such a dock still shows up here.
#
# ONE EVENT PER PHYSICAL DEVICE. A single stick raises an event for the
# device and one for each of its interfaces, so this keeps DEVTYPE=usb_device
# and drops the rest. Root hubs are dropped too: they are the controllers
# built into the machine, they enumerate at boot, and vendor 1d6b is the
# Linux Foundation id every one of them carries.

set -uo pipefail

# -------------------------------------------------------------------------
# Names
# -------------------------------------------------------------------------
# udev exposes the same string twice. ID_MODEL has spaces replaced with
# underscores; ID_MODEL_ENC keeps them as \x20 escapes. The escaped one is
# the only way back to the real name - "HDMI Expansion Card" against
# "HDMI_Expansion_Card" - so it is preferred and printf %b does the decoding.
#
# A vendor is prepended only when the model does not already say it. Plenty
# of sticks report ID_VENDOR=SanDisk and ID_MODEL="SanDisk Ultra", and
# "SanDisk SanDisk Ultra" reads like a bug.
decode() {
    local s=${1-}
    [[ -z $s ]] && return
    printf '%b' "${s//\\x/\\x}"
}

device_name() {
    local vendor model
    model=$(decode "${ID_MODEL_ENC-}")
    [[ -z $model ]] && model=${ID_MODEL-}
    model=${model//_/ }

    vendor=$(decode "${ID_VENDOR_ENC-}")
    [[ -z $vendor ]] && vendor=${ID_VENDOR-}
    vendor=${vendor//_/ }

    if [[ -z $model && -z $vendor ]]; then
        # Nothing readable: fall back to the numeric id, which is at least
        # enough to look up. An unnamed device is usually a hub or a bridge.
        printf 'USB device %s:%s' "${ID_VENDOR_ID-????}" "${ID_MODEL_ID-????}"
        return
    fi
    if [[ -z $vendor || $model == *"$vendor"* ]]; then
        printf '%s' "${model:-$vendor}"
    else
        printf '%s %s' "$vendor" "$model"
    fi
}

# -------------------------------------------------------------------------
# Storage
# -------------------------------------------------------------------------
# A stick's size is the one extra fact worth the trouble: it is how you tell
# which stick you just plugged in when they are all black and unlabelled.
#
# THE BLOCK DEVICE IS NOT THERE YET when the usb_device event arrives. The
# kernel binds usb-storage, scans the SCSI host and creates /dev/sdX a moment
# later, so this polls for it rather than looking once. A second and a half
# is generous for a stick and short enough that a device which never had a
# block device - a keyboard, a dock - does not hold the notification up
# noticeably; it is announced without a size instead.
storage_line() {
    local sysfs="/sys${1#/sys}" dev="" i
    for ((i = 0; i < 15; i++)); do
        # THE DISK, NOT ITS PARTITIONS. A stick's block device sits at
        # <usb>/…:1.0/hostN/targetN/N:N:N:N/blockN/sdX - six levels down -
        # and sdX1 sits one further inside it, which "*/block/*" matches
        # just as well. Excluding anything deeper keeps this on the whole
        # device, which is what lsblk wants to be asked about anyway.
        dev=$(find "$sysfs" -maxdepth 7 \
                   -path '*/block/*' -not -path '*/block/*/*' \
                   -printf '%f\n' 2>/dev/null | head -1)
        [[ -n $dev ]] && break
        sleep 0.1
    done
    [[ -z $dev ]] && return 1

    # lsblk reads the partition table, so a stick reports the size of the
    # whole device and its label if it has one.
    local size label
    size=$(lsblk -ndo SIZE "/dev/$dev" 2>/dev/null | tr -d ' ')
    label=$(lsblk -no LABEL "/dev/$dev" 2>/dev/null | grep -m1 . || true)

    printf '%s' "/dev/$dev"
    [[ -n $size  ]] && printf ' · %s' "$size"
    [[ -n $label ]] && printf ' · %s' "$label"
    printf '\n'
}

# -------------------------------------------------------------------------
# Announcing
# -------------------------------------------------------------------------
# -a groups these under one application in the panel's history, and the icon
# is a stock freedesktop name so it follows the icon theme rather than being
# a path into this repo.
#
# A PATH, NOT A THEMED NAME, and that is not a style choice. quickshell's
# notification toast resolves a name through Quickshell.iconPath(), which
# asks Qt for the current icon theme - and in a bare Hyprland session Qt has
# not been told what that is, so every named icon comes back as the
# missing-icon chequerboard. Confirmed it is not about the name: "firefox"
# draws the chequerboard too, and the same icon passed as an absolute path
# draws correctly. Setting QT_QPA_PLATFORMTHEME=gtk3 did not fix it either.
# That is a shell-wide bug worth fixing on its own; until it is, every
# notification anything sends with a themed name looks broken, and this
# script sidesteps it by doing the lookup itself.
#
# ONCE, AT STARTUP. Icon files do not move while the service runs, and this
# would otherwise be a find(1) on every plug.
ICON_STORAGE=""
ICON_DEVICE=""

# The first file matching the name, searched the way the icon spec says to:
# the user's own directory first, then everything in XDG_DATA_DIRS, which is
# what makes this work on a distro that does not keep icons in /usr/share -
# NixOS puts them under /run/current-system/sw/share.
# SVG FIRST, ACROSS EVERY DIRECTORY, then PNG - not the first file of either
# kind in the first directory. Searching for both at once found
# AdwaitaLegacy's 16x16 png before Adwaita's scalable svg, and a 16px icon
# drawn into the toast's 28px box is a blurry postage stamp. A separate pass
# per extension costs one extra find and always prefers the one that scales.
icon_path() {
    local name=$1 ext dirs d hit
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for ext in svg png; do
        for d in "${XDG_DATA_HOME:-$HOME/.local/share}" "${dirs[@]}"; do
            [[ -d $d/icons ]] || continue
            hit=$(find -L "$d/icons" -name "$name.$ext" -print -quit 2>/dev/null)
            [[ -n $hit ]] && { printf '%s' "$hit"; return 0; }
        done
    done
    return 1
}

# Falls back to no icon at all rather than to a name, because a name is the
# thing that draws wrong. With -i omitted the toast draws its own accent dot,
# which at least looks deliberate.
notify() {
    local icon=${3:-$ICON_STORAGE}
    if [[ -n $icon ]]; then
        notify-send -a "USB" -i "$icon" "$1" "$2" 2>/dev/null && return
    else
        notify-send -a "USB" "$1" "$2" 2>/dev/null && return
    fi
    printf 'usb-notify: %s - %s\n' "$1" "$2" >&2
}

announce() {
    [[ ${DEVTYPE-} == usb_device ]]  || return 0
    [[ ${ID_VENDOR_ID-} == 1d6b ]]   && return 0   # root hub, see above

    local name; name=$(device_name)

    case "${ACTION-}" in
        add)
            local line
            if line=$(storage_line "${DEVPATH-}"); then
                notify "USB storage connected" "$name"$'\n'"$line"
            else
                notify "USB device connected" "$name" "$ICON_DEVICE"
            fi
            ;;
        remove)
            # Nothing to look up on the way out: the sysfs path is already
            # gone by the time this runs, which is why the size is only ever
            # reported on the way in.
            notify "USB device removed" "$name" "$ICON_DEVICE"
            ;;
    esac
}

# -------------------------------------------------------------------------
# The event stream
# -------------------------------------------------------------------------
# `udevadm monitor --property` prints a header line, then KEY=VALUE lines,
# then a blank line per event. Everything is collected into the environment
# and announce() reads it from there, so the parser has no knowledge of which
# keys matter and adding one is a one-line change above.
#
# EXPORTED AND THEN CLEARED, not assigned to local variables: an event that
# omits a key would otherwise leave the previous event's value in place, and
# a stick unplugged after a keyboard would be announced as the keyboard.
pump() {
    local line key val keys=()
    while IFS= read -r line; do
        if [[ -z $line ]]; then
            (( ${#keys[@]} )) && announce
            for key in "${keys[@]}"; do unset "$key"; done
            keys=()
            continue
        fi
        # The header line - "UDEV [123.4] add /devices/... (usb)" - is
        # anything that is not KEY=VALUE. Tested by shape rather than by
        # looking for a space, because plenty of real properties have one:
        # ID_MODEL_FROM_DATABASE=Fingerprint Reader would have been dropped.
        [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        key=${BASH_REMATCH[1]}
        val=${BASH_REMATCH[2]}
        printf -v "$key" '%s' "$val"
        keys+=("$key")
    done
    # A stream that ends without a trailing blank line still has one event in
    # hand - which is every recorded file, and matters only for `test`.
    if (( ${#keys[@]} )); then announce; fi

    # EXPLICIT, because the line above is the last thing that runs and its
    # status becomes the script's. On a stream that did end with a blank line
    # there is nothing left in hand, so the test is false and a clean run
    # exited 1 - which under Restart=on-failure is the difference between a
    # service that has finished and one systemd keeps resurrecting.
    return 0
}

ICON_STORAGE=$(icon_path drive-removable-media || true)
ICON_DEVICE=$(icon_path media-flash || true)

case "${1:-watch}" in
    watch)
        # --udev, not --kernel: these are the events as they leave udev with
        # the ID_* properties filled in, which is where every readable name
        # in this script comes from. The kernel's own events have none of it.
        udevadm monitor --udev --subsystem-match=usb --property | pump
        ;;
    test) pump ;;
    # The storage lookup on its own, against a DEVPATH that already exists:
    #   bin/usb-notify.sh probe /devices/pci0000:00/.../usb3/3-2
    # It is the one part that cannot be exercised from a recorded stream,
    # because it goes and reads sysfs rather than the event.
    probe) storage_line "${2:?usage: $0 probe <devpath>}" || echo "no block device under it" ;;
    *) echo "usage: $0 {watch|test|probe <devpath>}" >&2; exit 2 ;;
esac
