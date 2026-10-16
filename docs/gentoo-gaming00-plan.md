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

## Portage, for this CPU

`-march=znver5` on a 9800X3D. 16 threads and 30 GiB of RAM mean `MAKEOPTS="-j16"`
and `PORTAGE_TMPDIR` on tmpfs are both comfortable. Compile time will not be the
bottleneck on this machine; nvidia and kernel choices will be.

## Still to decide

- Filesystem for the Gentoo root (the Samsung currently has ext4 for NIXROOT
  and NIXHOME)
- Whether to keep a Fedora entry in the Gentoo bootloader, or leave each disk
  booting itself from the firmware menu
- Profile: `default/linux/amd64/23.0/desktop/plasma` with OpenRC
