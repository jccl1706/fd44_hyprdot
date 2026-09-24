#!/usr/bin/env bash
# =========================================================================
# usb-notify.sh - say something when a USB device is plugged in or pulled out
# =========================================================================
#
# Usage:  bin/usb-notify.sh watch            follow udev and notify (the unit)
#         bin/usb-notify.sh test < file      feed it a recorded event stream
#         bin/usb-notify.sh probe <devpath>  just the what-is-it lookup
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
        # Nothing readable. The numeric id is at least enough to look up, so
        # it is used when there is one - but only then: a REMOVE event has no
        # ID_* properties at all, and printing the placeholders unconditionally
        # produced "USB device ????:????", which tells nobody anything.
        # Returning empty lets the caller say something true instead.
        [[ -n ${ID_VENDOR_ID-} && -n ${ID_MODEL_ID-} ]] \
            && printf 'USB device %s:%s' "$ID_VENDOR_ID" "$ID_MODEL_ID"
        return
    fi
    if [[ -z $vendor || $model == *"$vendor"* ]]; then
        printf '%s' "${model:-$vendor}"
    else
        printf '%s %s' "$vendor" "$model"
    fi
}

# -------------------------------------------------------------------------
# What the thing actually is
# -------------------------------------------------------------------------
# ASK SYSFS, NOT THE USB CLASS CODE. The obvious route is bInterfaceClass -
# 08 mass storage, 02 network, 01 audio, 03 HID - and it does not work. The
# Realtek 2.5G adapter that prompted this reports class ff, vendor-specific,
# and its driver binds on the vendor id; a class-code lookup calls it
# "unknown" and draws the generic icon, which is the thing being fixed. What
# it DOES do is create a net/ directory under its interface, and so does
# every other network adapter whatever class it claims. The same is true of
# block/ for storage, sound/ for audio and input/ for keyboards and mice.
# Asking what the kernel built is asking what the device turned out to be
# rather than what it said it was.
#
# NONE OF IT IS THERE YET when the usb_device event arrives: the kernel
# binds the driver and creates those directories a moment later. Hence the
# poll. A second and a half is generous for any of them and short enough
# that a device which never grows one - a hub, a dock, an expansion card -
# is announced generically without a noticeable wait.
#
# Prints "<kind> <detail>", where the detail is whatever is worth saying
# about that kind: the block device for storage, the interface name for a
# network adapter, nothing much for the rest.
probe_kind() {
    local sysfs="/sys${1#/sys}" i d

    [[ -d $sysfs ]] || return 1

    for ((i = 0; i < 15; i++)); do
        # THE DISK, NOT ITS PARTITIONS. A stick's block device sits at
        # <usb>/…:1.0/hostN/targetN/N:N:N:N/block/sdX - six levels down - and
        # sdX1 sits one further inside it, which "*/block/*" matches just as
        # well. Excluding anything deeper keeps this on the whole device,
        # which is what lsblk wants to be asked about anyway.
        d=$(find "$sysfs" -maxdepth 7 -path '*/block/*' -not -path '*/block/*/*' \
                 -printf '%f\n' -quit 2>/dev/null)
        [[ -n $d ]] && { printf 'storage %s' "$d"; return 0; }

        d=$(find "$sysfs" -maxdepth 7 -path '*/net/*' -not -path '*/net/*/*' \
                 -printf '%f\n' -quit 2>/dev/null)
        [[ -n $d ]] && { printf 'network %s' "$d"; return 0; }

        d=$(find "$sysfs" -maxdepth 7 -path '*/sound/card*' \
                 -printf '%f\n' -quit 2>/dev/null)
        [[ -n $d ]] && { printf 'audio %s' "$d"; return 0; }

        d=$(find "$sysfs" -maxdepth 8 -path '*/input/input[0-9]*' \
                 -printf '%f\n' -quit 2>/dev/null)
        [[ -n $d ]] && { printf '%s %s' "$(hid_kind "$sysfs")" "$d"; return 0; }

        sleep 0.1
    done
    return 1
}

# Keyboard or mouse, from the HID boot protocol on the interface: 1 is a
# keyboard, 2 is a mouse. A device with neither - a tablet, a gamepad, a
# fingerprint reader - is just "input", which has no icon of its own here and
# falls back to the generic one rather than being drawn as a keyboard it is
# not.
hid_kind() {
    local f p
    for f in "$1"/*/bInterfaceProtocol; do
        [[ -f $f ]] || continue
        p=$(<"$f")
        [[ $p == 01 ]] && { printf 'keyboard'; return; }
        [[ $p == 02 ]] && { printf 'mouse'; return; }
    done
    printf 'input'
}

# A stick's size is the one extra fact worth the trouble: it is how you tell
# which stick you just plugged in when they are all black and unlabelled.
# lsblk reads the partition table, so a stick reports the size of the whole
# device and its label if it has one.
storage_detail() {
    local dev=$1 size label
    size=$(lsblk -ndo SIZE "/dev/$dev" 2>/dev/null | tr -d ' ')
    label=$(lsblk -no LABEL "/dev/$dev" 2>/dev/null | grep -m1 . || true)
    printf '/dev/%s' "$dev"
    [[ -n $size  ]] && printf ' · %s' "$size"
    [[ -n $label ]] && printf ' · %s' "$label"
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
declare -A ICON=()


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

# ONE ICON PER KIND. A network adapter announced with a flash-card picture
# is the sort of wrong that is worse than no picture at all - it says
# something specific and untrue. The names are the freedesktop ones the theme
# is expected to carry; anything it does not have resolves to empty through
# icon_path and the toast falls back to its dot.
#
# network-wired has no scalable svg in Adwaita, only a 48x48 png in
# AdwaitaLegacy, which icon_path finds on its second pass - drawn into a 28px
# box that is fine. Worth knowing before assuming every name here is an svg.
refresh_icons() {
    local now; now=$(current_icon_theme)
    [[ $now == "$ICON_THEME" ]] && return
    ICON_THEME=$now
    ICON[storage]=$(icon_path drive-removable-media || true)
    ICON[network]=$(icon_path network-wired        || true)
    ICON[audio]=$(icon_path audio-headset          || true)
    ICON[keyboard]=$(icon_path input-keyboard      || true)
    ICON[mouse]=$(icon_path input-mouse            || true)
    ICON[device]=$(icon_path media-removable       || true)
}

# What each kind is called in the notification.
kind_noun() {
    case $1 in
        storage)  printf 'USB storage' ;;
        network)  printf 'USB network adapter' ;;
        audio)    printf 'USB audio device' ;;
        keyboard) printf 'USB keyboard' ;;
        mouse)    printf 'USB mouse' ;;
        *)        printf 'USB device' ;;
    esac
}

# Falls back to no icon at all rather than to a name, because a name is the
# thing that draws wrong. With -i omitted the toast draws its own accent dot,
# which at least looks deliberate.
notify() {
    local icon=${3-}
    if [[ -n $icon ]]; then
        notify-send -a "USB" -i "$icon" "$1" "$2" 2>/dev/null && return
    else
        notify-send -a "USB" "$1" "$2" 2>/dev/null && return
    fi
    printf 'usb-notify: %s - %s\n' "$1" "$2" >&2
}

# WHAT WAS PLUGGED INTO EACH PORT, remembered from the add event and read
# back on the remove.
#
# A REMOVE EVENT CARRIES ALMOST NOTHING. udev has already torn the device
# down by the time it is announced, so the ID_VENDOR and ID_MODEL properties
# every name here comes from are simply absent - unplugging a stick that had
# been announced as "SanDisk Ultra" produced "USB device ????:????" on the
# way out. The sysfs path is the one thing both events agree on, so it is the
# key.
#
# The kind is remembered too, not just the name, so that a stick shows the
# same icon and the same wording going out as coming in. It was the icon
# that gave this away: connecting drew the drive and disconnecting drew the
# card, because the remove branch had no way to know which it had been.
declare -A SEEN_NAME=()
declare -A SEEN_KIND=()

announce() {
    [[ ${DEVTYPE-} == usb_device ]]  || return 0
    [[ ${ID_VENDOR_ID-} == 1d6b ]]   && return 0   # root hub, see above

    refresh_icons

    local path=${DEVPATH-} name kind detail probe
    name=$(device_name)

    case "${ACTION-}" in
        add)
            kind=device; detail=""
            if probe=$(probe_kind "$path"); then
                kind=${probe%% *}
                detail=${probe#* }
            fi
            [[ $kind == storage && -n $detail ]] && detail=$(storage_detail "$detail")
            # The interface name on its own: after "USB network adapter
            # connected" there is nothing else it could be, and "· as enp…"
            # read as a stumble next to the middle dot.

            [[ $kind == audio || $kind == keyboard || $kind == mouse || $kind == input ]] \
                && detail=""

            notify "$(kind_noun "$kind") connected" \
                   "$name${detail:+ · $detail}" "${ICON[$kind]-${ICON[device]}}"

            [[ -n $path ]] && { SEEN_NAME[$path]=$name; SEEN_KIND[$path]=$kind; }
            ;;
        remove)
            kind=${SEEN_KIND[$path]-device}
            [[ -z $name ]] && name=${SEEN_NAME[$path]-}
            # Still nothing - the device was already plugged in when this
            # service started, so there was no add event to learn from. The
            # port it was in is at least true.
            [[ -z $name ]] && name="on port ${path##*/}"

            notify "$(kind_noun "$kind") removed" "$name" "${ICON[$kind]-${ICON[device]}}"
            unset "SEEN_NAME[$path]" "SEEN_KIND[$path]"
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
    probe) probe_kind "${2:?usage: $0 probe <devpath>}" || echo "nothing under it says what it is" ;;
    *) echo "usage: $0 {watch|test|probe <devpath>}" >&2; exit 2 ;;
esac
