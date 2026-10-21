# FreeBSD 15.1 installer: plan and feasibility

Written 2026-10-21. Scopes a FreeBSD 15.1 installer built **the same way** as
`install/install_fedora.sh` — the same wizard / preflight / dry-run / staged
shape — and is honest about which parts port cleanly and which are a genuine
rewrite or an open risk. No code yet: this exists so the real decisions are made
before 3000 lines are, the way `gentoo-gaming00-plan.md` did for that build.

Target: **FreeBSD 15.1 + ZFS (boot environments) + EFI + a Wayland desktop**,
developed and tested in a VM first.

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
| getty autologin + uwsm | FreeBSD `gettytab` autologin + a Wayland launch from the shell profile | no uwsm; hand-roll the session start |
| Plymouth graphical boot | no real equivalent | loader has a splash/logo but nothing like Plymouth; likely dropped |
| NVIDIA (already dropped — AMD target) | **`drm-kmod`** (`amdgpu` via `kldload amdgpu`) | AMD works; see Risks for the GPU/KMS detail |

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
| `fedora_desktop.sh` — GPU + desktop on the booted system | `freebsd_desktop.sh` — `drm-kmod` + Wayland + bar | **low — see Risks** |
| compositor config (niri/Hyprland/Plasma) | **compositor swap likely required** | **low** |

The dividing line is exactly where the Fedora pipeline already splits: the base
system is solid ground; the desktop is the unknown.

## Risks — the desktop and the hardware, stated plainly

The base-system installer is high-confidence. Everything below is why the
*desktop* half is scoped separately and gets real-hardware proof before trust.

- **niri on FreeBSD: no evidence it runs at all.** Rust + smithay; smithay's
  FreeBSD support is unestablished. Treat as a non-starter until proven.
- **Hyprland on FreeBSD:** a ports entry exists but looks dated (it still
  describes the wlroots base Hyprland left behind at 0.42 for aquamarine).
  Uncertain; do not assume.
- **Working Wayland on FreeBSD today is sway / labwc** (wlroots 0.20 is current
  and ports well). So a FreeBSD fd44 almost certainly means **a different
  compositor**: the `quickshell` bar (Qt) may port, but the niri/Hyprland KDL/conf
  does not. Scope it as **"FreeBSD + sway (or labwc) + quickshell"**, not a niri
  port. This is the single biggest design change from the Linux builds.
- **Wi-Fi (Framework MT7922):** 15.1's LinuxKPI-7.0 wireless *may* now cover
  mt76/mt7921, but MediaTek via LinuxKPI has been weak historically. **Verify on
  real hardware before promising networking.** Plan for a wired/USB-ethernet
  fallback during install regardless.
- **amdgpu / KMS:** `drm-kmod` supports the Framework's AMD graphics and is one
  of FreeBSD's better-supported paths, but KMS load timing and the exact GPU
  generation need checking on the actual machine.
- **Suspend/resume:** rougher than Linux on this laptop; the s2idle/deep tuning
  from the Linux side does not carry. Do not promise working sleep.
- **Fingerprint, and other Framework niceties:** assume unsupported.

## Decisions to make before any code

1. **ZFS layout** — pool name, dataset tree, and the boot-environment root
   (`zroot/ROOT/default`). This is the FreeBSD analogue of the btrfs subvolume
   layout the Fedora script argued over, and it deserves the same care.
2. **Encryption** — ZFS native (per-dataset, BE-friendly) vs GELI (whole-disk,
   LUKS-like). Pick one; the prompt-at-boot discipline is the same either way.
3. **bsdinstall-scripted vs manual** — per the section above.
4. **Compositor** — sway or labwc. This decides how much of the quickshell
   layer survives and how much is rewritten.
5. **Scope of v1** — recommend: ship the **base installer** first (high
   confidence, useful on its own, testable entirely in the VM), and treat the
   desktop as a separate milestone gated on real-hardware Wi-Fi/GPU/suspend
   results.

## What does NOT port

- Plymouth, uwsm, systemd-anything.
- The hibernation path.
- The niri and Hyprland configurations (compositor swap).
- The NVIDIA handling (already absent — AMD target), and the Linux suspend tuning.

## First concrete step

Stand up a FreeBSD 15.1 VM on the `vmtest` rig, do **one manual install by hand**
(gpart → zpool → base.txz → bectl → rc.conf → pkg), writing down every command.
That transcript becomes the skeleton of `install_freebsd.sh`, exactly as the
first by-hand Gentoo install became `bin/gentoo-*.sh`. Nothing here is committed
to until that by-hand install has booted in the VM.
