#!/usr/bin/env bash
# =========================================================================
# gentoo-kernel-config.sh - turn a defconfig into one that boots THIS box
# =========================================================================
#
# Usage:  bin/gentoo-kernel-config.sh apply  [/usr/src/linux]
#         bin/gentoo-kernel-config.sh verify [/usr/src/linux]
#
# WHY NOT localmodconfig. It prunes an existing config against a RUNNING
# kernel's module list. Run against a foreign kernel's /proc/modules on top of
# a bare defconfig it produced a config with no NVMe and no btrfs - a kernel
# that cannot see its own disk, let alone mount it. It is the right tool when
# you already have a working config for the same kernel, and the wrong one
# here.
#
# So: defconfig as the base, then every driver this machine actually needs
# turned on by name, then `make olddefconfig` to settle dependencies, then
# CHECK WHAT ACTUALLY TOOK. That last step is the point - `scripts/config
# --enable` happily writes a symbol whose dependencies are unmet, kconfig
# drops it on the next regeneration, and nothing says a word.
#
# Every entry below maps to a device seen on this machine with lspci -k or
# lsusb, not to a guess about what a desktop needs.

set -euo pipefail
name="${0##*/}"
die() { printf '%s: %s\n' "$name" "$*" >&2; exit 1; }
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

SRC="${2:-/usr/src/linux}"
[[ -f "$SRC/Makefile" ]] || die "no kernel tree at $SRC"
cd "$SRC"
CFG=./scripts/config

# --- storage: without these the machine does not boot ---------------------
STORAGE=(BLK_DEV_NVME NVME_CORE SATA_AHCI ATA ATA_PIIX BLK_DEV_SD
         BTRFS_FS BTRFS_FS_POSIX_ACL EXT4_FS VFAT_FS FAT_FS MSDOS_FS
         NLS_CODEPAGE_437 NLS_ISO8859_1 NLS_UTF8)

# --- AMD Zen 5 / B850 platform --------------------------------------------
# X86_AMD_PSTATE_DEFAULT_MODE is an int, not a bool - `--enable` on it writes
# 'y' and kconfig warns "symbol value 'y' invalid". It is left out; the
# default mode is already the active one Fedora uses.
#
# EDAC_AMD64 needs EDAC, AMD_NB, AMD_NODE and EDAC_DECODE_MCE. It reports ECC
# DRAM errors, which this machine's non-ECC consumer DDR5 cannot produce, so
# it is listed last and costs nothing if it still does not take.
PLATFORM=(X86_AMD_PSTATE AMD_3D_VCACHE
          SENSORS_K10TEMP SENSORS_NCT6775 CRYPTO_DEV_CCP
          CRYPTO_DEV_CCP_DD KVM KVM_AMD PINCTRL_AMD I2C_PIIX4 I2C_CHARDEV
          ASUS_WMI ACPI_WMI AMD_PMC X86_AMD_PLATFORM_DEVICE
          EDAC EDAC_DECODE_MCE AMD_NB AMD_NODE EDAC_AMD64)

# --- the RTX 5090 is out of tree; the kernel only has to stay out of its way
GPU=(DRM DRM_FBDEV_EMULATION DRM_SIMPLEDRM FB SYSFB_SIMPLEFB X86_PAT
     AGP MTRR)

# --- network: RTL8125 wired, MT7922 wireless ------------------------------
NET=(R8169 WLAN CFG80211 MAC80211 MT76_CORE MT76_CONNAC_LIB MT792x_LIB
     MT7921_COMMON MT7921E RFKILL)

# --- audio: AMD HDA, NVIDIA HDA, and the Audient EVO4 over USB ------------
AUDIO=(SOUND SND SND_PCI SND_HDA_INTEL SND_HDA_CODEC_REALTEK
       SND_HDA_CODEC_HDMI SND_USB SND_USB_AUDIO SND_HRTIMER)

# --- USB, input, and the Aquacomputer Quadro ------------------------------
# HID_LOGITECH depends on LEDS_CLASS *and* LEDS_CLASS_MULTICOLOR, which
# defconfig does not set - so it was dropped, and HID_LOGITECH_DJ and
# HID_LOGITECH_HIDPP went with it, silently. Without DJ a Unifying receiver
# works only as a generic mouse: paired devices are not exposed individually.
# The LEDS entries come first so the dependency is met before the driver is
# asked for.
USBHID=(USB_SUPPORT USB USB_XHCI_HCD USB_XHCI_PCI USB_EHCI_HCD
        NEW_LEDS LEDS_CLASS LEDS_CLASS_MULTICOLOR
        HID HID_GENERIC USB_HID HIDRAW
        HID_LOGITECH HID_LOGITECH_DJ HID_LOGITECH_HIDPP
        HWMON SENSORS_AQUACOMPUTER_D5NEXT)

# --- things a desktop needs that defconfig does not turn on ---------------
DESKTOP=(FUSE_FS TMPFS TMPFS_POSIX_ACL CGROUPS NAMESPACES
         NTSYNC                       # Wine/Proton sync primitive
         BINFMT_MISC
         IKCONFIG IKCONFIG_PROC)      # so /proc/config.gz exists next time

# --- must be OFF ----------------------------------------------------------
DISABLE=(DRM_NOUVEAU)

ALL=("${STORAGE[@]}" "${PLATFORM[@]}" "${GPU[@]}" "${NET[@]}"
     "${AUDIO[@]}" "${USBHID[@]}" "${DESKTOP[@]}")

cmd_apply() {
    [[ -f .config ]] || die "no .config - run 'make defconfig' first"
    cp .config .config.before-fd44
    say "enabling ${#ALL[@]} symbols"
    local s; for s in "${ALL[@]}"; do "$CFG" --enable "$s"; done
    say "disabling ${#DISABLE[@]}"
    for s in "${DISABLE[@]}"; do "$CFG" --disable "$s"; done
    say "make olddefconfig - settles dependencies"
    make olddefconfig >/dev/null
    say "done - now run '$name verify' and read it"
    printf '  previous config kept as .config.before-fd44\n'
}

cmd_verify() {
    [[ -f .config ]] || die "no .config"
    local s v ok=0 missing=()
    printf '\n'
    for s in "${ALL[@]}"; do
        v="$(grep -E "^CONFIG_${s}=" .config | head -1 || true)"
        if [[ -n $v ]]; then ok=$((ok+1)); else missing+=("$s"); fi
    done
    say "$ok of ${#ALL[@]} enabled"
    if (( ${#missing[@]} )); then
        printf '\n  NOT SET - each is a symbol whose dependencies were not met,\n'
        printf '  or which does not exist in this kernel version:\n'
        printf '    %s\n' "${missing[@]}"
        printf '\n  Check each in menuconfig with / before assuming it does not matter.\n'
    fi
    printf '\n'
    say "the ones that must be right"
    local c
    for c in BLK_DEV_NVME BTRFS_FS VFAT_FS DRM_NOUVEAU SND_USB_AUDIO \
             SENSORS_AQUACOMPUTER_D5NEXT MT7921E R8169 NTSYNC; do
        printf '    %-32s %s\n' "$c" \
            "$(grep -E "^(CONFIG_${c}=|# CONFIG_${c} )" .config | head -1 || echo 'ABSENT')"
    done
}

case "${1:-}" in
    apply)  cmd_apply  ;;
    verify) cmd_verify ;;
    *) die "usage: $name [apply|verify] [kernel-tree]" ;;
esac
