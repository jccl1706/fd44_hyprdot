# Gentoo on the gaming desktop: hardware survey and install plan

Written 2026-10-16 from a survey of the running Fedora on that machine. Every
hardware line below came from `lspci -k`, `lsmod` or `lscpu` on the box itself,
not from memory. The kernel symbol names did not - see the warning on them.

Target: **Gentoo + OpenRC + KDE Plasma + nvidia + a hand-configured kernel.**

## THE DISK: IDENTIFY IT BY SERIAL, NEVER BY nvme0n1

The two NVMe drives in this machine **swap device names between boots**. They
did it again between 2026-10-15 and 2026-10-16:

| serial | model | holds | on 10-15 | on 10-16 |
| --- | --- | --- | --- | --- |
| `S7KGNJ0X134514R` | Samsung 990 PRO 4TB | NixOS - **the target** | nvme1n1 | nvme0n1 |
| `2401E88BCC0A` | Crucial P3 Plus 4TB | **running Fedora** | nvme0n1 | nvme1n1 |

An installer pointed at "the second NVMe" would have destroyed the working
Fedora system on 2026-10-16. The Samsung carries labels `NIXESP`, `NIXROOT`,
`NIXHOME`; the Crucial carries `FEDESP`, `FEDROOT`. **Check the serial or the
labels before every destructive command**, the way `bin/disk-image.sh` does:

```sh
lsblk -dno NAME,SERIAL | grep S7KGNJ0X134514R
```

The NixOS install on the Samsung is confirmed expendable: its 631 GB of data
was copied to `/home/from-nixos` on the Fedora disk in September and verified.

## Hardware

| part | detail | driver |
| --- | --- | --- |
| CPU | AMD Ryzen 7 9800X3D, Zen 5, 8c/16t | `k10temp`, `amd_3d_vcache`, `amd-pstate-epp` |
| Board | ASUS TUF GAMING B850M-PLUS WIFI, UEFI | `asus_wmi`, `nct6775`, `i2c_piix4`, `gpio_amdpt` |
| Secure Boot | **disabled** - no module signing needed | |
| RAM | 30 GiB | enough for `PORTAGE_TMPDIR` on tmpfs |
| GPU | **NVIDIA RTX 5090**, GB202 Blackwell, `10de:2b85` | `nvidia` **open** 615.71.09 |
| NVMe | Samsung 990 PRO + Crucial P3 Plus | `nvme` |
| SATA | AMD 600 series | `ahci` |
| Ethernet | Realtek RTL8125 2.5GbE | `r8169` |
| Wi-Fi | MediaTek MT7922 | `mt7921e`, `mt76`, `mt792x_lib` + firmware |
| Audio | AMD Ryzen HDA + NVIDIA HDA | `snd_hda_intel` |
| USB audio | **Audient EVO4** | `snd_usb_audio` |
| Fan controller | **Aquacomputer Quadro** `0c70:f00d` | `aquacomputer_d5next` |
| Keyboard | KBDFANS KBD75 | generic HID |
| Mouse | Logitech receiver | `hid_logitech_dj`, `hid_logitech_hidpp` |
| RGB | ASUS AURA `0b05:19af` | none - userspace (OpenRGB) |
| USB | 4x `xhci_hcd` | |
| Other | AMD crypto, KVM | `ccp`, `kvm_amd` |

Everything is supported by mainline Linux. Nothing here needs an out-of-tree
driver except nvidia.

## The three things that will actually bite

**1. Blackwell requires the OPEN kernel modules.** The classic proprietary
module does not support GB202 at all. Fedora is running
`615.71.09 Open Kernel Module` today. On Gentoo this is
`x11-drivers/nvidia-drivers` built as the open variant - not a preference.

**2. "Latest kernel" and nvidia pull against each other.** Mainline releases
land weeks before nvidia supports them. On a binary distro you wait; here you
simply cannot build the module until a compatible `nvidia-drivers` exists. This
is the most likely way to end up without a desktop. Keep a known-good kernel
installed and bootable alongside any new one.

**3. OpenRC has no per-user service manager.** There is no `systemd --user`.
Everything in this repository's `systemd/` - the backup timer, the hourly
wallpaper rotation, the polkit agent with `Restart=on-failure`, udiskie -
has no direct equivalent and becomes cron plus autostart plus your own
supervision. This was raised and accepted deliberately; it is the cost of the
Gentoo-way choice, not an oversight.

Also needed on OpenRC: **elogind** in place of logind, for seats and sessions,
which KDE Plasma requires.

## The kernel

Use `make localmodconfig` on the target, booted from the Gentoo ISO with all
this hardware present. It keeps what `lsmod` shows and disables the rest, which
is a far better starting point than transcribing a list.

**THESE SYMBOL NAMES ARE FROM MEMORY AND WERE NEVER VERIFIED.** Fedora does not
ship `/boot/config-$(uname -r)` on this machine and `/proc/config.gz` does not
exist, so the intended check was impossible. Search for each in `menuconfig`
with `/` rather than trusting the spelling here. The *hardware* behind each one
is verified; the symbol is not.

```
CONFIG_SND_USB_AUDIO                the Audient EVO4
CONFIG_SENSORS_AQUACOMPUTER_D5NEXT  the Quadro fan controller
CONFIG_SENSORS_NCT6775              motherboard sensors
CONFIG_SENSORS_K10TEMP              CPU temperature
CONFIG_NTSYNC                       Wine/Proton sync - wanted on a gaming box
CONFIG_AMD_3D_VCACHE                9800X3D cache scheduling
CONFIG_X86_AMD_PSTATE               amd-pstate-epp
CONFIG_MT7921E and the MT76 stack   Wi-Fi, plus linux-firmware
CONFIG_HID_LOGITECH_DJ / _HIDPP     the Logitech receiver
CONFIG_R8169                        2.5GbE
CONFIG_DRM_NOUVEAU=n                MUST be off or it fights the nvidia module
```

`localmodconfig` will miss anything that was not loaded on the ISO - the EVO4
and the Quadro in particular, since they are USB devices that may not be
plugged in while installing.

## nvidia suspend/resume on OpenRC: one script

The nvidia kernel module does not care what PID 1 is. Loading,
`nvidia_drm.modeset=1`, Wayland and KDE are all udev and modprobe.

**Suspend is the exception.** With `NVreg_PreserveVideoMemoryAllocations=1` the
driver saves VRAM to disk across a suspend, and something must call it at the
right moment. On Fedora that is four systemd units - and
`nvidia-suspend.service` turns out to be a thin wrapper:

```
ExecCondition=grep -qs 'UseKernelSuspendNotifiers: 0' /proc/driver/nvidia/params
ExecStart=/usr/bin/nvidia-sleep.sh "suspend"
```

`/usr/bin/nvidia-sleep.sh` ships with the driver. So on OpenRC this is one
elogind sleep hook, not a port:

```sh
# /lib/elogind/system-sleep/nvidia  (chmod 755)
#!/bin/sh
# $1 is pre|post, $2 is suspend|hibernate|suspend-then-hibernate
grep -qs 'UseKernelSuspendNotifiers: 0' /proc/driver/nvidia/params || exit 0
case "$1/$2" in
    pre/suspend)              /usr/bin/nvidia-sleep.sh suspend   ;;
    pre/hibernate)            /usr/bin/nvidia-sleep.sh hibernate ;;
    pre/suspend-then-hibernate) /usr/bin/nvidia-sleep.sh suspend ;;
    post/*)                   /usr/bin/nvidia-sleep.sh resume    ;;
esac
```

And the modprobe options Fedora uses, which are not init-specific:

```
# /etc/modprobe.d/nvidia.conf
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_UseKernelSuspendNotifiers=0
options nvidia NVreg_TemporaryFilePath=/var/tmp
```

Skipping the hook does not break booting - the failure mode is corrupted VRAM
after a resume. Two of Fedora's five nvidia units need no replacement at all:
`nvidia-persistenced` is already disabled there, and `nvidia-powerd` is Dynamic
Boost, a laptop feature.

## Filesystem: btrfs, not ext4

Chosen for one Gentoo-specific reason. What breaks a source distribution is an
update - a kernel that `nvidia-drivers` does not support yet, a rebuild that
half-finishes, a USE change that cascades. A snapshot before
`emerge -uDN @world` turns each of those from an evening into a reboot.

The usual objection - Portage's small-file I/O under copy-on-write - goes away
when `PORTAGE_TMPDIR` lives on tmpfs, which 30 GiB of RAM makes free. Builds
never touch the disk; only the installed result does.

With GRUB, `sys-boot/grub-btrfs` puts snapshots straight in the boot menu,
which is the safety net a rolling distribution wants. This machine already runs
btrfs on its Fedora root, and `bin/btrfs-scrub-setup.sh` here already knows how
to scrub one - though note that script installs **systemd** units and will need
an OpenRC equivalent.

Layout on the Samsung: reuse the existing 1 GiB `NIXESP` vfat partition as the
ESP, and give the rest to btrfs with subvolumes for `/`, `/home` and
`/.snapshots`.

## Bootloader: GRUB

Chosen over systemd-boot, which would be an odd fit beside OpenRC anyway.
UEFI, Secure Boot is disabled so nothing needs signing. Add `grub-btrfs` for
snapshot entries.

Each disk keeps its own ESP, so Fedora and Gentoo can boot independently from
the firmware menu; whether Gentoo's GRUB should also detect Fedora with
`os-prober` is still open - it is convenient and it is also one more thing that
can rewrite a boot entry you did not ask it to.

## Portage, for this CPU

`-march=znver5` on a 9800X3D. 16 threads and 30 GiB of RAM mean `MAKEOPTS="-j16"`
and `PORTAGE_TMPDIR` on tmpfs are both comfortable. Compile time will not be the
bottleneck on this machine; nvidia and kernel choices will be.

## Decided

- **OpenRC**, deliberately, having been told what it costs - see above
- **btrfs** root with subvolumes, `PORTAGE_TMPDIR` on tmpfs
- **GRUB** plus `grub-btrfs`
- **`plasma-meta` only**, not `kde-apps-meta` - roughly halves the build
- Profile: `default/linux/amd64/23.0/desktop/plasma`, OpenRC variant

## Still to decide

- Whether Gentoo's GRUB runs `os-prober` to find Fedora, or each disk boots
  itself from the firmware menu
- Which `-bin` packages to accept: `rust-bin` and `firefox-bin` save hours and
  cost nothing visible; `qtwebengine` has no binary and is the worst single
  build in a KDE install, so check whether your USE flags actually pull it
