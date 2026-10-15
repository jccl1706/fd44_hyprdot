#!/usr/bin/env bash
# =========================================================================
# disk-image.sh - a byte-exact copy of a whole disk, and a way back
# =========================================================================
#
# Usage:  bin/disk-image.sh measure <serial>            how big the image will be
#         bin/disk-image.sh image   <serial> <outdir>   write it
#         bin/disk-image.sh verify  <serial> <outdir>   compare it against the disk
#         bin/disk-image.sh restore <serial> <outdir>   put it back (asks twice)
#
# Run it as root, on the machine the disk is PLUGGED INTO, not the machine it
# came out of.
#
# IT FINDS THE DISK BY SERIAL, NEVER BY /dev/nvmeXn1. Device names are assigned
# in probe order and are not stable: on the desktop this was written for, the
# two NVMe drives swapped names between two boots of the same machine. An
# earlier script in this repository hardcoded /dev/nvme0n1, which would have
# detached the wrong disk, and was deleted rather than fixed. A serial is
# printed on the drive and cannot change under you.
#
# THE SOURCE IS OPENED READ-ONLY and this never writes to it except in
# `restore`, which asks for the serial to be typed back before it does.
#
# WHY COMPRESSED, AND WHY `measure` COMES FIRST. A LUKS disk is ciphertext,
# which does not compress at all - but the parts never written to are whatever
# the SSD returns for an unwritten block, usually zeros, and those compress to
# nothing. So the image of a 931 GB disk holding 4 GB can be anything between
# 5 GB and 931 GB depending on what the drive has been used for in its life,
# and the only way to know is to look. `measure` samples the raw device and
# tells you before you commit the space.
#
# THE HEADER AND THE PARTITION TABLE ARE SAVED SEPARATELY TOO. They are a few
# megabytes, they are what makes the image mountable rather than merely stored,
# and a LUKS header that has been overwritten cannot be reconstructed from
# anything else - the data behind it is then permanently gone.

set -euo pipefail

name="${0##*/}"
die()  { printf '%s: %s\n' "$name" "$*" >&2; exit 1; }
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

[[ $EUID -eq 0 ]] || die "run this as root (it reads a raw device)"

# --- the tools, checked before anything is read ---------------------------
#
# CRYPTSETUP IS NOT OPTIONAL even though it is only used for a few seconds.
# Without it the LUKS header backup is skipped, and it would be skipped
# QUIETLY: `if cryptsetup isLuks ...` on a machine with no cryptsetup is a
# command that fails, which reads as "not a LUKS partition" and moves on. The
# image would be written, verified, and reported good, and the one file that
# cannot be reconstructed from anything else would simply not be in it. Found
# on the desktop this is meant to run on, which has zstd but neither cryptsetup
# nor gdisk.
need=()
for t in dd zstd sfdisk cryptsetup lsblk sha256sum blockdev; do
    command -v "$t" >/dev/null 2>&1 || need+=("$t")
done
if (( ${#need[@]} )); then
    printf '%s: missing: %s\n' "$name" "${need[*]}" >&2
    printf '  on Fedora:  sudo dnf install cryptsetup gdisk zstd util-linux coreutils\n' >&2
    exit 1
fi
# sgdisk is the only genuinely optional one: it writes a second copy of the
# partition table in GPT's own format, and sfdisk has already written one.
command -v sgdisk >/dev/null 2>&1 || warn_no_sgdisk=1

# --- find the disk --------------------------------------------------------
find_disk() {
    local want="$1" dev serial
    for dev in /sys/block/*; do
        [[ -r "$dev/device/serial" ]] || continue
        serial="$(tr -d ' \n' < "$dev/device/serial" 2>/dev/null || true)"
        if [[ "$serial" == "$want" ]]; then
            printf '/dev/%s\n' "${dev##*/}"
            return 0
        fi
    done
    return 1
}

require_disk() {
    local serial="$1" disk
    disk="$(find_disk "$serial")" || die "no disk with serial $serial is attached"
    # REFUSE A MOUNTED DISK. An image of a filesystem that is being written to
    # is an image of a filesystem caught mid-sentence.
    if lsblk -nro MOUNTPOINT "$disk" | grep -q .; then
        lsblk -o NAME,SIZE,MOUNTPOINT "$disk" >&2
        die "$disk has something mounted - unmount it first, this must be offline"
    fi
    printf '%s\n' "$disk"
}

human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }

# --- measure --------------------------------------------------------------
measure() {
    local serial="$1" disk size samples=400 chunk=$((1024*1024))
    disk="$(require_disk "$serial")"
    size=$(blockdev --getsize64 "$disk")
    say "$disk - $(human "$size") - sampling $samples points"

    local i off zeros=0 raw=0 comp=0 tmp
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
    for ((i = 0; i < samples; i++)); do
        off=$(( i * (size / samples) ))
        dd if="$disk" bs="$chunk" count=1 skip=$((off / chunk)) \
           iflag=skip_bytes,count_bytes status=none 2>/dev/null >> "$tmp" || true
    done
    raw=$(stat -c%s "$tmp")
    comp=$(zstd -3 -c "$tmp" 2>/dev/null | wc -c)
    zeros=$(tr -d '\000' < "$tmp" | wc -c)
    local zero_pct=$(( 100 - (zeros * 100 / (raw > 0 ? raw : 1)) ))

    printf '\n'
    printf '  sampled          %s across the whole disk\n' "$(human "$raw")"
    printf '  of that, zeros   %s%%\n' "$zero_pct"
    printf '  compresses to    %s%% of its size\n' "$(( comp * 100 / (raw > 0 ? raw : 1) ))"
    printf '\n'
    local est=$(( size / 100 * (comp * 100 / (raw > 0 ? raw : 1)) ))
    say "estimated image size: about $(human "$est")"
    printf '  Reading still takes as long either way - every block is read.\n'
    printf '  Allow room: the estimate is a sample, not a promise.\n'
}

# --- image ----------------------------------------------------------------
image() {
    local serial="$1" outdir="$2" disk size
    disk="$(require_disk "$serial")"
    size=$(blockdev --getsize64 "$disk")
    mkdir -p "$outdir"

    local base="$outdir/$serial"
    [[ -e "$base.img.zst" ]] && die "$base.img.zst exists already - move it aside"

    # The small, precious things first: they take seconds and they are what
    # makes the big file useful.
    say "saving the partition table"
    sfdisk --dump "$disk" > "$base.sfdisk"
    if [[ -n "${warn_no_sgdisk:-}" ]]; then
        warn "no sgdisk - keeping only the sfdisk dump of the partition table"
    else
        sgdisk --backup="$base.gpt" "$disk" >/dev/null 2>&1 || true
    fi

    say "saving any LUKS headers"
    local part found_luks=0
    for part in "$disk"p* "$disk"[0-9]*; do
        [[ -b "$part" ]] || continue
        if cryptsetup isLuks "$part" 2>/dev/null; then
            cryptsetup luksHeaderBackup "$part" \
                --header-backup-file "$base.$(basename "$part").luks-header" \
                || die "could not back up the LUKS header on $part"
            say "  header from $part"
            found_luks=1
        fi
    done
    # SAID OUT LOUD EITHER WAY. A disk with no LUKS on it is perfectly normal;
    # a disk that HAS LUKS and whose header was not saved is a disaster that
    # only shows up years later, so the run should never be ambiguous about
    # which of the two happened.
    (( found_luks )) || warn "no LUKS partitions found on $disk - nothing to back up"

    say "writing the image - $(human "$size") to read"
    printf '  source  %s\n  target  %s.img.zst\n\n' "$disk" "$base"
    # tee to sha256sum so the source hash costs nothing extra: the bytes are
    # already passing through. Without this, verifying means reading the disk
    # a second time.
    dd if="$disk" bs=16M status=progress iflag=direct 2>/dev/null \
      | tee >(sha256sum | cut -d' ' -f1 > "$base.source.sha256") \
      | zstd -3 --long=27 -T0 -q -o "$base.img.zst"

    sync
    say "done"
    printf '  image      %s\n' "$(human "$(stat -c%s "$base.img.zst")")"
    printf '  source sha %s\n' "$(cat "$base.source.sha256")"
    printf '\n  Now run:  %s verify %s %s\n' "$name" "$serial" "$outdir"
}

# --- verify ---------------------------------------------------------------
verify() {
    local serial="$1" outdir="$2" base="$outdir/$serial"
    [[ -f "$base.img.zst" ]] || die "no image at $base.img.zst"
    [[ -f "$base.source.sha256" ]] || die "no recorded source checksum beside the image"

    say "checking the compressed file is intact"
    zstd -t "$base.img.zst" || die "the image itself is corrupt"

    say "decompressing and hashing - this reads the whole image"
    local got want
    got="$(zstd -dc --long=27 "$base.img.zst" | sha256sum | cut -d' ' -f1)"
    want="$(cat "$base.source.sha256")"
    printf '  recorded  %s\n  image     %s\n' "$want" "$got"
    [[ "$got" == "$want" ]] || die "THE IMAGE DOES NOT MATCH THE DISK IT CAME FROM"
    say "the image is a faithful copy of the disk"
}

# --- restore --------------------------------------------------------------
restore() {
    local serial="$1" outdir="$2" base="$outdir/$serial" disk typed
    [[ -f "$base.img.zst" ]] || die "no image at $base.img.zst"
    disk="$(require_disk "$serial")"

    warn "This ERASES $disk completely and writes the image over it."
    lsblk -o NAME,SIZE,MODEL,SERIAL "$disk" >&2
    printf 'Type the serial of the disk to confirm: '
    read -r typed
    [[ "$typed" == "$serial" ]] || die "that is not the serial - nothing was written"

    say "restoring"
    zstd -dc --long=27 "$base.img.zst" | dd of="$disk" bs=16M status=progress oflag=direct
    sync
    say "restored - the disk is byte-for-byte what it was"
}

case "${1:-}" in
    measure) [[ $# -eq 2 ]] || die "usage: $name measure <serial>"; measure "$2" ;;
    image)   [[ $# -eq 3 ]] || die "usage: $name image <serial> <outdir>"; image "$2" "$3" ;;
    verify)  [[ $# -eq 3 ]] || die "usage: $name verify <serial> <outdir>"; verify "$2" "$3" ;;
    restore) [[ $# -eq 3 ]] || die "usage: $name restore <serial> <outdir>"; restore "$2" "$3" ;;
    *) die "usage: $name [measure <serial>|image <serial> <dir>|verify <serial> <dir>|restore <serial> <dir>]" ;;
esac
