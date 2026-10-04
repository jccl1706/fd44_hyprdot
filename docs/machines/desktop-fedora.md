# Gaming desktop — Fedora

`fedora-gaming00`, on the desktop's **Crucial P3 Plus** NVMe, beside NixOS on the
Samsung. Fedora 44 with a deliberately small KDE Plasma, systemd-boot, no LUKS,
and the NVIDIA driver from RPM Fusion.

It replaced Gentoo on 2026-10-04. Gentoo ran here from 2026-09-29 and was
dropped; what was worth keeping from it is on the Samsung T5 under
`gentoo-keepsakes/`, which carries its own README.

## the two disks

Both are 4 TB and **their kernel names swap between boots** — `nvme0n1` and
`nvme1n1` have changed places more than once on this machine, on the same day.
Size does not tell them apart either. Only the model and serial do:

| | |
|---|---|
| `Samsung SSD 990 PRO 4TB`, serial `S7KGNJ0X134514R` | NixOS — `NIXESP`, `NIXROOT`, `NIXHOME` |
| `CT4000P3PSSD8`, serial `2401E88BCC0A` | Fedora — `FEDESP`, `FEDROOT` |

Everything in the installer names disks by `/dev/disk/by-id/`, and it refuses a
`/dev/nvmeXn1` path outright. That is not fussiness: a script that partitioned
"the second drive" by name would have destroyed the running system on one of
those two days.

## the layout

```
FEDESP    1 GiB   vfat   -> /boot      the EFI System Partition
FEDROOT   rest    ext4   -> /
```

**`/boot` IS the ESP.** Fedora's `kernel-install` writes Boot Loader
Specification entries to `/boot/loader/entries`, and systemd-boot reads them only
from the EFI System Partition — so the two are the same filesystem. Fedora's
traditional separate `/boot` plus `/boot/efi` needs `sdubby` to copy entries
across, which is one more thing to go wrong. This matches how NixOS is arranged
on the other disk.

**No swap partition.** 30 GiB of RAM, Fedora's zram by default, and nothing on
this machine hibernates.

**No LUKS**, matching the NixOS disk beside it. Neither system is encrypted, so
physical access is physical access.

## installing it from nothing

Four stages, all run from the **running NixOS on the other disk** except the
last. There is no install medium: it is a partition table, `dnf5 --installroot`,
and a chroot.

| | |
|---|---|
| `install/install_fedora_desktop.sh` | partition and format. Refuses anything but a by-id path, refuses a disk carrying a mounted filesystem, and asks for the disk's **serial** typed out |
| `install/fedora_bootstrap.sh` | `@core` plus a named list into the installroot, with Fedora's own signing keys |
| `install/fedora_chroot.sh` | fstab, identity, user, systemd-boot, the kernel, and the SELinux labelling |
| `install/fedora_desktop.sh` | runs **on Fedora**: RPM Fusion, NVIDIA, KDE, tools |

Each is dry by default and takes `--go`.

## what it taught

Every one of these cost a broken boot or a rescue, and each is written into the
script that hit it.

**`chroot` passes the caller's `PATH` through.** Inside the chroot it still
pointed at `/run/current-system/sw/bin`, so `bootctl` was "not found" while
sitting in `/usr/bin`. Everything now goes through one helper with `env -i`.

**`mount --rbind` inherits shared propagation**, so a later `umount -R` travels
back and unmounts the *originals*. It took `/sys/firmware/efi/efivars`,
`/sys/kernel/debug` and — worst — `/run/wrappers` off the **running** NixOS.
`/run/wrappers` holds the setuid `unix_chkpwd` that `pam_unix` executes, so every
ssh login then failed with *"Access denied by PAM account configuration"* on a
machine whose accounts were fine. `--make-rslave` fixes it, and must be applied
to binds **inherited from a previous run** too.

**`bootctl install` writes a firmware entry and puts itself first.** Run against
a tree with no kernel yet, the next boot reached no operating system at all and
the machine had to be rescued through the firmware menu. It now runs with
`--no-variables`.

**`kernel-install` inherits the running system's `/proc/cmdline`** when
`/etc/kernel/cmdline` is absent — and `/proc` in the chroot is the host's. The
first working entry carried NixOS's `init=/nix/store/...`, which would have
panicked. The command line is written explicitly now.

**`/.autorelabel` cannot fix an unlabelled install.** It is run *by* systemd, and
systemd cannot start without labels: *"Failed to allocate manager object"* after
several hundred denials. `setfiles` works offline against `file_contexts` and
needs no loaded policy, which is why Anaconda runs it at install time.

**Fedora's Recommends are not decoration.** `install_weak_deps=False` produced a
273-package system and four failures, each a long way from its cause:

| missing | how it presented |
|---|---|
| `selinux-policy-targeted` | systemd would not start at all |
| `systemd-pam` | black screen, crash inside NVIDIA's EGL — the driver was fine |
| `chrony` | no NTP at all; a silently drifting clock |
| `cracklib-dicts` | `passwd` stopped checking passwords |

Weak dependencies are left on now. The install is still small because the
**package list** is small — `@core` plus a dozen named things rather than a
desktop group.

## the result

```
Fedora Linux 44        kernel 7.2.8-200.fc44
1188 packages, 5.6 GB  (a Fedora KDE spin is roughly 1800)
SELinux Enforcing      sddm, Plasma on Wayland
NVIDIA via akmod       nvidia_drm.modeset=1 nvidia_drm.fbdev=1
0 failed units         boot 32s, 17s of it firmware
```

## still to do

- **No backups.** This machine is not in the rotation; see [backup.md](../backup.md).
- **The fd44 desktop is not installed here** — no quickshell, no `theme.sh`, no
  keybinds. This is a stock KDE.
- **It shares `192.168.10.158` with NixOS**, so ssh reports a changed host key
  every time you switch. Both are called `Linux Boot Manager` in the firmware
  menu too; tell them apart by the disk.
