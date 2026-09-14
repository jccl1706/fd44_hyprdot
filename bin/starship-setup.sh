#!/usr/bin/env bash
# =========================================================================
# starship-setup.sh - a two-line Starship prompt for bash, per user
# =========================================================================
#
# Usage:  bin/starship-setup.sh            install or update (no sudo)
#         bin/starship-setup.sh --remove   take it out again
#
# Everything goes inside your home directory:
#   ~/.local/bin/starship        the binary, a pinned and checksummed release
#   ~/.config/starship.toml      symlink to starship/starship.toml in this repo
#   ~/.bashrc.d/starship.sh      starts it in interactive bash
#
# WHY NOT DNF. Fedora does not package starship. The COPR that does
# (atim/starship) is a third party and lags upstream - its newest good Fedora
# 44 build was 1.24.2 when this was written - so this takes the upstream
# release and pins its sha256, the way install-nerd-font.sh pins the font. The
# musl build is statically linked, so a glibc update cannot break it.
#
# WHY NOT THE INSTALLER. A prompt is taste, not a fix; the installer carries
# only what the machine needs to work.
#
# COLOURS. The config names ANSI colours only, never hex values, so the prompt
# is drawn in kitty's palette and follows bin/theme.sh between dark and cream
# with nothing to regenerate.
#
# To move to a newer release, change VERSION and SHA256 together - the hash is
# in the .sha256 file published next to the tarball - and run this again.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="v1.26.0"
ASSET="starship-x86_64-unknown-linux-musl.tar.gz"
URL="https://github.com/starship/starship/releases/download/$VERSION/$ASSET"
SHA256="b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3"

BIN="$HOME/.local/bin/starship"
CONFIG="$HOME/.config/starship.toml"
SNIPPET="$HOME/.bashrc.d/starship.sh"
SOURCE_CONFIG="$repo/starship/starship.toml"

die()  { printf 'starship-setup: %s\n' "$*" >&2; exit 1; }
warn() { printf 'starship-setup: WARNING - %s\n' "$*" >&2; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

(( EUID != 0 )) || die "run this as yourself, not with sudo - it only touches your home directory"

if [[ ${1:-} == --remove ]]; then
    rm -f "$SNIPPET"
    log "removed $SNIPPET"
    # Only this repo's link. A starship.toml of your own is left alone.
    if [[ -L $CONFIG && $(readlink "$CONFIG") == "$SOURCE_CONFIG" ]]; then
        rm -f "$CONFIG"
        log "removed the link $CONFIG"
    fi
    rm -f "$BIN"
    log "removed $BIN"
    log "open a new terminal for the plain bash prompt"
    exit 0
fi
(( $# == 0 )) || die "usage: $0 [--remove]"

[[ $(uname -m) == x86_64 ]] || die "the pinned release is x86_64 only, this machine is $(uname -m)"
[[ -f $SOURCE_CONFIG ]] || die "missing $SOURCE_CONFIG - run this from a full checkout"

# --- the binary ----------------------------------------------------------
installed=""
if [[ -x $BIN ]]; then
    # "starship 1.26.0" on the first line. awk reads to the end, so starship
    # never meets a closed pipe.
    installed="$("$BIN" --version 2>/dev/null | awk 'NR == 1 { print $2 }' || true)"
fi

if [[ $installed == "${VERSION#v}" ]]; then
    log "starship $installed already installed: $BIN"
else
    [[ -n $installed ]] && log "replacing starship $installed"
    log "downloading starship $VERSION"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL --retry 2 --max-time 120 "$URL" -o "$tmp/$ASSET" \
        || die "download failed - check the network, or fetch $URL by hand"
    printf '%s  %s\n' "$SHA256" "$tmp/$ASSET" | sha256sum --check --status \
        || die "the download does not match the pinned sha256 - not installing it"
    tar --no-same-owner --no-same-permissions -xzf "$tmp/$ASSET" -C "$tmp" starship \
        || die "could not extract starship from the archive"
    [[ -f "$tmp/starship" && ! -L "$tmp/starship" ]] \
        || die "starship in the archive is not a regular file - not installing it"
    mkdir -p "$(dirname "$BIN")"
    install -m 0755 "$tmp/starship" "$BIN"
    log "installed starship ${VERSION#v}: $BIN"
fi

# --- the config ----------------------------------------------------------
# A symlink, like ~/.config/kitty and the rest: edits in the repo are live.
mkdir -p "$(dirname "$CONFIG")"
if [[ -L $CONFIG && $(readlink "$CONFIG") == "$SOURCE_CONFIG" ]]; then
    log "already linked: $CONFIG"
else
    if [[ -e $CONFIG || -L $CONFIG ]]; then
        backup="$CONFIG.before-fd44-$(date +%Y%m%d-%H%M%S)"
        mv "$CONFIG" "$backup"
        log "kept the previous config as $backup"
    fi
    ln -s "$SOURCE_CONFIG" "$CONFIG"
    log "linked $CONFIG -> $SOURCE_CONFIG"
fi

# --- bash ----------------------------------------------------------------
mkdir -p "$(dirname "$SNIPPET")"
cat >"$SNIPPET" <<'EOF'
# Starship prompt - written by fd44_hyprdot's bin/starship-setup.sh.
# Interactive shells only, and not on the Linux console (tty1, where autologin
# runs): the console font has none of the prompt's glyphs.
if [[ $- == *i* && $TERM != linux ]] && command -v starship >/dev/null; then
    eval "$(starship init bash)"
fi
EOF
log "wrote $SNIPPET"

# Fedora's default ~/.bashrc reads ~/.bashrc.d/. One written by hand may not.
if ! grep -qs 'bashrc\.d' "$HOME/.bashrc"; then
    warn "~/.bashrc does not read ~/.bashrc.d/, so the prompt will not start. Add:"
    printf '    for rc in ~/.bashrc.d/*; do [ -f "$rc" ] && . "$rc"; done\n' >&2
fi
if [[ -n ${STARSHIP_CONFIG:-} && $STARSHIP_CONFIG != "$CONFIG" ]]; then
    warn "STARSHIP_CONFIG is set to $STARSHIP_CONFIG, which overrides $CONFIG"
fi

# --- check ---------------------------------------------------------------
# A config starship cannot read is not an error to it: it prints a warning
# and draws its defaults. So its stderr is the test.
complaints="$(cd "$HOME" && STARSHIP_CONFIG="$CONFIG" "$BIN" prompt 2>&1 >/dev/null)" \
    || die "starship prompt failed: $complaints"
[[ -z $complaints ]] || die "starship did not accept $CONFIG: $complaints"
log "config accepted by starship ${VERSION#v}"

printf '\n'
log "open a new terminal, or run: exec bash"
