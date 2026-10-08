#!/usr/bin/env bash
# =========================================================================
# fedora_virt.sh - libvirt, QEMU/KVM and the macvtap LAN network
# =========================================================================
#
# Usage:  sudo install/fedora_virt.sh [--go]
#
# Stage six of six, opt-in, run ON the Fedora install. The other half of what
# fd44_nixos/modules/virtualisation.nix gives the NixOS system on the disk
# beside this one, so the Windows 11 guest can run from either side.
#
# IT DOES NOT COPY OR DEFINE A GUEST. Moving the guest across is a one-off
# migration with real decisions in it - a different QEMU version, a different
# firmware path, a disk image to copy - and belongs in neither an installer nor
# a loop. guests/README.md in fd44_nixos records how that was done.
#
# @virtualization IS NOT USED. The Fedora group is about 90 packages and brings
# a second network stack, a cockpit plugin and tooling for guest building. What
# is named below is what this machine actually needs to run one already-built
# Windows guest with a share and a LAN address.

set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfedora:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

GO=0
while (( $# )); do
    case "$1" in
        --go) GO=1; shift ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done
(( EUID == 0 )) || die "run this with sudo"
[[ -f /etc/fedora-release ]] || die "this runs on the Fedora install"
[[ -e /dev/kvm ]] || die "no /dev/kvm - check SVM is enabled in the firmware"

TARGET_USER="${SUDO_USER:-jc}"
NIC="eno1"

PKGS=(
    # The hypervisor and the daemon that drives it. libvirt-daemon-kvm pulls the
    # QEMU driver and its hooks; qemu-kvm is the emulator itself.
    qemu-kvm
    libvirt-daemon-kvm
    libvirt-client

    # UEFI firmware. The guest boots with secure boot on, which is a Windows 11
    # requirement, and that needs the secboot build of OVMF rather than the
    # plain one. libvirt picks the file itself from its firmware descriptors -
    # see the migration note about NOT hardcoding the path.
    edk2-ovmf

    # TPM 2.0, also a Windows 11 requirement, emulated per guest. Without it the
    # installer refuses to start and an installed guest stops passing its own
    # health checks.
    swtpm
    swtpm-tools

    # THE SHARED FOLDER. virtiofsd is a separate process libvirt launches per
    # share; the <filesystem driver type='virtiofs'> element is useless without
    # it. On the NixOS side this is virtualisation.libvirtd.qemu.vhostUserPackages.
    virtiofsd

    # The GUI, and virt-install for anything scripted.
    virt-manager
    virt-install
)

if (( ! GO )); then
    note "would install:"; printf '    %s\n' "${PKGS[@]}"
    note "would enable libvirtd and add $TARGET_USER to the libvirt group"
    note "would define the macvtap 'lan' network on $NIC"
    note "would set LIBVIRT_DEFAULT_URI=qemu:///system in /etc/environment"
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

note "installing"
dnf -y install "${PKGS[@]}"

note "enabling libvirtd"
systemctl enable --now libvirtd

# THE GROUP IS WHAT MAKES virsh WORK WITHOUT sudo, by way of polkit: libvirt
# ships a rule granting the libvirt group access to the system URI. A session
# that started before the group existed does not have it - log out and in.
note "adding $TARGET_USER to the libvirt group"
usermod -aG libvirt "$TARGET_USER"

# --- the LAN network ---------------------------------------------------------
#
# A MACVTAP POOL ON THE PHYSICAL NIC, so a guest appears directly on
# 192.168.10.0/24 and takes an address from the house router. The laptop and
# everything else then reach it by its own IP, with no port forwarding.
#
# WHAT MACVTAP CANNOT DO is let the guest talk to THIS host. Traffic leaves on
# the physical link and the host never sees it return - kernel behaviour, not a
# mistake here. Host-to-guest needs a real br0 with eno1 enslaved, which costs
# the host its link on every change. libvirt's NAT 'default' network stays
# available for anything that would rather have that trade.
#
# THE UUID IS PINNED, and it is the SAME uuid the NixOS side uses, so both
# systems describe one network rather than two that happen to share a name.
# Without a uuid in the XML, libvirt generates one on first define and then
# refuses every later define that disagrees:
#
#   error: operation failed: network 'lan' already exists with uuid 56d0412b-...
#
# With it written down, defining an existing network updates it instead, which
# is what makes this script safe to re-run.
note "defining the macvtap 'lan' network on $NIC"
install -d -m 0755 /etc/libvirt/fd44-networks
cat > /etc/libvirt/fd44-networks/lan.xml <<LAN
<network>
  <name>lan</name>
  <uuid>56d0412b-a04e-4ed0-9d1a-2dfe10622064</uuid>
  <forward mode="bridge">
    <interface dev="$NIC"/>
  </forward>
</network>
LAN
virsh net-define /etc/libvirt/fd44-networks/lan.xml

for n in default lan; do
    virsh net-autostart "$n" || warn "could not autostart $n"
    if ! virsh net-list --name | grep -qx "$n"; then
        virsh net-start "$n" || warn "could not start $n"
    fi
done

# --- the virtiofsd wrapper ----------------------------------------------------
#
# WHAT GOES WRONG WITHOUT IT. virtiofsd runs as root and a virtiofs share is
# accessmode='passthrough', so whatever uid and gid the guest claims are written
# straight onto the host's files. The Windows virtio-fs driver claims 301:67,
# which exists on no Fedora system - so the moment the guest touched the share
# directory, it became owned by a phantom account:
#
#   drwxrwsr-x. 1 301 67   /home/vms/share
#
# Mode 2775 gives the owner and the group write access, and the host user is
# neither, so it fell through to "other" and could no longer write to its own
# share. Found that way on 2026-10-08; a 165 GB image written by the guest three
# days earlier had the same ownership.
#
# THE FIX IS A WRAPPER BECAUSE LIBVIRT HAS NO XML FOR IT. virtiofsd grew
# --translate-uid in 1.x; libvirt 12's <binary> element still exposes only
# cache, sandbox, locking and the thread pool. Pointing <binary path=.../> at a
# script that re-execs the real binary with the flags added is the way round,
# and libvirt passes its own arguments through untouched.
#
# squash-guest maps a RANGE of guest ids onto ONE host id, so every id the guest
# can present lands as the desktop user. 65536 is far past anything a Windows
# guest reports.
#
# THE DOMAIN IS NOT EDITED HERE. This stage deliberately defines no guest - see
# the note at the top - so it installs the wrapper and prints the one line to
# add. A guest migrated from the NixOS side gets it when its XML is written.
note "installing the virtiofsd wrapper"

VIRTIOFS_WRAP=/usr/libexec/fd44-virtiofsd
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"

cat > "$VIRTIOFS_WRAP" <<WRAPPER
#!/bin/sh
# Installed by install/fedora_virt.sh - see the note there for why this exists.
#
# Everything the guest writes lands on the host owned by $TARGET_USER, whatever
# uid or gid the guest claims. Without this, virtiofsd faithfully applies the
# guest's ids, and a Windows guest claims 301:67 - which exists nowhere here.
exec /usr/libexec/virtiofsd \\
    --translate-uid "squash-guest:0:$TARGET_UID:65536" \\
    --translate-gid "squash-guest:0:$TARGET_GID:65536" \\
    "\$@"
WRAPPER
chmod 0755 "$VIRTIOFS_WRAP"

# SELinux: libvirt will not execute it without virtiofsd's own label. They are
# both bin_t on Fedora 44, but taking it from the real binary keeps this true if
# the policy ever gives virtiofsd a type of its own.
if command -v chcon >/dev/null 2>&1 && [[ -e /usr/libexec/virtiofsd ]]; then
    chcon --reference=/usr/libexec/virtiofsd "$VIRTIOFS_WRAP" 2>/dev/null || true
    if command -v semanage >/dev/null 2>&1; then
        _t="$(stat -c %C /usr/libexec/virtiofsd | cut -d: -f3)"
        semanage fcontext -a -t "$_t" "$VIRTIOFS_WRAP" 2>/dev/null \
            || semanage fcontext -m -t "$_t" "$VIRTIOFS_WRAP" 2>/dev/null || true
    fi
fi
ls -lZ "$VIRTIOFS_WRAP" | sed 's/^/  /'

# --- the default libvirt URI -------------------------------------------------
#
# A bare `virsh` run by a normal user talks to qemu:///session, the per-user
# daemon, which has no domains. A command meant for the system guests then fails
# with
#
#   error: failed to get domain 'win11'
#
# which reads as "no such guest" rather than "I looked somewhere else".
#
# /etc/environment, NOT /etc/profile.d: pam_env reads it for every session,
# graphical ones included, so virt-manager and anything started from the desktop
# see it too. A profile script would only reach login shells. This matches the
# reach of environment.sessionVariables on the NixOS side, which sets the same
# variable.
note "setting LIBVIRT_DEFAULT_URI system-wide"
if ! grep -q '^LIBVIRT_DEFAULT_URI=' /etc/environment 2>/dev/null; then
    printf 'LIBVIRT_DEFAULT_URI=qemu:///system\n' >> /etc/environment
fi
grep '^LIBVIRT_DEFAULT_URI=' /etc/environment | sed 's/^/  /'

printf '\n'
note "done"
printf '  %-14s %s\n' "libvirtd"  "$(systemctl is-active libvirtd)"
printf '  %-14s %s\n' "qemu-kvm"  "$(rpm -q --qf '%{VERSION}' qemu-kvm)"
printf '  %-14s %s\n' "networks"  "$(virsh net-list --name | tr '\n' ' ')"
printf '  %-14s %s\n' "machines"  "$(/usr/bin/qemu-system-x86_64 -M help | grep -c q35) q35 types"
printf '\n'
warn "LOG OUT AND BACK IN before using virt-manager - the libvirt group only"
warn "reaches a session that started after it was granted."
printf '\n'
note "for a guest with a virtiofs share, add this inside its <filesystem>:"
printf "  <binary path='%s'/>\n" "$VIRTIOFS_WRAP"
printf '  %s\n' "without it the guest's own uid/gid land on the host's files -"
printf '  %s\n' "see the virtiofsd wrapper note in this script"
