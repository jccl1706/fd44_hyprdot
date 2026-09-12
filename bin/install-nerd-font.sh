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
# The version is pinned to match install_fedora_v1_11.sh. If one changes the
# other should too, or a reinstall will quietly move the font backwards.

set -euo pipefail

VERSION="v3.4.0"
URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$VERSION/NerdFontsSymbolsOnly.tar.xz"
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

if [[ -f "$DEST/$FILE" ]]; then
    log "already installed: $DEST/$FILE"
else
    # Reuse a copy that is already on the machine before going to the network.
    # The usual case for this script is a font that is present but in the
    # wrong place, and re-downloading 2.4MB to replace a file that is already
    # correct is pointless.
    found=""
    if [[ -n $target_home && -f "$target_home/.local/share/fonts/$FILE" ]]; then
        found="$target_home/.local/share/fonts/$FILE"
    fi

    if [[ -n $found ]]; then
        log "reusing the copy already at $found"
        install -m 0644 -o root -g root "$found" "$DEST/$FILE"
    else
        log "downloading Symbols Nerd Font $VERSION"
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        curl -fsSL --retry 2 --max-time 120 "$URL" -o "$tmp/symbols.tar.xz" \
            || die "download failed - check the network, or fetch $URL by hand"
        # --no-same-owner because the archive carries the uid of whoever built
        # it upstream, and tar as root would honour it: that is how this font
        # once ended up owned by uid 1001.
        tar --no-same-owner --no-same-permissions \
            -xJf "$tmp/symbols.tar.xz" -C "$DEST" "$FILE" \
            || die "could not extract $FILE from the archive"
        chown root:root "$DEST/$FILE"
        chmod 644 "$DEST/$FILE"
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
