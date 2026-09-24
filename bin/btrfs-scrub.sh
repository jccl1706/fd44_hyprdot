#!/usr/bin/env bash
# =========================================================================
# btrfs-scrub.sh - read every block back and say whether it still checks out
# =========================================================================
#
# Usage:  sudo bin/btrfs-scrub.sh            scrub every mounted btrfs
#         sudo bin/btrfs-scrub.sh --dry-run  say what it would scrub
#
# Run monthly by btrfs-scrub.timer. Install both with:
#         sudo bin/btrfs-scrub-setup.sh
#
# WHAT A SCRUB IS FOR, and what it is not. btrfs stores a checksum for every
# block it writes; a scrub reads them all back and compares. On a single-device
# filesystem - which is every machine here - it can only REPORT a mismatch,
# because there is no second copy to repair from. That is still the whole
# point: a disk that has started to rot says so while the file you care about
# is still readable, rather than the first symptom being a file you cannot
# open. Metadata is DUP even on one device, so metadata damage genuinely is
# repaired.
#
# THIS IS NOT A BACKUP AND NOT A SNAPSHOT. btrfs-patrol takes the snapshots
# and rolls the system back; it lives on the same disk and dies with it. A
# scrub tells you that disk is going. Neither is a copy of your data
# somewhere else, which this repository still does not have.
#
# ONE SCRUB PER FILESYSTEM, NOT PER MOUNT. `/` and `/home` here are two
# subvolumes of one filesystem, so scrubbing both would read the same device
# twice for nothing. Mounts are therefore grouped by UUID and the first of
# each is scrubbed.
#
# NO ionice, DELIBERATELY. `btrfs scrub` takes -c and -n, and its own help
# says they need I/O scheduler support and do not work with mq-deadline. The
# scheduler on this laptop's NVMe is `none`, so they would be silently
# ignored; the unit asks for idle I/O and Nice=19 instead, which cost nothing
# where they are also ignored.
#
# EXIT 1 IF ANYTHING WAS WRONG, which is the whole reporting mechanism: the
# unit then shows in `systemctl --failed`, where a sweep of the machine will
# see it. A scrub that finds nothing says so in the journal and exits 0.

set -euo pipefail

DRY=0
[[ ${1-} == --dry-run ]] && DRY=1

if [[ $EUID -ne 0 ]]; then
    echo "btrfs-scrub: needs root - a scrub reads the raw device" >&2
    exit 2
fi

command -v btrfs >/dev/null 2>&1 || { echo "btrfs-scrub: btrfs-progs not installed" >&2; exit 2; }

# TARGET, UUID for every mounted btrfs, first mount of each filesystem only.
mapfile -t targets < <(
    findmnt -rno TARGET,FSTYPE,UUID 2>/dev/null |
    awk '$2 == "btrfs" && !seen[$3]++ { print $1 }'
)

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "btrfs-scrub: no mounted btrfs filesystem - nothing to do"
    exit 0
fi

rc=0
for mnt in "${targets[@]}"; do
    if [[ $DRY -eq 1 ]]; then
        echo "would scrub $mnt ($(findmnt -rno SOURCE "$mnt"))"
        continue
    fi

    # A scrub already running is not a failure: the previous one is still
    # doing the same work, and -f would only corrupt its statistics file.
    if btrfs scrub status "$mnt" 2>/dev/null | grep -qi "Status:.*running"; then
        echo "btrfs-scrub: a scrub is already running on $mnt - leaving it alone"
        continue
    fi

    echo "btrfs-scrub: scrubbing $mnt"
    # -B stays in the foreground, so the unit's lifetime is the scrub's and
    # systemd's own logging captures the result. -d reports per device.
    btrfs scrub start -B -d "$mnt" || rc=1

    # The summary above is human-readable; the counters are read back
    # separately because their names are stable and greppable.
    errs="$(btrfs scrub status -R "$mnt" 2>/dev/null |
            awk '/_errors:/ { gsub(/.*: */, "", $0); s += $NF } END { print s + 0 }')"
    if [[ ${errs:-0} -gt 0 ]]; then
        echo "btrfs-scrub: $mnt reported $errs error(s) - see 'btrfs scrub status -R $mnt'" >&2
        rc=1
    else
        echo "btrfs-scrub: $mnt clean"
    fi
done

exit $rc
