#!/usr/bin/env bash
# =========================================================================
# evo4-gain.sh - open the EVO4's own output, which comes up shut
# =========================================================================
#
# Usage:  bin/evo4-gain.sh          set it, if an EVO4 is attached
#         bin/evo4-gain.sh --show   print what it is now
#
# THE FAULT THIS EXISTS FOR. The Audient EVO4 has a hardware playback volume
# of its own - ALSA numid=4, 'EVO4  Playback Volume' - and it comes up at 0,
# which is -127 dB, which is silence. PipeWire will happily show 95% and route
# streams into it; `wpctl status` looks perfect; nothing comes out. On
# 2026-09-25 that was a desktop with no sound at all after every boot, and the
# thing that made it hard to see is that every software-side indicator was
# healthy.
#
# WHY NOTHING ELSE SETS IT.
#   - wireplumber/wireplumber.conf.d/51-evo4-soft-mixer.conf tells WirePlumber
#     to keep volume in software and leave this control alone, because driving
#     it writes to the interface hundreds of times a second and the EVO4 cuts
#     out while that is happening. That fix is right and stays.
#   - ALSA's own save/restore would carry the value across a reboot, but this
#     machine has no alsa-store/alsa-restore units and no
#     /var/lib/alsa/asound.state - NixOS stopped shipping them with the old
#     `sound.enable` option.
#
# So the control is written once, here, by something that runs after the card
# is there.
#
# ALL FOUR CHANNELS, THROUGH THE SIMPLE CONTROL. `cset numid=4 254,254,254,254`
# sets the front pair and silently leaves the rear pair at 0 - measured, twice.
# `sset` writes every channel, and the EVO4's profile is "Headphone / Line
# Out", so the rear pair is the other socket: set only the front pair and
# headphones stay silent.
#
# HARMLESS WITHOUT AN EVO4. Every machine in this repository reads the same
# autostart; a laptop with no such card exits 0 having done nothing.

set -euo pipefail

CARD=EVO4
CONTROL='EVO4 '   # the trailing space is the control's actual name

have_card() { [[ -d /proc/asound/$CARD ]]; }

if [[ ${1-} == --show ]]; then
    have_card || { echo "no $CARD attached"; exit 0; }
    amixer -c "$CARD" sget "$CONTROL" 2>/dev/null | grep -E "Front|Rear"
    exit 0
fi

have_card || exit 0
command -v amixer >/dev/null 2>&1 || { echo "evo4-gain: alsa-utils not installed" >&2; exit 0; }

# Idempotent: if it is already open, say nothing and change nothing. This runs
# on every login and on every replug, and a write to this control is exactly
# what the soft-mixer config exists to avoid doing often.
if amixer -c "$CARD" sget "$CONTROL" 2>/dev/null | grep -q "\[0%\]"; then
    amixer -c "$CARD" sset "$CONTROL" 100% >/dev/null 2>&1 ||
        { echo "evo4-gain: could not set $CONTROL on $CARD" >&2; exit 1; }
    echo "evo4-gain: opened $CARD's output (was at 0, which is silence)"
fi
