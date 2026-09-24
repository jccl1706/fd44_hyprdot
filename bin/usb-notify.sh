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

    # Nothing in sysfs says what it is. Some devices never grow a class
    # directory because the kernel has no driver to bind - or because the
    # thing they do is not something the kernel drives at all.
    kind_from_class "$sysfs"
}

# THE USB CLASS, as a fallback and not as the first question - see the note
# above probe_kind for why that order matters. It answers the cases sysfs
# cannot, and BILLBOARD is the one that prompted it.
#
# A USB-C video adapter reports interface class 0x11, "Billboard": the class
# exists precisely to announce that the port has gone into an alternate mode.
# The video itself never touches USB - it is DisplayPort over the same cable
# - so the adapter creates no drm device, no class directory, nothing the
# scan above can see, and a Framework HDMI expansion card was announced as a
# nameless "USB device connected". Measured on this one: interface :1.0 is
# class 11, interface :1.1 is HID with no input device behind it.
#
# It is not a Framework quirk. Billboard is what any USB-C alt-mode adapter
# is supposed to present, so this recognises the class rather than the
# vendor id.
kind_from_class() {
    local sysfs=$1 f c
    for f in "$sysfs"/*/bInterfaceClass; do
        [[ -f $f ]] || continue
        c=$(<"$f")
        case $c in
            11) printf 'display'; return 0 ;;   # USB-C alt mode adapter
            0e) printf 'video';   return 0 ;;   # UVC camera
            07) printf 'printer'; return 0 ;;
        esac
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
# NO ICON IS SENT. The shell draws every notification with a coloured dot
# rather than a picture (quickshell/NotificationToast.qml), so an icon name
# here would be read by nobody.
#
# There used to be a table of them, one per kind, and before that ninety
# lines that searched the icon theme on disk. Both are gone. What stays is
# kind_noun below - with no picture, the WORDS are the only thing saying what
# was plugged in, which makes them worth more than they were.
#
# Put -i back with a freedesktop name if the toast ever draws icons again:
# drive-removable-media, network-wired, audio-headset, input-keyboard,
# input-mouse, video-display, camera-web, printer, media-removable. They
# resolve because bin/icon-bridge.sh puts the selected theme where
# quickshell's Qt can see it.

# What each kind is called in the notification.
kind_noun() {
    case $1 in
        storage)  printf 'USB storage' ;;
        network)  printf 'USB network adapter' ;;
        display)  printf 'USB display adapter' ;;
        video)    printf 'USB camera' ;;
        printer)  printf 'USB printer' ;;
        audio)    printf 'USB audio device' ;;
        keyboard) printf 'USB keyboard' ;;
        mouse)    printf 'USB mouse' ;;
        *)        printf 'USB device' ;;
    esac
}

# -a groups these under one application in the panel's history.
# -a groups these under one application in the panel's history.
notify() {
    notify-send -a "USB" "$1" "$2" 2>/dev/null \
        || printf 'usb-notify: %s - %s\n' "$1" "$2" >&2
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
# same icon and the same wording going out as coming in.
#
# DECLARED, and that is not decoration: without `declare -A` bash treats
# SEEN_NAME[$path] as an ARITHMETIC subscript and a sysfs path is not
# arithmetic. It fails with "operand expected" on the first device plugged
# in, and under `set -u` that ends the watcher.
declare -A SEEN_NAME=()
declare -A SEEN_KIND=()

announce() {
    [[ ${DEVTYPE-} == usb_device ]]  || return 0
    [[ ${ID_VENDOR_ID-} == 1d6b ]]   && return 0   # root hub, see above

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

            # Only storage and network have anything to add; for the rest
            # the detail is the sysfs node that identified them, which means
            # nothing to anyone reading a notification.
            [[ $kind == storage || $kind == network ]] || detail=""

            notify "$(kind_noun "$kind") connected" \
                   "$name${detail:+ · $detail}"

            [[ -n $path ]] && { SEEN_NAME[$path]=$name; SEEN_KIND[$path]=$kind; }
            ;;
        remove)
            kind=${SEEN_KIND[$path]-device}
            [[ -z $name ]] && name=${SEEN_NAME[$path]-}
            # Still nothing - the device was already plugged in when this
            # service started, so there was no add event to learn from. The
            # port it was in is at least true.
            [[ -z $name ]] && name="on port ${path##*/}"

            notify "$(kind_noun "$kind") removed" "$name"
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

    # THE WATCH IS NOT SUPPOSED TO END, so ending is a failure and has to be
    # reported as one. `udevadm monitor` exiting closes the pipeline, the loop
    # sees EOF and the script falls off the end with status 0 - and
    # Restart=on-failure does nothing with a clean exit, so the unit sits
    # "inactive (dead)" and nothing reacts to anything ever again.
    #
    # Not hypothetical: on 2026-09-23 a stray `pkill -f 'udevadm monitor'`
    # meant for a throwaway process took power-mode.service's with it. The
    # unit exited 0 at 20:48 and was still dead thirteen hours later - no
    # governor switching, no brightness changes, and nothing anywhere saying
    # so. Found by a sweep rather than by noticing.
        echo "usb-notify: udevadm monitor ended" >&2
        exit 1
        ;;
    test) pump ;;
    # The storage lookup on its own, against a DEVPATH that already exists:
    #   bin/usb-notify.sh probe /devices/pci0000:00/.../usb3/3-2
    # It is the one part that cannot be exercised from a recorded stream,
    # because it goes and reads sysfs rather than the event.
    probe) probe_kind "${2:?usage: $0 probe <devpath>}" || echo "nothing under it says what it is" ;;
    *) echo "usage: $0 {watch|test|probe <devpath>}" >&2; exit 2 ;;
esac
