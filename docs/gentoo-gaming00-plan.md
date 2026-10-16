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

## Method: a chroot from the running Fedora, not the live ISO

Gentoo installs perfectly well from another running Linux, and here that is the
better choice for two reasons.

**Fedora stays up, so the install can be driven over ssh** from the laptop.
From the ISO every command and every error has to be relayed by hand, and a
Gentoo install produces a great deal of both.

**`make localmodconfig` gets a better reference.** Inside the chroot it reads
`/proc/modules` of the *running* kernel - Fedora's, on this hardware, with the
USB devices actually plugged in. The live ISO boots a generic kernel that loads
a different set, and would miss the EVO4 and the Quadro.

Everything needed is already on that machine: btrfs-progs, mkfs.vfat, chroot,
curl, gpg, tar, sgdisk, parted. 1.7 TB free and 29 GiB of RAM available.

```
1. partition the Samsung  reuse NIXESP as the ESP, btrfs on the rest
2. mount subvolumes       /mnt/gentoo, @root @home @snapshots
3. stage3                 download, verify the signature, untar
4. bind-mount             /proc /sys /dev /dev/pts /run, copy resolv.conf
5. chroot                 from here it is an ordinary handbook install
6. kernel                 localmodconfig against Fedora's lsmod, then prune
7. GRUB                   from inside the chroot, to the Samsung's ESP only
```

**Step 7 is where this method can hurt Fedora, and nowhere else:**

- Use Gentoo's `grub-install` **inside the chroot**, never Fedora's
  `grub2-install` from outside it.
- `--efi-directory` must be the Samsung's ESP. Fedora's is mounted at `/boot`
  on the other disk and must not be written to.
- `efibootmgr` writes firmware NVRAM, which is system-wide rather than
  per-disk. Record `efibootmgr -v` before and after, and confirm the Fedora
  entry survives.

## nvidia suspend/resume on OpenRC: no hook, one module parameter

**The elogind sleep hook written here earlier was wrong for Gentoo**, and is
kept below only as the record of a plan that did not survive contact.

It called `/usr/bin/nvidia-sleep.sh`, which Fedora ships and **Gentoo does
not**. Checked with `qlist x11-drivers/nvidia-drivers`: the only sleep-related
files are four systemd drop-ins, and all four merely set
`SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` to avoid an Xorg deadlock. Nothing
about VRAM, and no script for a hook to call.

The driver can do it without userspace help:

```
# /etc/modprobe.d/nvidia.conf
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_UseKernelSuspendNotifiers=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
```

`UseKernelSuspendNotifiers=1` makes the driver register kernel power
management notifiers and save and restore video memory itself. Fedora sets it
to **0** because it has the userspace path available and prefers it; with no
script on this system, 1 is the setting that fits.

**Verified on 2026-10-16** with `rtcwake -m mem -s 30`:

```
PM: suspend entry (deep) ... PM: suspend exit     a real S3 cycle
same boot_id                                      slept, did not reboot
plasmashell 1995 -> 1995, kwin 1857 -> 1857       the session SURVIVED
RTX 5090, VRAM restored, NVRM errors 0 -> 0
```

The unchanged PIDs are the part that matters: a session that crashed and
restarted looks nearly identical from outside, and only the process IDs
distinguish the two. The driver preserved and restored video memory entirely
in-kernel - no userspace helper, no elogind hook, nothing for OpenRC to
coordinate.

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
