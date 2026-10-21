# FreeBSD 15.1 installer: plan and feasibility

Written 2026-10-21. Scopes a FreeBSD 15.1 installer built **the same way** as
`install/install_fedora.sh` — the same wizard / preflight / dry-run / staged
shape — and is honest about which parts port cleanly and which are a genuine
rewrite or an open risk. No code yet: this exists so the real decisions are made
before 3000 lines are, the way `gentoo-gaming00-plan.md` did for that build.

Target: **FreeBSD 15.1 + ZFS (boot environments) + EFI + KDE Plasma**,
developed and tested in a VM first.

The desktop choice is **KDE Plasma**, and that is a deliberate de-risking: KDE is
one of FreeBSD's flagship, actively-maintained desktops (the KDE-FreeBSD project,
730 ports, Plasma 6.6.3+ tracking upstream), where niri and Hyprland have no
credible FreeBSD story. It also maps straight onto the `--plasma` branch
`install_fedora.sh` already has, and it dissolves the quickshell question — Plasma
ships its own panel and shell, so there is no tiling-compositor bar to port.

FreeBSD 15.1 is real — released 2026-06-16, the second release on stable/15,
carrying LinuxKPI wireless based on Linux 7.0 (which is the only reason the
Framework's Wi-Fi is even a maybe rather than a no — see Risks).

## Develop it in a VM, not on hardware

There is no spare disk for a FreeBSD install right now (the Framework runs
Fedora/niri; the gaming desktop runs NixOS + Fedora across its two NVMes, both
full). Build and iterate in the installer VM test rig — the `vmtest` alias and
collector already set up on fedora00 for exactly this with `install_fedora.sh`.
A VM also sidesteps, for the base-system work, every hardware risk below; those
get re-tested on real hardware only once the base installer is solid.

## The same disk discipline

Identify the target disk by its **GPT label or diskid, never by `ada0`/`nvd0`**.
FreeBSD device names are as unstable as Linux's `nvme0n1` — enumeration order,
not identity. `install_fedora.sh` keys on `/dev/disk/by-id`; the FreeBSD
equivalent is `/dev/diskid/*` or `/dev/gpt/<label>` after labelling, and
`gpart show` / `geom disk list` to confirm model and serial before any
destructive `gpart` call. Every wipe checks the label first, as the Fedora and
Gentoo scripts do.

## The translation table — this is the core of the port

The *structure* is OS-agnostic bash. Almost every *mechanism* differs. This maps
each thing `install_fedora.sh` does to its FreeBSD counterpart; several are not
just equivalents but improvements.

| Fedora (what the script does) | FreeBSD 15.1 mechanism | notes |
|---|---|---|
| partition with `sgdisk`/`parted` | **`gpart`** (`gpart create -s gpt`, `gpart add`) | GPT, 1 freebsd-boot + EFI + freebsd-zfs |
| btrfs + subvolumes | **ZFS** datasets | native; the right choice |
| btrfs snapshots for rollback | **ZFS boot environments** (`bectl`) | *better* than subvolumes — a BE is a bootable rollback the loader offers at boot |
| systemd-boot (UEFI) | **FreeBSD loader** (`/boot/loader.efi` on the ESP, `gptboot` fallback) | loader.conf, not loader entries |
| optional LUKS2 + LVM | **ZFS native encryption** (preferred) or **GELI** | ZFS encryption is per-dataset and integrates with BEs; GELI is whole-disk, closer to LUKS |
| LUKS passphrase prompted at boot by systemd | loader prompts for the ZFS key / GELI passphrase | never stored, same discipline |
| hibernation (swap on LVM) | **drop it** | FreeBSD suspend/resume on this laptop is unproven; no hibernation story worth promising |
| `dnf5 --installroot` into the target | **`bsdinstall`** (scripted) **or** extract `base.txz` + `kernel.txz` then chroot | FreeBSD has first-class unattended install — see below |
| base system = Fedora packages | base system is **one tarball** (`base.txz`) + kernel | cleaner; the OS and its packages are separate concerns on FreeBSD |
| systemd units (`systemctl enable`) | **`/etc/rc.conf`** entries (`sysrc foo_enable=YES`) | declarative-ish, simpler |
| `dnf install` for everything else | **`pkg install`** (binary) or ports | |
| getty autologin + uwsm (niri/Hyprland path) | **SDDM** (`sddm_enable=YES`) | Plasma's natural display manager; well-supported on FreeBSD. The autologin/uwsm approach was tiling-compositor-specific and does not apply |
| Plymouth graphical boot | no real equivalent | loader has a splash/logo but nothing like Plymouth; likely dropped |
| NVIDIA (already dropped — AMD target) | **`drm-kmod`** (`amdgpu` via `kldload amdgpu`) | AMD works; also the GPU the one positive Plasma-Wayland-on-FreeBSD report used |
| — (Plasma needs these on FreeBSD) | **`dbus`, `seatd`** in rc.conf | seat/session management; Plasma + SDDM want them running |

### bsdinstall scripted vs. manual extract

Two honest options for the base install, and the plan should pick one early:

1. **`bsdinstall` scripted mode** — FreeBSD's native unattended install. A single
   `installerconfig`/script on the media drives partitioning, ZFS, base
   extraction and first-boot config non-interactively. Less code than the Fedora
   script needed, because FreeBSD ships the machinery Fedora lacks. The downside
   is less fine control than hand-rolling.
2. **Manual** — `gpart` + `zpool create` + `tar -xf base.txz kernel.txz` into the
   pool + `chroot` for config. This mirrors `install_fedora.sh`'s hand-built
   approach most exactly and gives total control, at the cost of reimplementing
   what `bsdinstall` already does.

Recommendation: **manual for the ZFS/partition/boot-environment layout**
(where the value and the opinions live), calling into `bsdinstall` subcommands
(`bsdinstall zfsboot`, `bsdinstall mount`) where they save honest work rather
than reimplementing them. Decide and record before coding.

## Stage map (mirrors the Fedora pipeline)

`install_fedora.sh` is a four-stage pipeline. The FreeBSD one keeps the shape:

| Fedora stage | FreeBSD equivalent | confidence |
|---|---|---|
| `install_fedora.sh` — guided bare-metal installer (wizard, preflight, dry-run, partition, base) | `install_freebsd.sh` — same wizard, `gpart` + ZFS + `base.txz` | **high** |
| `fedora_bootstrap.sh` — minimal bootable system from a running Linux | roll into stage 1 or a `freebsd_bootstrap.sh` run from the live installer | **high** |
| `fedora_desktop.sh` — GPU + desktop on the booted system | `freebsd_desktop.sh` — `drm-kmod` + Plasma + SDDM | **medium-high (X11), see Risks** |
| compositor config (niri/Hyprland/Plasma) | Plasma ships its own — **X11 session for v1** | **medium-high** |

KDE moves the desktop from "unknown" to "mostly known": the X11 Plasma session on
FreeBSD is mature. What is left uncertain is the **Wayland** session and the
laptop hardware, below — not the desktop software itself.

## Risks — now the Wayland session and the hardware, not the desktop

Choosing KDE took the desktop *software* off the risk list — the X11 Plasma
session on FreeBSD is mature and well-maintained. What remains is the Plasma
**Wayland** session and the laptop hardware, and these get real-hardware proof
before being trusted.

- **Plasma session: X11 for v1, Wayland aspirational.** The X11 session is the
  known-good path and what the installer should default to. The Wayland session
  *can* work on FreeBSD — the one solid positive report (Phoronix, 2025) was
  specifically an **AMD + drm-kmod + amdgpu + dbus + seatd** setup, which is
  exactly the Framework's GPU — but it is version-sensitive and unreliable (a
  May 2026 Qt 6.11.1 bug blocked the Wayland session while X11 kept working).
  So: ship X11, offer Wayland as an opt-in to test on the real machine, do not
  make it the default until it is proven on this hardware.
- **Wi-Fi (Framework MT7922):** 15.1's LinuxKPI-7.0 wireless *may* now cover
  mt76/mt7921, but MediaTek via LinuxKPI has been weak historically. **Verify on
  real hardware before promising networking.** Plan for a wired/USB-ethernet
  fallback during install regardless.
- **amdgpu / KMS:** `drm-kmod` supports the Framework's AMD graphics and is one
  of FreeBSD's better-supported paths — it is also the GPU stack the working
  Plasma-Wayland report used — but KMS load timing and the exact generation need
  checking on the actual machine.
- **Suspend/resume:** rougher than Linux on this laptop; the s2idle/deep tuning
  from the Linux side does not carry. Do not promise working sleep.
- **Fingerprint, and other Framework niceties:** assume unsupported.

niri and Hyprland are simply not in scope — KDE is the desktop, so their absence
of a FreeBSD story stops being this project's problem.

## Decisions to make before any code

1. **ZFS layout** — pool name, dataset tree, and the boot-environment root
   (`zroot/ROOT/default`). This is the FreeBSD analogue of the btrfs subvolume
   layout the Fedora script argued over, and it deserves the same care.
2. **Encryption** — ZFS native (per-dataset, BE-friendly) vs GELI (whole-disk,
   LUKS-like). Pick one; the prompt-at-boot discipline is the same either way.
3. **bsdinstall-scripted vs manual** — per the section above.
4. **Plasma session type** — X11 (default, mature) with Wayland as an opt-in
   flag to test on real AMD hardware. Not a compositor choice any more; KDE
   settles that.
5. **Display manager** — SDDM (standard for Plasma), with `dbus` and `seatd`
   enabled in rc.conf alongside it.
6. **Scope of v1** — recommend: ship the **base installer + X11 Plasma** first
   (now medium-high confidence, testable largely in the VM), and treat the
   Wayland session and the laptop hardware (Wi-Fi/GPU/suspend) as a separate
   milestone gated on real-hardware results.

## What does NOT port

- Plymouth, uwsm, systemd-anything.
- The hibernation path.
- The niri and Hyprland configurations, and the quickshell bar — Plasma brings
  its own shell and panel, so none of the tiling-WM layer carries over. (A later
  pass could rebuild the fd44 *look* in Plasma, but that is theming, not porting.)
- The NVIDIA handling (already absent — AMD target), and the Linux suspend tuning.

## First concrete step

Stand up a FreeBSD 15.1 VM on the `vmtest` rig, do **one manual install by hand**
(gpart → zpool → base.txz → bectl → rc.conf → pkg → `pkg install` Plasma + SDDM,
with `dbus`/`seatd`/`sddm` enabled), writing down every command. Get the **X11
Plasma session** up first; only then try the Wayland session. That transcript
becomes the skeleton of `install_freebsd.sh`, exactly as the first by-hand Gentoo
install became `bin/gentoo-*.sh`. Nothing here is committed to until that by-hand
install has booted to a Plasma login in the VM.
