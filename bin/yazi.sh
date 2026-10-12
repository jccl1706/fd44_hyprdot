#!/usr/bin/env bash
# =========================================================================
# yazi.sh - the terminal file manager, pinned and checksummed
# =========================================================================
#
# Usage:  bin/yazi.sh            install it if it is not here (no root)
#         bin/yazi.sh --status   what is pinned against what is installed
#         bin/yazi.sh --force    fetch again even if present
#         bin/yazi.sh --remove   take it out again
#
# WHY THIS EXISTS. chafa prints an image and exits; what was actually wanted
# was arrows through a folder with the picture appearing beside the name. That
# is a file manager with previews, and of the ones that do it well, yazi is not
# in any Fedora repository - ranger and nnn are, and both want a preview helper
# bolted on, while yazi speaks kitty's graphics protocol itself.
#
# SO IT IS FETCHED, AND FETCHED THE WAY EVERYTHING ELSE HERE IS: a pinned
# version with a checksum, the same as bin/install-nerd-font.sh and
# bin/gtk-theme.sh. A release that moves under you is a tool that behaves
# differently for no reason you can name, and an unverified download is
# something else entirely.
#
# THE musl BUILD, NOT gnu, AND THAT IS THE WHOLE POINT OF THE CHOICE. It is
# statically linked, so it does not care which glibc the machine has. These
# dotfiles run on Fedora, Debian and NixOS, and on NixOS in particular a
# dynamically linked binary dropped into ~/.local/bin does not run at all -
# there is no /lib64/ld-linux-x86-64.so.2 for it to start from. One file, three
# distributions.
#
# `yazi --version` REPORTS THE gnu TRIPLE EVEN IN THIS BUILD. It is a string
# baked in at build time and says nothing about linkage; `ldd` on the installed
# file answers "statically linked" and it has no ELF interpreter at all, which
# is the thing that actually matters on NixOS. Checked, because the version
# output flatly contradicts the asset name and the next person to look will
# wonder which is lying.
#
# x86_64 ONLY, DELIBERATELY. yazi publishes aarch64 and riscv64 builds too, but
# a checksum is a promise that this exact file was seen, and pinning one for an
# architecture that cannot be tested here would be a promise made up. The error
# below says so rather than guessing.
#
# IMAGE PREVIEWS NEED tmux/tmux.conf's allow-passthrough, which is set there
# with the reasoning written beside it: inside tmux, kitty's graphics protocol
# is filtered out before it reaches kitty, and yazi draws nothing.

set -euo pipefail

VERSION="v26.9.1"
ASSET="yazi-x86_64-unknown-linux-musl"
URL="https://github.com/sxyazi/yazi/releases/download/$VERSION/$ASSET.zip"
SHA256="9b9c39decccf8cb0ff53a7d637d38f8a79d93bbd0099f4ea9c619ef6bb392f5d"

# `yazi` is the file manager and `ya` is its command line helper - the plugin
# manager and the way a shell talks to a running instance. Both or neither:
# yazi's own documentation assumes `ya` is on PATH.
BINS=(yazi ya)
DEST="$HOME/.local/bin"

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_d=$'\033[2m'; c_0=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%syazi:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

mode=install force=false
for a in "$@"; do
    case "$a" in
        --status) mode=status ;;
        --remove) mode=remove ;;
        --force)  force=true ;;
        -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
        *) die "unknown argument: $a" ;;
    esac
done

installed_version() {
    command -v yazi >/dev/null 2>&1 || return 1
    # `yazi --version` prints a BLOCK, not a line: "Yazi" on its own, then
    # indented Version/Debug/Triple/Rustc rows. Taking the first line's second
    # field - which is what you write without looking - returns the empty
    # string, and the empty string compares unequal to every version, so a
    # correct install reported "installed version is not the pinned one".
    yazi --version 2>/dev/null | awk '/Version:/ { print $2; exit }'
}

if [[ $mode == status ]]; then
    printf '  %-14s %s\n' pinned "$VERSION"
    if v="$(installed_version)"; then
        printf '  %-14s %s  (%s)\n' installed "v${v#v}" "$(command -v yazi)"
        [[ "v${v#v}" == "$VERSION" ]] || warn "  installed version is not the pinned one"
    else
        printf '  %-14s %s\n' installed "not here"
    fi
    printf '  %-14s %s\n' "would go in" "${DEST/#$HOME/\~}"
    printf '\n  %sImage previews also need allow-passthrough in tmux/tmux.conf.%s\n' "$c_d" "$c_0"
    exit 0
fi

if [[ $mode == remove ]]; then
    for b in "${BINS[@]}"; do
        [[ -e $DEST/$b ]] && rm -f "$DEST/$b" && say "removed ${DEST/#$HOME/\~}/$b"
    done
    exit 0
fi

[[ "$(uname -m)" == x86_64 ]] \
    || die "only the x86_64 build is pinned here, and this is $(uname -m) - see the note at the top"

if command -v yazi >/dev/null 2>&1 && ! $force; then
    printf '    %salready%s  yazi v%s at %s\n' "$c_d" "$c_0" "$(installed_version)" "$(command -v yazi)"
    exit 0
fi

command -v curl >/dev/null || die "curl is not installed"

# ITS OWN EMPTY DIRECTORY, and nothing is ever run from inside it. A downloaded
# archive is untrusted until the checksum says otherwise, and even then it is
# only ever read.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say "fetching yazi $VERSION"
curl -fsSL --retry 2 --max-time 300 "$URL" -o "$TMP/yazi.zip" \
    || die "could not download $URL"

printf '%s  %s\n' "$SHA256" "$TMP/yazi.zip" | sha256sum --check --status \
    || die "CHECKSUM MISMATCH - refusing to install it
  expected  $SHA256
  got       $(sha256sum "$TMP/yazi.zip" | cut -d' ' -f1)"

say "checksum matches"

# EXTRACTED WITH python RATHER THAN unzip, for two reasons. unzip is not
# installed on a minimal Fedora and python3 always is; and zipfile lets the
# entries be checked before anything is written. Python's extractall does NOT
# have tarfile's `filter="data"` - there is no equivalent for zip - so the
# traversal check is done here by hand rather than assumed.
mkdir -p "$TMP/x"
python3 -I - "$TMP/yazi.zip" "$TMP/x" <<'PY'
import os, sys, zipfile
src, dest = sys.argv[1], os.path.realpath(sys.argv[2])
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        target = os.path.realpath(os.path.join(dest, info.filename))
        if not (target == dest or target.startswith(dest + os.sep)):
            sys.exit(f"refusing entry outside the extraction directory: {info.filename}")
    z.extractall(dest)
PY

mkdir -p "$DEST"
for b in "${BINS[@]}"; do
    src="$TMP/x/$ASSET/$b"
    [[ -f $src ]] || die "the archive does not contain $b - the asset layout has changed"
    install -m 0755 "$src" "$DEST/$b"
    printf '    installed %s\n' "${DEST/#$HOME/\~}/$b"
done

cat <<NEXT

  yazi $VERSION is in ${DEST/#$HOME/\~}, which is already on PATH.

    yazi ~/.cache/fd44-shots      arrow through the shell's screenshots
    q                             quit
    ya pkg --help                 plugins, if you ever want them

  Images draw through kitty's graphics protocol. Inside tmux that needs
  allow-passthrough, which tmux/tmux.conf sets - if previews come out as
  blocks or nothing, that is the first thing to check.
NEXT
