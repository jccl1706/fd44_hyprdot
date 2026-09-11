#!/usr/bin/env bash
#
# Boot a throwaway UEFI VM to test install_fedora_v1_9.sh without touching
# this laptop. Nothing here writes outside $VMDIR.
#
# Usage:
#   ./vm-test.sh /path/to/Fedora-Workstation-Live-x86_64-44-*.iso
#   ./vm-test.sh --reboot      boot the installed disk again, no ISO
#   ./vm-test.sh --clean       delete the VM disk and start over
#
# Get an ISO from https://fedoraproject.org/workstation/download
# (Workstation Live is easiest: it boots to a desktop with a terminal, has
# network, and sudo works without a password as the "liveuser" account.)
#
# Once the VM is up, inside it:
#
#   curl -O http://10.0.2.2:8000/install_fedora_v1_9.sh     # 10.0.2.2 = this host
#   chmod +x install_fedora_v1_9.sh
#   ./install_fedora_v1_9.sh --check-repos                  # no root needed
#   sudo ./install_fedora_v1_9.sh --dry-run                 # prints, touches nothing
#   sudo ./install_fedora_v1_9.sh                           # the real thing
#
# The VM's disk is /dev/vda - pick that when the wizard asks, NOT anything else.

set -euo pipefail

VMDIR="${VMDIR:-$HOME/.local/share/fedora-vm-test}"
DISK="$VMDIR/disk.qcow2"
VARS="$VMDIR/OVMF_VARS.fd"
DISK_SIZE="${DISK_SIZE:-40G}"
RAM="${RAM:-8G}"
CPUS="${CPUS:-4}"
HTTP_PORT="${HTTP_PORT:-8000}"
# Host port forwarded to the VM's port 22, so the VM can be driven over ssh
# instead of only through the graphical console. Nothing listens on it until
# sshd is started INSIDE the VM - see the banner below.
SSH_PORT="${SSH_PORT:-2222}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# --- locate OVMF (UEFI firmware) -----------------------------------------
# The installer uses systemd-boot and an ESP, so the VM MUST be UEFI. A
# default qemu VM is BIOS and the install would boot to nothing.
find_ovmf() {
    local c
    for c in /usr/share/edk2/ovmf/OVMF_CODE.fd \
             /usr/share/edk2/ovmf/OVMF_CODE_4M.fd \
             /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f $c ]] && { echo "$c"; return 0; }
    done
    return 1
}
find_ovmf_vars() {
    local c
    for c in /usr/share/edk2/ovmf/OVMF_VARS.fd \
             /usr/share/edk2/ovmf/OVMF_VARS_4M.fd \
             /usr/share/OVMF/OVMF_VARS.fd; do
        [[ -f $c ]] && { echo "$c"; return 0; }
    done
    return 1
}

case "${1:-}" in
    --clean)
        log "removing $VMDIR"
        rm -rf "$VMDIR"
        exit 0
        ;;
esac

command -v qemu-system-x86_64 >/dev/null || die "qemu not installed. Run:
  sudo dnf install qemu-system-x86-core qemu-img edk2-ovmf qemu-ui-gtk \\
                   qemu-device-display-virtio-gpu qemu-device-display-virtio-vga-gl \\
                   qemu-device-display-virtio-gpu-gl virglrenderer"

OVMF_CODE="$(find_ovmf)"      || die "OVMF firmware not found - install edk2-ovmf"
OVMF_VARS_SRC="$(find_ovmf_vars)" || die "OVMF vars template not found - install edk2-ovmf"

mkdir -p "$VMDIR"

# Per-VM copy of the UEFI variable store, so boot entries persist across runs
# and the system template is never modified.
[[ -f $VARS ]] || { log "creating UEFI vars from $OVMF_VARS_SRC"; cp "$OVMF_VARS_SRC" "$VARS"; }

if [[ ! -f $DISK ]]; then
    log "creating $DISK_SIZE disk at $DISK"
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

ISO_ARGS=()
if [[ "${1:-}" == "--reboot" ]]; then
    log "booting the installed disk (no ISO)"
else
    ISO="${1:-}"
    [[ -n $ISO ]] || die "give me an ISO path, or --reboot / --clean. See the header."
    [[ -f $ISO ]] || die "no such ISO: $ISO"
    ISO_ARGS=(-cdrom "$ISO" -boot order=d,menu=on)
    log "booting from $ISO"
fi

# Serve this directory so the VM can fetch the installer at 10.0.2.2 - qemu's
# user-mode networking always maps the host to that address.
if ! curl -s --max-time 1 "http://127.0.0.1:$HTTP_PORT/" >/dev/null 2>&1; then
    log "serving $SCRIPT_DIR on port $HTTP_PORT (for the VM to curl)"
    ( cd "$SCRIPT_DIR" && exec python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 ) \
        >/dev/null 2>&1 &
    HTTP_PID=$!
    trap 'kill '"$HTTP_PID"' 2>/dev/null || true' EXIT
else
    log "something is already serving port $HTTP_PORT - reusing it"
fi

cat <<EOF

  Inside the VM:
    curl -O http://10.0.2.2:$HTTP_PORT/$(basename "$SCRIPT_DIR"/install_fedora_v1_9.sh 2>/dev/null || echo install_fedora_v1_9.sh)
    chmod +x install_fedora_v1_9.sh
    ./install_fedora_v1_9.sh --check-repos
    sudo ./install_fedora_v1_9.sh --dry-run
    sudo ./install_fedora_v1_9.sh          # target disk is /dev/vda

  To drive the VM over ssh instead of the console, run this INSIDE it:
    sudo systemctl start sshd
    sudo passwd liveuser          # set any password; it is a throwaway VM

  then from this laptop:
    ssh -p $SSH_PORT liveuser@127.0.0.1

  NOTE the installed system will NOT have sshd - openssh-server is
  deliberately not in the installer's package list. ssh is for driving the
  live environment while testing, not the result.

  KEYBOARD GRAB: this host runs Hyprland too, so SUPER+<key> is caught by
  YOUR desktop before it ever reaches the guest. grab-on-hover is enabled, so
  moving the pointer into the VM window hands the whole keyboard - SUPER
  included - to the guest. ctrl+alt+g toggles the grab manually.
  (The mechanism is the Wayland keyboard-shortcuts-inhibit protocol, which
  GDK implements and Hyprland honours.)
  Shut the VM down from inside, or just close the window.

EOF

# Pick a display device we can actually run.
#
# virtio-vga-gl is a thin VGA-compatible wrapper that internally instantiates
# the "virtio-gpu-gl-device" type. That type lives in a DIFFERENT module,
# hw-display-virtio-gpu-gl.so, shipped by qemu-device-display-virtio-gpu-gl -
# and qemu-device-display-virtio-vga-gl does NOT depend on it. Install one
# without the other and qemu does not report a missing type: it SEGFAULTS
# inside error_prepend() while building the error message
# (qemu 10.2.2 / Fedora 44). libvirglrenderer is needed too, at runtime.
#
# So check for the module and the library directly rather than trusting the
# device to fail cleanly.
if [[ -e /usr/lib64/qemu/hw-display-virtio-gpu-gl.so ]] \
   && ls /usr/lib64/libvirglrenderer.so.* >/dev/null 2>&1; then
    VIDEO=(-device virtio-vga-gl -display gtk,gl=on,grab-on-hover=on)
    log "3D acceleration available (virglrenderer present)"
else
    VIDEO=(-device virtio-vga -display gtk,grab-on-hover=on)
    log "3D unavailable - falling back to software rendering"
    [[ -e /usr/lib64/qemu/hw-display-virtio-gpu-gl.so ]] \
        || log "  missing: qemu-device-display-virtio-gpu-gl"
    ls /usr/lib64/libvirglrenderer.so.* >/dev/null 2>&1 \
        || log "  missing: virglrenderer"
    log "  the install will still work; Hyprland itself may not start."
fi

# Run qemu's GTK window through XWayland rather than natively on Wayland.
#
# GTK3's Wayland backend implements NEITHER zwp_pointer_constraints_v1 NOR
# zwp_relative_pointer_manager_v1 (0 references in libgdk-3.so.0), so when
# qemu grabs input it cannot lock the pointer or receive relative motion:
# the keyboard grab works - that is a different protocol, which GDK does
# have - but the mouse stops moving inside the guest entirely.
#
# X11 has native XGrabPointer and needs no such protocol, so under XWayland
# the grab works fully. Hyprland still composites the window; this only
# changes which toolkit backend GTK uses. Costs one translation layer.
#
# Needs xorg-x11-server-Xwayland installed (it is, on this machine).
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -n "${DISPLAY:-}" ]]; then
    log "using XWayland for the qemu window (working pointer grab)"
    export GDK_BACKEND=x11
elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    warn "no DISPLAY set - qemu will run natively on Wayland, and the mouse"
    warn "  will stop moving whenever input is grabbed (GTK3 Wayland lacks"
    warn "  pointer constraints). Install/enable Xwayland to fix."
fi

log "starting VM (${RAM} RAM, ${CPUS} vCPU, ${DISK_SIZE} disk, UEFI)"
exec qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,smm=on \
    -cpu host \
    -m "$RAM" \
    -smp "$CPUS" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$VARS" \
    -drive "file=$DISK,if=virtio,format=qcow2,cache=writeback" \
    "${ISO_ARGS[@]}" \
    "${VIDEO[@]}" \
    -netdev user,id=net0,hostfwd=tcp::"$SSH_PORT"-:22 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-tablet-pci \
    -device virtio-mouse-pci \
    -device virtio-keyboard-pci \
    -audiodev none,id=snd0
