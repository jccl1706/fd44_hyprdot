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
#
# DRM_QXL=m LOOKS ABSURD AND IS NOT. nvidia-drivers refuses to build without
# CONFIG_DRM_TTM_HELPER, which has no menu entry of its own - it is only ever
# `select`ed by a DRM driver. With every in-tree DRM driver disabled (which is
# the point, for an nvidia box) nothing selects it, and the ebuild stops with:
#
#   CONFIG_DRM_TTM_HELPER: is not set but is needed to compile when using
#   kernel version 6.11.x or newer while DRM_FBDEV_EMULATION is set
#
# The ebuild suggests DRM_QXL=m, DRM_AMDGPU=m or DRM_NOUVEAU=m. QXL is a QEMU
# virtual GPU: the smallest of the three, and it physically cannot bind to
# anything in this machine. NOUVEAU would also work as a module but is the one
# driver that actively fights nvidia, and AMDGPU is large and pointless on a
# CPU with no integrated graphics.
GPU=(DRM DRM_FBDEV_EMULATION DRM_SIMPLEDRM FB SYSFB_SIMPLEFB X86_PAT
     AGP MTRR)
GPU_TTM_HELPER_SHIM=(DRM_QXL)

# --- network: RTL8125 wired, MT7922 wireless ------------------------------
NET=(R8169 WLAN RFKILL)

# ANYTHING THAT NEEDS FIRMWARE MUST BE A MODULE, not built in - unless you
# also build an initramfs carrying the firmware, which a hand-tailored kernel
# exists partly to avoid.
#
# Found the hard way: MT7921E=y probed at 5.5 seconds, before / was mounted,
# so /lib/firmware did not exist and the load failed:
#
#   mt7921e: Direct firmware load for mediatek/WIFI_RAM_CODE_MT7922_1.bin failed
#
# The firmware was installed and correct the whole time. Rebinding the device
# by hand after boot loaded it immediately and the interface appeared, which
# is what proved the cause was timing rather than a missing file. As a module
# it is loaded after the root filesystem is up and simply works.
# CFG80211 IS ON THIS LIST TOO, and net-wireless/wireless-regdb says so in its
# own post-install message: "With CONFIG_CFG80211=y (built-in), the driver(s)
# won't be able to load regulatory.db from /lib/firmware, resulting in broken
# regulatory domain support." Same failure as the MT76 stack, one layer up -
# without regulatory.db the card falls back to world-wide settings and loses
# 5 GHz channels and transmit power. MAC80211 follows CFG80211 because it
# depends on it.
NEEDS_FIRMWARE_SO_MODULE=(CFG80211 MAC80211
                          MT76_CORE MT76_CONNAC_LIB MT792x_LIB
                          MT7921_COMMON MT7921E)

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

# --- netfilter -------------------------------------------------------------
#
# Found when libvirtd refused to start: "modprobe: FATAL: Module ip_tables not
# found". libvirt's default network is NAT, which it builds out of iptables
# rules, so with no netfilter in the kernel the daemon cannot come up at all.
#
# This is also why this machine had no firewall. The earlier audit recorded
# "no firewall tooling installed", which was true but shallow - the kernel
# could not have run one.
#
# Both backends: nftables is what a firewall would be written in today, and
# iptables-legacy is what libvirt still reaches for by default.
NETFILTER_CORE=(NETFILTER NETFILTER_ADVANCED NF_CONNTRACK NF_NAT
                NETFILTER_XTABLES NF_TABLES NF_TABLES_INET
                NFT_CT NFT_NAT NFT_MASQ NFT_REJECT NFT_LOG NFT_LIMIT
                IP_NF_IPTABLES IP_NF_FILTER IP_NF_NAT IP_NF_MANGLE
                IP_NF_TARGET_MASQUERADE IP_NF_TARGET_REJECT
                IP6_NF_IPTABLES IP6_NF_FILTER IP6_NF_NAT
                XT_MATCH_CONNTRACK XT_MATCH_COMMENT XT_MATCH_ADDRTYPE
                XT_TARGET_MASQUERADE XT_TARGET_CHECKSUM XT_TARGET_LOG
                BRIDGE_NETFILTER NF_CONNTRACK_FTP NF_NAT_FTP)

# fq_codel: /usr/lib/sysctl.d/50-default.conf asks for it and the kernel had no
# modern qdisc at all, so it silently stayed on pfifo_fast. The sysctl line is
# prefixed "-" so the failure is ignored by design and never surfaced as an
# error. fq_codel is what keeps a download from adding latency to everything
# else, which on a machine that games while something is pulling packages is
# worth more than it sounds.
QDISC=(NET_SCH_FQ_CODEL NET_SCH_FQ)

# --- KVM guests ------------------------------------------------------------
#
# KVM itself is already built in (KVM=y, KVM_AMD=y), so /dev/kvm exists and a
# guest will boot - but with no network. libvirt's default NAT network needs a
# tap device, and without TUN it cannot be created at all, leaving QEMU's slow
# user-mode networking as the only option. Found by checking before installing
# rather than after the first guest came up isolated.
#
# TUN       tap devices, what every libvirt network is built on
# BRIDGE    bridged networking, for guests on the LAN rather than behind NAT
# VHOST_NET kernel-side virtio-net; without it the datapath goes through
#           userspace QEMU and throughput drops sharply
VIRT_GUEST_MODULE=(TUN BRIDGE VHOST_NET MACVTAP)

# VFIO is for passing real PCI devices to a guest. Built as modules so the
# option exists without committing to it: this machine has a single GPU, so
# passing the 5090 through would leave the host blind unless the 9800X3D's
# integrated GPU is enabled in BIOS first ("iGPU Multi-Monitor").
VFIO_MODULE=(VFIO VFIO_PCI VFIO_IOMMU_TYPE1)

# --- filesystems for removable media --------------------------------------
#
# defconfig gives vfat and iso9660 but not these, and nothing reports the gap:
# the drive simply will not mount, with "unknown filesystem type". Found when a
# Samsung T5 formatted exFAT could not be mounted.
#
# exfat   - every USB drive and SD card over 32 GB ships formatted this way
# ntfs3   - the in-kernel NTFS driver, for drives shared with Windows
# udf     - DVDs, and some large USB drives
#
# As modules: they are needed only when such a drive is attached, and the NLS
# codepages they translate filenames through are already built in.
REMOVABLE_FS_MODULE=(EXFAT_FS NTFS3_FS UDF_FS)

# --- zram, for compressed swap in RAM -------------------------------------
#
# A desktop with 30 GiB and no swap does not slow down under pressure, it
# OOM-kills - which during a large emerge means losing hours of compiling to
# a single greedy linker. zram gives the kernel somewhere to put cold pages at
# the cost of some CPU, which this machine has in abundance.
#
# ZRAM as a module so its parameters can be set at load time; ZSMALLOC and the
# zstd crypto backend are what it compresses with.
ZRAM=(ZSMALLOC CRYPTO_ZSTD ZRAM_DEF_COMP_ZSTD)
ZRAM_MODULE=(ZRAM)

# --- things a desktop needs that defconfig does not turn on ---------------
DESKTOP=(FUSE_FS TMPFS TMPFS_POSIX_ACL CGROUPS NAMESPACES
         NTSYNC                       # Wine/Proton sync primitive
         BINFMT_MISC
         IKCONFIG IKCONFIG_PROC)      # so /proc/config.gz exists next time

# --- must be OFF ----------------------------------------------------------
DISABLE=(DRM_NOUVEAU)

ALL=("${STORAGE[@]}" "${PLATFORM[@]}" "${GPU[@]}" "${NET[@]}"
     "${AUDIO[@]}" "${USBHID[@]}" "${DESKTOP[@]}" "${ZRAM[@]}")

cmd_apply() {
    [[ -f .config ]] || die "no .config - run 'make defconfig' first"
    cp .config .config.before-fd44
    say "enabling ${#ALL[@]} symbols"
    local s; for s in "${ALL[@]}"; do "$CFG" --enable "$s"; done
    say "as MODULES: ${#NEEDS_FIRMWARE_SO_MODULE[@]} that load firmware"
    for s in "${NEEDS_FIRMWARE_SO_MODULE[@]}"; do "$CFG" --module "$s"; done
    say "as a MODULE: ${#GPU_TTM_HELPER_SHIM[@]} only to select DRM_TTM_HELPER for nvidia"
    for s in "${GPU_TTM_HELPER_SHIM[@]}"; do "$CFG" --module "$s"; done
    say "as a MODULE: ${#ZRAM_MODULE[@]} so its parameters can be set at load"
    for s in "${ZRAM_MODULE[@]}"; do "$CFG" --module "$s"; done
    say "as a MODULE: ${#REMOVABLE_FS_MODULE[@]} filesystems for removable media"
    for s in "${REMOVABLE_FS_MODULE[@]}"; do "$CFG" --module "$s"; done
    say "built IN: ${#NETFILTER_CORE[@]} netfilter symbols - libvirt NAT and any firewall"
    for s in "${NETFILTER_CORE[@]}"; do "$CFG" --enable "$s"; done
    say "built IN: ${#QDISC[@]} queueing disciplines"
    for s in "${QDISC[@]}"; do "$CFG" --enable "$s"; done
    say "as a MODULE: ${#VIRT_GUEST_MODULE[@]} for KVM guest networking"
    for s in "${VIRT_GUEST_MODULE[@]}"; do "$CFG" --module "$s"; done
    say "as a MODULE: ${#VFIO_MODULE[@]} for PCI passthrough, available but unused"
    for s in "${VFIO_MODULE[@]}"; do "$CFG" --module "$s"; done
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
    say "firmware-loading drivers must be =m, not =y"
    for s in "${NEEDS_FIRMWARE_SO_MODULE[@]}"; do
        v="$(grep -E "^CONFIG_${s}=" .config | head -1 || true)"
        case "$v" in
            *=m) printf '    %-24s %s\n' "$s" "m  ok" ;;
            *=y) printf '    %-24s \033[1;31my  WRONG - will probe before /lib/firmware exists\033[0m\n' "$s" ;;
            *)   printf '    %-24s not set\n' "$s" ;;
        esac
    done
    printf '\n'
    for s in "${ALL[@]}" "${NEEDS_FIRMWARE_SO_MODULE[@]}"; do
        v="$(grep -E "^CONFIG_${s}=" .config | head -1 || true)"
        if [[ -n $v ]]; then ok=$((ok+1)); else missing+=("$s"); fi
    done
    say "$ok of $(( ${#ALL[@]} + ${#NEEDS_FIRMWARE_SO_MODULE[@]} )) enabled"
    if (( ${#missing[@]} )); then
        printf '\n  NOT SET - each is a symbol whose dependencies were not met,\n'
        printf '  or which does not exist in this kernel version:\n'
        printf '    %s\n' "${missing[@]}"
        printf '\n  Check each in menuconfig with / before assuming it does not matter.\n'
    fi
    printf '\n'
    say "the ones that must be right"
    local c
    for c in BLK_DEV_NVME BTRFS_FS VFAT_FS DRM_NOUVEAU DRM_TTM_HELPER SND_USB_AUDIO \
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
