#!/usr/bin/env bash
# =========================================================================
# gentoo-stage3.sh - fetch, verify and unpack a stage3 into a mounted root
# =========================================================================
#
# Usage:  bin/gentoo-stage3.sh fetch  [root]   download and verify, do not unpack
#         bin/gentoo-stage3.sh unpack [root]   unpack what fetch verified
#         bin/gentoo-stage3.sh chroot [root]   bind-mount and enter
#
# root defaults to /mnt/gentoo. Run as root.
#
# THE SIGNATURE CHECK IS THE POINT, not ceremony. A stage3 is the entire
# userland of the machine you are about to build; a corrupted or substituted
# one is a system you cannot trust and will not notice. This verifies the
# .asc against Gentoo's release key and refuses to unpack anything that fails.
# `fetch` and `unpack` are separate so a failed verification cannot be
# followed by an unpack out of habit.
#
# --xattrs-include='*.*' AND --numeric-owner ARE NOT OPTIONAL. Without the
# first, file capabilities and SELinux labels are dropped and things like ping
# lose their capability bits. Without the second, tar maps ownership through
# the HOST's /etc/passwd - so the files land owned by whichever Fedora user
# happens to hold that uid. Both are silent; both produce a system that mostly
# works and is subtly wrong.
#
# VARIANT: openrc, deliberately. The default stage3 on the Gentoo mirrors is
# systemd now, and picking it by accident means discovering the init system
# you did not want several hours later.

set -euo pipefail

name="${0##*/}"
die()  { printf '%s: %s\n' "$name" "$*" >&2; exit 1; }
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

ARCH=amd64
VARIANT=openrc                       # NOT the mirror default, which is systemd
BASE="https://distfiles.gentoo.org/releases/${ARCH}/autobuilds"
KEYSERVER=hkps://keys.gentoo.org
KEYBUNDLE=https://qa-reports.gentoo.org/output/service-keys.gpg
RELEASE_KEY=BB572E0E2D182910
ROOT="${2:-/mnt/gentoo}"

[[ $EUID -eq 0 ]] || die "run as root"
for t in curl gpg tar findmnt; do command -v "$t" >/dev/null || die "missing: $t"; done

require_root_mounted() {
    findmnt -no TARGET "$ROOT" >/dev/null 2>&1 \
        || die "$ROOT is not a mount point - run gentoo-partition.sh mount first"
    [[ "$(findmnt -no FSTYPE "$ROOT")" == btrfs ]] \
        || die "$ROOT is not the btrfs this was meant for"
}

latest_url() {
    # THE POINTER FILE IS PGP CLEARSIGNED, which the obvious parse walks
    # straight into: skipping comments and blank lines and taking the first
    # line left returns "-----BEGIN PGP SIGNED MESSAGE-----", and the URL
    # built from it 404s. The payload is the one line that looks like a
    # timestamped path to a tarball, so match that shape instead of guessing
    # at a position.
    local pointer="${BASE}/latest-stage3-${ARCH}-${VARIANT}.txt" path
    path="$(curl -fsSL --max-time 60 "$pointer" \
            | grep -oE '^[0-9]{8}T[0-9]{6}Z/stage3-[^ ]+\.tar\.xz' | head -1)" \
        || die "could not read $pointer"
    [[ -n $path ]] || die "no stage3 path found in $pointer - has the format changed?"
    printf '%s/%s\n' "$BASE" "$path"
}

cmd_fetch() {
    require_root_mounted
    local url tarball dest
    url="$(latest_url)"
    tarball="$(basename "$url")"
    dest="$ROOT/$tarball"
    say "latest ${ARCH} ${VARIANT} stage3"
    printf '  %s\n' "$url"

    # Reuse a complete download rather than fetching 280 MB again, but always
    # re-verify: a tarball sitting on disk is not evidence of anything.
    if [[ -f $dest ]] && [[ "$(stat -c%s "$dest")" -gt 100000000 ]]; then
        say "a tarball is already here, reusing it ($(du -h "$dest" | cut -f1))"
    else
        say "downloading"
        curl -fL --progress-bar --max-time 1800 -o "$dest" "$url"
    fi
    curl -fL --silent --max-time 300 -o "$dest.asc" "$url.asc"

    # GPG NEEDS A HOME OF ITS OWN HERE. Run as root on a machine where nobody
    # has used gpg, ~/.gnupg does not exist, and the failure is indirect and
    # baffling: "failed to create temporary file .../.gnupg/.#lk..." followed
    # by "can't connect to the dirmngr". A scratch GNUPGHOME avoids depending
    # on, or polluting, whatever root's looks like.
    local gnupg; gnupg="$(mktemp -d)"
    export GNUPGHOME="$gnupg/home"
    mkdir -p -m700 "$GNUPGHOME"
    local kr="$gnupg/keyring.gpg"

    # THE KEY COMES OVER HTTPS, NOT FROM A KEYSERVER. A keyserver needs
    # dirmngr, which needs a working gpg home and an outbound hkps connection;
    # Gentoo publishes the same keys as a file over TLS from its own
    # infrastructure, which needs neither. The keyserver stays as a fallback.
    say "fetching Gentoo's signing keys"
    if curl -fsSL --max-time 120 "$KEYBUNDLE" -o "$gnupg/keys.gpg" \
       && gpg --no-default-keyring --keyring "$kr" --import "$gnupg/keys.gpg" 2>/dev/null; then
        say "imported from $KEYBUNDLE"
    else
        warn "the HTTPS bundle failed, trying the keyserver"
        gpg --no-default-keyring --keyring "$kr" --keyserver "$KEYSERVER" \
            --recv-keys "$RELEASE_KEY" 2>&1 | sed 's/^/  /' \
            || { rm -rf "$gnupg"; die "could not obtain Gentoo's release key by either route"; }
    fi

    gpg --no-default-keyring --keyring "$kr" --list-keys "$RELEASE_KEY" >/dev/null 2>&1 \
        || { rm -rf "$gnupg"; die "release key $RELEASE_KEY is not in the keyring that was fetched"; }
    say "release key $RELEASE_KEY present"

    say "verifying the signature"
    if gpg --no-default-keyring --keyring "$kr" --verify "$dest.asc" "$dest" 2>&1 | sed 's/^/  /'; then
        say "signature good"
        rm -rf "$gnupg"
    else
        rm -rf "$gnupg" "$dest" "$dest.asc"
        die "SIGNATURE VERIFICATION FAILED - the download was deleted"
    fi
    printf '\n  %s\n  Next: %s unpack\n' "$(du -h "$dest" | cut -f1) at $dest" "$name"
}

cmd_unpack() {
    require_root_mounted
    local tarball
    tarball="$(find "$ROOT" -maxdepth 1 -name 'stage3-*.tar.xz' | head -1)"
    [[ -n $tarball ]] || die "no stage3 tarball in $ROOT - run '$name fetch' first"
    [[ -f "$tarball.asc" ]] || die "no .asc beside $tarball - refusing to unpack unverified"

    # Unpacking over an existing system would merge two userlands into one.
    if [[ -e "$ROOT/usr/bin/env" ]]; then
        die "$ROOT already contains a system - refusing to unpack over it"
    fi

    say "unpacking $(basename "$tarball")"
    tar xpf "$tarball" --xattrs-include='*.*' --numeric-owner -C "$ROOT"
    say "unpacked"
    rm -f "$tarball" "$tarball.asc"
    say "tarball and keyring removed"
    printf '  %s\n' "$(du -sh "$ROOT" | cut -f1) in $ROOT"
    printf '\n  Next: %s chroot\n' "$name"
}

cmd_chroot() {
    require_root_mounted
    [[ -x "$ROOT/bin/bash" ]] || die "no system in $ROOT - unpack first"

    say "binding the kernel filesystems"
    local m
    for m in proc sys dev run; do mkdir -p "$ROOT/$m"; done
    mountpoint -q "$ROOT/proc" || mount -t proc  /proc "$ROOT/proc"
    mountpoint -q "$ROOT/sys"  || { mount --rbind /sys  "$ROOT/sys";  mount --make-rslave "$ROOT/sys"; }
    mountpoint -q "$ROOT/dev"  || { mount --rbind /dev  "$ROOT/dev";  mount --make-rslave "$ROOT/dev"; }
    mountpoint -q "$ROOT/run"  || { mount --rbind /run  "$ROOT/run";  mount --make-rslave "$ROOT/run"; }

    say "copying resolv.conf so the chroot has DNS"
    cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"

    say "entering - type exit to leave"
    printf '  Inside, start with:  source /etc/profile && export PS1="(gentoo) $PS1"\n\n'
    chroot "$ROOT" /bin/bash --login
}

case "${1:-}" in
    fetch)  cmd_fetch  ;;
    unpack) cmd_unpack ;;
    chroot) cmd_chroot ;;
    *) die "usage: $name [fetch|unpack|chroot] [root] - see the header" ;;
esac
