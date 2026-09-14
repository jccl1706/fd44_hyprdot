#!/usr/bin/env bash
# =========================================================================
# install-nerd-font.sh - put Symbols Nerd Font where the system expects it
# =========================================================================
#
# Usage:  sudo bin/install-nerd-font.sh
#
# Installs the font system-wide at the path the installer uses, and removes
# any per-user copy that would shadow it.
#
# WHY THIS EXISTS. Fedora packages no Symbols Nerd Font - the only "nerd" font
# in the repos is texlive-inconsolata-nerd-font, which is unrelated - so the
# installer downloads it. That is the one step in the whole install that
# reaches the public internet and is allowed to fail without aborting, and
# when it fails every glyph in the bar, launcher, OSD, power menu and lock
# screen renders as an empty box. This is the repair.
#
# It is also the fix for a subtler problem. A font dropped in
# ~/.local/share/fonts works, and fontconfig prefers it, so a machine with a
# hand-placed user copy renders perfectly while the system path sits empty -
# and a fresh install of the same config then has no glyphs at all. That is
# how this project's development machine diverged from what it shipped, and
# nothing on that machine could have revealed it. So this removes the user
# copy rather than leaving both.
#
# The font is COMMITTED to this repo, at fonts/nerd-fonts-symbols/, so the
# normal path copies it out of the checkout and never touches the network. The
# download below is only for a machine that somehow has this script without
# the rest of the repository.
#
# The version is pinned to match install_fedora.sh. If one changes the
# other should too, or a reinstall will quietly move the font backwards.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="v3.4.0"
URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$VERSION/NerdFontsSymbolsOnly.tar.xz"
# sha256 of that tarball, the same pin as install_fedora.sh's
# nerdfont_sha256. The font inside matches the copy committed in fonts/.
SHA256="7f8c090da3b0eaa7108646bf34cbbb6ed13d5358a72460522108b06c7ecd716a"
DEST="/usr/local/share/fonts/nerd-fonts-symbols"
FILE="SymbolsNerdFont-Regular.ttf"

die() { printf 'install-nerd-font: %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

(( EUID == 0 )) || die "must run as root - try: sudo $0"

# The user who invoked sudo, so their stray copy can be cleaned up. Falls back
# to nothing rather than guessing, since removing files out of the wrong home
# directory is not a mistake worth risking to save one command.
target_user="${SUDO_USER:-}"
target_home=""
if [[ -n $target_user ]]; then
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
fi

mkdir -p "$DEST"

vendored="$repo/fonts/nerd-fonts-symbols/$FILE"
# A symlink is refused: `install` below runs as root and would follow it, and
# the checkout is writable by the user.
[[ ! -L $vendored ]] || die "refusing $vendored: it is a symlink, not a font file"

# ALREADY PRESENT IS NOT THE SAME AS CORRECT. If the installed file differs
# from the one committed here, replace it - that is the whole job of a repair
# script. Skipping on mere existence is how this machine ended up running
# 3.5.1 against a pin of 3.4.0 and nobody noticed.
if [[ -f "$DEST/$FILE" && -f $vendored ]] && cmp -s "$DEST/$FILE" "$vendored"; then
    log "already correct: $DEST/$FILE"
elif [[ -f "$DEST/$FILE" && ! -f $vendored ]]; then
    log "already installed (no vendored copy to compare against): $DEST/$FILE"
else
    [[ -f "$DEST/$FILE" ]] && log "installed copy differs from the one in this repo - replacing"

    # THE VENDORED COPY, never one found lying around on the machine. An
    # earlier version of this reused whatever it found in
    # ~/.local/share/fonts, which seemed thrifty and was wrong: that copy was
    # Nerd Fonts 3.5.1 while this script pinned 3.4.0, so it silently
    # installed a version nobody had asked for. A file of unknown provenance
    # is not a saving.
    if [[ -f $vendored ]]; then
        log "installing the copy committed to this repo"
        install -m 0644 -o root -g root "$vendored" "$DEST/$FILE"
    else
        log "downloading Symbols Nerd Font $VERSION"
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        curl -fsSL --retry 2 --max-time 120 "$URL" -o "$tmp/symbols.tar.xz" \
            || die "download failed - check the network, or fetch $URL by hand"
        printf '%s  %s\n' "$SHA256" "$tmp/symbols.tar.xz" | sha256sum --check --status \
            || die "the download does not match the pinned sha256 - not installing it"
        # --no-same-owner because the archive carries the uid of whoever built
        # it upstream, and tar as root would honour it: that is how this font
        # once ended up owned by uid 1001.
        #
        # Into the temp directory, not straight into $DEST: the old chown and
        # chmod after an in-place extraction followed a symlink, so an archive
        # whose "font" linked to /etc/shadow would have made it world-readable.
        tar --no-same-owner --no-same-permissions \
            -xJf "$tmp/symbols.tar.xz" -C "$tmp" "$FILE" \
            || die "could not extract $FILE from the archive"
        [[ -f "$tmp/$FILE" && ! -L "$tmp/$FILE" ]] \
            || die "$FILE in the archive is not a regular file - not installing it"
        install -m 0644 -o root -g root "$tmp/$FILE" "$DEST/$FILE"
        log "installed $DEST/$FILE"
    fi
fi

# Remove per-user copies that would shadow the system one. Only the exact
# SymbolsNerdFont files, never the whole directory - people keep other fonts
# in there.
if [[ -n $target_home && -d "$target_home/.local/share/fonts" ]]; then
    shopt -s nullglob
    strays=("$target_home/.local/share/fonts/"SymbolsNerdFont*.ttf)
    shopt -u nullglob
    if (( ${#strays[@]} )); then
        log "removing ${#strays[@]} per-user copy/copies that would shadow it"
        rm -f "${strays[@]}"
        # As the user, so their cache is rebuilt rather than root's.
        runuser -u "$target_user" -- fc-cache -f >/dev/null 2>&1 || true
    fi
fi

fc-cache -f >/dev/null 2>&1 || true

# Report what fontconfig actually resolves now, as the user rather than as
# root - root has a different cache and could disagree.
resolved=""
if [[ -n $target_user ]]; then
    resolved="$(runuser -u "$target_user" -- fc-match "Symbols Nerd Font" -f '%{file}' 2>/dev/null || true)"
else
    resolved="$(fc-match "Symbols Nerd Font" -f '%{file}' 2>/dev/null || true)"
fi

printf '\n'
if [[ $resolved == "$DEST/$FILE" ]]; then
    log "fontconfig resolves Symbols Nerd Font to the system copy:"
    printf '    %s\n' "$resolved"
else
    printf 'install-nerd-font: WARNING - fontconfig resolves to:\n' >&2
    printf '    %s\n' "${resolved:-nothing}" >&2
    printf '  expected %s\n' "$DEST/$FILE" >&2
    printf '  another copy is still shadowing it, or the cache is stale.\n' >&2
    exit 1
fi
