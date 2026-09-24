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
# draws correctly. QT_QPA_PLATFORMTHEME was tried at gtk3, gnome and
# xdgdesktopportal and changed nothing. That is a shell-wide bug worth
# fixing on its own; until it is, every notification anything sends with a
# themed name looks broken, and this script does the lookup itself.
#
# THROUGH THE THEME THE SYSTEM IS SET TO, not whichever copy of the file
# turns up first. bin/theme.sh writes that name - the palette's icon_theme,
# or Adwaita while Reversal is not installed - into gsettings and the GTK
# settings files, so the icon in the notification changes with the rest of
# the desktop instead of being pinned to one theme.
#
# CACHED, BUT RE-READ WHEN THE THEME CHANGES. Resolving once at startup was
# the first version and it was wrong for the thing this is for: bin/theme.sh
# switches the icon theme with the palette, and a service started hours
# earlier would have gone on pointing at the old theme's files until the
# session was restarted. Checking the theme NAME is one gsettings call; it
# is only the find(1) that is worth avoiding, and that now runs when the
# answer would actually be different.
ICON_THEME=""
ICON_STORAGE=""
ICON_DEVICE=""


# What the desktop is set to. gsettings is what theme.sh writes last and what
# GTK4 reads, the settings.ini is the GTK3 copy of the same answer, and
# hicolor is the spec's own fallback - every theme inherits it and it is the
# only one guaranteed to exist.
current_icon_theme() {
    local t
    t=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "\"'")
    if [[ -n $t && $t != "@as"* ]]; then printf '%s' "$t"; return; fi
    t=$(sed -n 's/^gtk-icon-theme-name=//p' \
            "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | tail -1)
    if [[ -n $t ]]; then printf '%s' "$t"; return; fi
    printf 'hicolor'
}

# Every directory a theme could live in, in the order the icon spec searches
# them: the user's own first, then XDG_DATA_DIRS. ~/.icons is the old
# location and is still what bin/icon-theme.sh's upstream installer uses on
# some systems, so it stays in the list.
icon_bases() {
    local dirs d
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    printf '%s\n' "$HOME/.icons" "${XDG_DATA_HOME:-$HOME/.local/share}/icons"
    for d in "${dirs[@]}"; do printf '%s\n' "$d/icons"; done
}

# A theme names its fallbacks in index.theme. Reversal-grey-dark inherits
# Reversal-grey which inherits Adwaita, and following that chain is the
# difference between "the theme has no icon for this" and "the theme has not
# bothered to redraw one that Adwaita already has".
theme_parents() {
    local theme=$1 base line
    while read -r base; do
        [[ -f $base/$theme/index.theme ]] || continue
        line=$(sed -n 's/^Inherits=//p' "$base/$theme/index.theme" | head -1)
        [[ -n $line ]] && printf '%s\n' "${line//,/ }"
        return
    done < <(icon_bases)
}

# SVG BEFORE PNG WITHIN A THEME, and the largest PNG when there is no SVG.
# Asking find for both at once returned AdwaitaLegacy's 16x16 png before
# Adwaita's scalable svg, and 16px drawn into the toast's 28px box is a
# blurry postage stamp. The size comes out of the NNxNN directory the spec
# requires, and anything without one sorts last rather than being dropped -
# a scalable/ png is still better than nothing.
icon_in_theme() {
    local theme=$1 name=$2 base hit
    while read -r base; do
        [[ -d $base/$theme ]] || continue
        hit=$(find -L "$base/$theme" -name "$name.svg" -print -quit 2>/dev/null)
        [[ -n $hit ]] && { printf '%s' "$hit"; return 0; }
    done < <(icon_bases)

    while read -r base; do
        [[ -d $base/$theme ]] || continue
        hit=$(find -L "$base/$theme" -name "$name.png" 2>/dev/null |
              sed -E 's#.*/([0-9]+)x[0-9]+/.*#\1 &#; t; s#^#0 #' |
              sort -rn | head -1 | cut -d" " -f2-)
        [[ -n $hit ]] && { printf '%s' "$hit"; return 0; }
    done < <(icon_bases)
    return 1
}

# THE CHAIN ENDS AT ADWAITA, NOT AT HICOLOR, which the spec would have it do.
# hicolor is the fallback every theme inherits and it is nearly empty - it
# holds what applications drop into it, not a device set - so a theme without
# a drive icon reached the end of the chain and produced nothing at all. Both
# other themes installed here, oxygen and Bluecurve, are cursor-only
# directories with no device icons and no index.theme, and under the strict
# order they lost the icon entirely rather than borrowing a reasonable one.
# Adwaita is the default theme on this platform and the one theme.sh itself
# falls back to, so ending there matches what the rest of the desktop does.
icon_path() {
    local name=$1 theme t hit
    theme=$(current_icon_theme)
    for t in "$theme" $(theme_parents "$theme") hicolor Adwaita; do
        [[ -z $t ]] && continue
        hit=$(icon_in_theme "$t" "$name") && { printf '%s' "$hit"; return 0; }
    done
    # Outside any theme, and the last place the spec says to look.
    [[ -f /usr/share/pixmaps/$name.svg ]] && { printf '/usr/share/pixmaps/%s.svg' "$name"; return 0; }
    [[ -f /usr/share/pixmaps/$name.png ]] && { printf '/usr/share/pixmaps/%s.png' "$name"; return 0; }
    return 1
}

refresh_icons() {
    local now; now=$(current_icon_theme)
    [[ $now == "$ICON_THEME" ]] && return
    ICON_THEME=$now
    ICON_STORAGE=$(icon_path drive-removable-media || true)
    ICON_DEVICE=$(icon_path media-flash || true)
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

    refresh_icons

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
