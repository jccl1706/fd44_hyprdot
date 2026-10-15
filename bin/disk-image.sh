#!/usr/bin/env bash
# =========================================================================
# disk-image.sh - a byte-exact copy of a whole disk, and a way back
# =========================================================================
#
# Usage:  bin/disk-image.sh measure <serial>            how big the image will be
#         bin/disk-image.sh image   <serial> <outdir>   write it
#         bin/disk-image.sh verify  <serial> <outdir>   compare it against the disk
#         bin/disk-image.sh restore <serial> <outdir>   put it back (asks twice)
#         bin/disk-image.sh wipe    <serial> <outdir>   discard it, once imaged
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
# ASK lsblk, NOT /sys/block/*/device/serial. That file is the serial of the
# CONTROLLER, which for an NVMe is the drive and for a USB enclosure is the
# bridge chip. Measured on the enclosure this was written for: the Sabrent
# reports 0546071110F388396596 through lsblk and 0000000000000000 through
# sysfs - a value cheap bridges share with each other, so matching on it could
# find a disk that is not the one asked for. lsblk reads VPD page 0x80, which
# is the drive answering for itself.
#
# AMBIGUITY IS A REFUSAL, not a first match. Two disks answering to one serial
# means the question has no answer, and this script's whole job is to be sure
# which disk it is pointed at.
find_disk() {
    local want="$1" name serial
    local -a matches=()
    [[ -n "$want" ]] || return 1
    while read -r name serial; do
        [[ "$serial" == "$want" ]] && matches+=("/dev/$name")
    done < <(lsblk -dno NAME,SERIAL 2>/dev/null)
    case ${#matches[@]} in
        1) printf '%s\n' "${matches[0]}"; return 0 ;;
        0) return 1 ;;
        *) printf '%s: more than one disk answers to serial %s: %s\n' \
                  "$name" "$want" "${matches[*]}" >&2; return 2 ;;
    esac
}

require_disk() {
    local serial="$1" disk
    disk="$(find_disk "$serial")" || die "no disk with serial $serial is attached"
    # Printed every time: the one line that proves this is pointed at the disk
    # you meant, in a script whose other modes erase things.
    printf '  %s  %s\n' "$disk" \
           "$(lsblk -dno MODEL,SIZE "$disk" 2>/dev/null | tr -s ' ')" >&2
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
        # skip AND count ARE BOTH IN BYTES because of the iflags, and both are
        # passed as bytes. Getting this wrong is quiet: count=1 under
        # count_bytes reads a single byte and dd reports no error, so the
        # sample comes back 400 bytes long, entirely zeros because they all
        # came from the start of the disk, and the estimate that follows is
        # arithmetic on nothing.
        dd if="$disk" bs="$chunk" skip="$off" count="$chunk" \
           iflag=skip_bytes,count_bytes status=none 2>/dev/null >> "$tmp" || true
    done
    raw=$(stat -c%s "$tmp")
    # A SHORT SAMPLE IS A FAILED SAMPLE. The point of this mode is to be
    # trusted about how much disk to set aside, so it says nothing rather than
    # extrapolating from whatever happened to be read.
    local want=$(( samples * chunk ))
    if (( raw < want / 2 )); then
        die "only read $(human "$raw") of an intended $(human "$want") - the sample is not usable"
    fi
    comp=$(zstd -3 -c "$tmp" 2>/dev/null | wc -c)
    zeros=$(tr -d '\000' < "$tmp" | wc -c)
    local zero_pct=$(( 100 - (zeros * 100 / (raw > 0 ? raw : 1)) ))

    printf '\n'
    printf '  sampled          %s across the whole disk\n' "$(human "$raw")"
    printf '  of that, zeros   %s%%\n' "$zero_pct"
    printf '  compresses to    %s%% of its size\n' "$(( comp * 100 / (raw > 0 ? raw : 1) ))"
    printf '\n'
    local ratio=$(( comp * 100 / (raw > 0 ? raw : 1) ))
    local est=$(( size / 100 * ratio ))

    # A SAMPLE OF AN ALMOST-EMPTY DISK FINDS NOTHING, AND NOTHING EXTRAPOLATES
    # TO ZERO. 400 points on a 932 GiB drive holding 4 GiB of data have about
    # a one in six chance of landing on any of it, so "every byte was zero" is
    # the expected result rather than a surprising one - and multiplying it out
    # says the image will be 0 B, which is both false and the kind of false
    # that gets believed because a program printed it.
    #
    # What the sample can honestly say is that the drive is overwhelmingly
    # unwritten. The floor is whatever is actually stored, which cannot be seen
    # from out here: it is behind the LUKS header, and opening that needs a
    # passphrase this script has no business holding.
    if (( zero_pct >= 99 )); then
        say "the drive is essentially all zeros - no written data in the sample"
        printf '  The image will be small: close to the size of what is actually\n'
        printf '  stored, which cannot be measured from outside the LUKS header.\n'
        printf '  A filesystem holding a few GB images to a few GB.\n'
    else
        say "estimated image size: about $(human "$est")"
        printf '  Allow room: the estimate is a sample, not a promise.\n'
    fi
    printf '\n  Reading takes the same time either way - every block is read.\n'
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
    # SPLIT ON PURPOSE. Under `set -u`, every word of a `local` is expanded
    # before the builtin assigns any of them, so `local a="$1" b="$a/x"` dies
    # on an unbound `a` - measured on bash 5.3.9. image() happened to declare
    # its parts separately and worked; verify() and restore() wrote it on one
    # line and did not.
    local serial="$1" outdir="$2"
    local base="$outdir/$serial"
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
    local serial="$1" outdir="$2" disk typed
    local base="$outdir/$serial"
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

# --- wipe -----------------------------------------------------------------
wipe() {
    local serial="$1" outdir="$2" disk typed
    local base="$outdir/$serial"
    local discarded=0

    # THE IMAGE IS THE PRECONDITION. This is the one command here that destroys
    # something with no way back, so it refuses to run unless the copy it is
    # making redundant is present and carries the checksum that was taken off
    # the disk. It does not re-verify - that takes twenty minutes and was done
    # when the image was made - but a missing or unrecorded image means the
    # answer to "is this safe" is unknown, and unknown is a no.
    [[ -f "$base.img.zst" ]] || die "no image at $base.img.zst - nothing to fall back on"
    [[ -f "$base.source.sha256" ]] || die "no recorded checksum beside the image"
    [[ -f "$base.sfdisk" ]] || die "no partition table saved beside the image"

    disk="$(require_disk "$serial")"

    printf '\n'
    warn "This DISCARDS EVERY BLOCK on $disk. There is no undo."
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL "$disk" >&2
    printf '\n  falling back on:\n'
    printf '    %s  (%s)\n' "$base.img.zst" "$(human "$(stat -c%s "$base.img.zst")")"
    printf '    %s\n' "$base.sda2.luks-header"
    printf '\n  Type the serial of the disk to confirm: '
    read -r typed
    [[ "$typed" == "$serial" ]] || die "that is not the serial - nothing was touched"

    say "discarding every block"
    # -f IS REQUIRED WHENEVER THE DISK STILL HAS A PARTITION TABLE. Without it
    # blkdiscard refuses - "contains existing partition (gpt)" - which is a
    # safety interlock and not a hardware limitation. This script read any
    # non-zero exit as "the enclosure does not pass TRIM through" and said so,
    # which was a confident diagnosis of the wrong thing: the enclosure was
    # fine, the flag was missing, and the blocks were never discarded.
    local err
    err="$(blkdiscard -f "$disk" 2>&1)" && discarded=1 || discarded=0
    if (( ! discarded )); then
        printf '%s\n' "$err" >&2
        case "$err" in
            *"not supported"*|*"Operation not supported"*|*"ioctl"*)
                warn "this enclosure does not pass TRIM through" ;;
            *)  warn "blkdiscard failed for the reason above" ;;
        esac
        warn "erasing the headers instead, which is what puts the data out of reach"
        wipefs --all --force "$disk" >/dev/null
        dd if=/dev/zero of="$disk" bs=1M count=16 status=none
        local end=$(( $(blockdev --getsize64 "$disk") / 1048576 - 16 ))
        dd if=/dev/zero of="$disk" bs=1M count=16 seek="$end" status=none
    fi
    sync
    partprobe "$disk" 2>/dev/null || true

    if (( discarded )); then
        say "done - every block on $disk discarded"
    else
        say "done - headers erased on $disk, blocks NOT discarded"
        printf '  The data is unreachable: the LUKS master key lived in that\n'
        printf '  header and is gone. But the ciphertext is still on the flash,\n'
        printf '  and the drive has not been returned to a clean write state.\n'
    fi
    lsblk -o NAME,SIZE,TYPE,FSTYPE "$disk" >&2
    printf '\n  first 4 KiB reads: '
    if dd if="$disk" bs=4096 count=1 status=none | tr -d '\000' | head -c1 | grep -q .; then
        printf 'NOT zeros\n'
    else
        printf 'all zeros\n'
    fi
}

case "${1:-}" in
    measure) [[ $# -eq 2 ]] || die "usage: $name measure <serial>"; measure "$2" ;;
    image)   [[ $# -eq 3 ]] || die "usage: $name image <serial> <outdir>"; image "$2" "$3" ;;
    verify)  [[ $# -eq 3 ]] || die "usage: $name verify <serial> <outdir>"; verify "$2" "$3" ;;
    restore) [[ $# -eq 3 ]] || die "usage: $name restore <serial> <outdir>"; restore "$2" "$3" ;;
    wipe)    [[ $# -eq 3 ]] || die "usage: $name wipe <serial> <outdir>"; wipe "$2" "$3" ;;
    *) die "usage: $name [measure|image|verify|restore|wipe] - see the header" ;;
esac
