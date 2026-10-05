#!/usr/bin/env bash
# =========================================================================
# ollama-setup.sh - Ollama with CUDA, on the NVIDIA desktop
# =========================================================================
#
# Usage:  sudo bin/ollama-setup.sh            install or update
#         sudo bin/ollama-setup.sh --remove   take it out again
#
# Opt-in, and specific to one machine's hardware, like bin/cooling-setup.sh:
# this installs the CUDA build, which is the right one for fedora-gaming00's
# RTX 5090 and the wrong one for the Framework laptop.
#
# WHY NOT DNF, WHEN FEDORA PACKAGES IT. Fedora 44 has ollama 0.12.11, and its
# build is CPU + ROCm ONLY: it ships libggml-hip.so and REQUIRES hipblas and
# rocblas. There is no CUDA backend, because CUDA cannot ship in Fedora. On this
# machine that package would run models on the CPU while pulling in AMD's ROCm
# stack for a GPU that is not here. Checked with `dnf repoquery --requires
# ollama` and `-l`, not assumed.
#
# WHY NOT `curl | sh`. Upstream's install.sh is the documented route and it
# works, but it decides versions and paths at run time and nothing records what
# landed. This pins the release and verifies its sha256 the way
# bin/starship-setup.sh pins starship, so an install is reproducible and a
# tampered download fails closed.
#
# THREE TARBALLS EXIST and only one is right here: -rocm is AMD, -mlx is Apple
# silicon, and the plain amd64 one carries the CPU backends AND CUDA. 1.4 GiB,
# most of which is the CUDA runtime it brings so the system needs no CUDA
# toolkit - only the driver, which xorg-x11-drv-nvidia already provides.
#
# IT LISTENS ON LOCALHOST ONLY. The service binds 127.0.0.1:11434 by default and
# this script does not change that. The API has no authentication of any kind,
# so anything that can reach it can use the GPU and read every model and prompt.
# To reach it from the laptop, do it over ssh - `ssh -L 11434:localhost:11434
# gaming00` - rather than by setting OLLAMA_HOST=0.0.0.0.
#
# To move to a newer release, change VERSION and SHA256 together - the hash is
# in the release's sha256sum.txt - and run this again.

set -euo pipefail

VERSION="v0.35.1"
ASSET="ollama-linux-amd64.tar.zst"
URL="https://github.com/ollama/ollama/releases/download/$VERSION/$ASSET"
SHA256="9fcd79ac4575b2bd31b992eee18b1000c8ad126b451627c8f8cd091714cfbb10"

PREFIX="/usr/local"
UNIT="/etc/systemd/system/ollama.service"
HOME_DIR="/usr/share/ollama"

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sollama-setup:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

(( EUID == 0 )) || die "run this with sudo - it installs a system service"

if [[ ${1:-} == --remove ]]; then
    systemctl disable --now ollama.service 2>/dev/null || true
    rm -f "$UNIT"
    systemctl daemon-reload
    rm -f "$PREFIX/bin/ollama"
    rm -rf "$PREFIX/lib/ollama"
    log "removed the binary, libraries and unit"
    warn "models are left in $HOME_DIR - delete that yourself if you mean to"
    exit 0
fi

command -v nvidia-smi >/dev/null || warn "no nvidia-smi - the CUDA build will fall back to CPU"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "downloading ollama $VERSION (1.4 GiB)"
curl -fL --progress-bar -o "$tmp/$ASSET" "$URL"

log "verifying sha256"
echo "$SHA256  $tmp/$ASSET" | sha256sum -c - >/dev/null \
    || die "checksum mismatch - refusing to install. Did VERSION change without SHA256?"
log "checksum ok"

# THE TARBALL UNPACKS INTO bin/ AND lib/ ALREADY, so it extracts straight into
# /usr/local. An old lib/ollama is removed first: the CUDA libraries are
# versioned by directory and a stale one left beside a new one is how a runner
# ends up loading two CUDA runtimes.
log "installing into $PREFIX"
rm -rf "$PREFIX/lib/ollama"
tar -C "$PREFIX" --zstd -xf "$tmp/$ASSET"

log "what came with it"
find "$PREFIX/lib/ollama" -maxdepth 1 -name 'cuda*' -o -maxdepth 1 -name 'libggml-*' \
    | sed "s|$PREFIX/lib/ollama/|    |" | sort

# A SYSTEM USER WITH NO SHELL AND NO PASSWORD. The service holds the GPU and
# answers an HTTP port; it has no reason to be able to log in. Models land in
# its home, which is why that is given explicitly rather than left in /var/empty.
if ! getent passwd ollama >/dev/null; then
    log "creating the ollama system user"
    useradd --system --create-home --home-dir "$HOME_DIR" \
            --shell /sbin/nologin --comment "Ollama" ollama
fi

# RENDER AND VIDEO, so the service can open the GPU. On this machine
# /dev/nvidia* are 0666 and it would work without them, but that is the driver's
# default rather than a guarantee, and a udev rule or a driver update can change
# it - at which point the failure is "no GPU found" and nothing about permissions.
for g in video render; do
    getent group "$g" >/dev/null && usermod -aG "$g" ollama
done

log "writing $UNIT"
cat > "$UNIT" <<UNITFILE
[Unit]
Description=Ollama
Documentation=https://github.com/ollama/ollama
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
ExecStart=$PREFIX/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3

# LOCALHOST ONLY, deliberately - the API is unauthenticated. See the header.
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

# The models directory is the only thing it needs to write.
ProtectSystem=strict
ReadWritePaths=$HOME_DIR
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
UNITFILE

log "enabling the service"
systemctl daemon-reload
systemctl enable --now ollama.service

sleep 3
printf '\n'
log "done"
printf '  %-14s %s\n' "version"  "$("$PREFIX/bin/ollama" --version 2>&1 | tail -1)"
printf '  %-14s %s\n' "service"  "$(systemctl is-active ollama.service)"
printf '  %-14s %s\n' "listening" "$(ss -ltn 2>/dev/null | awk '/11434/{print $4; exit}')"
printf '  %-14s %s\n' "gpu"      "$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null)"
printf '\n'
log "pull a model, as yourself:  ollama run gemma3:12b"
log "the GPU is only used once a model is loaded - check with: ollama ps"
