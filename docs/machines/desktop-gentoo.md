# Gaming desktop — Gentoo

`gentoo-gaming00`, on the desktop's second NVMe. Built 2026-09-29; it shares the
hardware with the NixOS install on the other drive and shares nothing else.

| | |
|---|---|
| CPU | Ryzen 7 9800X3D, 16 threads |
| GPU | RTX 5090, 600 W limit |
| RAM | 30 GB |
| disks | Crucial 3.6 TB (`GENTOOROOT`, ext4) · Samsung 3.6 TB (`NIXROOT`, `NIXHOME`) |
| boot | **separate ESP per OS**, chosen from the firmware menu — neither bootloader manages the other |
| profile | `default/linux/amd64/23.0/desktop/systemd` |
| built by | [`install_gentoo.sh`](../../install/install_gentoo.sh) → [`gentoo_chroot.sh`](../../install/gentoo_chroot.sh) → [`gentoo_gaming.sh`](../../install/gentoo_gaming.sh) → [`gentoo_desktop.sh`](../../install/gentoo_desktop.sh) |

`gentoo_enter.sh` re-enters the chroot from another Linux, which is how this
machine was repaired twice without reinstalling.

## Installing it from nothing

**This one installs from a RUNNING LINUX, not from its own installer** — the
prerequisite the other two do not have. On a blank desktop that means either
booting any live ISO (Fedora's will do), or installing NixOS on the other drive
first and running it from there, which is how this machine was built. The script
refuses to install over the system it is running from, so the two can never be
the same disk.

```sh
# from that running Linux, with this repository cloned
sudo install/install_gentoo.sh --disk /dev/disk/by-id/<target> --dry-run
sudo install/install_gentoo.sh --disk /dev/disk/by-id/<target>
```

**By id, never `/dev/nvme0n1`.** The two NVMes in this machine swapped names
between two boots on the same day.

Stage one partitions, fetches and verifies a stage3, and leaves you inside a
chroot. Then, in there, in this order:

| | |
|---|---|
| `gentoo_chroot.sh` | profile, kernel, systemd-boot, network, `CPU_FLAGS_X86` from the real CPU, the daily sync timer |
| `gentoo_gaming.sh` | multilib, the 32-bit NVIDIA stack, Steam, GameMode, the `/dev/uinput` rule |
| `gentoo_desktop.sh` | Hyprland and quickshell from the overlays, fonts, `nvidia_drm modeset`, quiet boot, autologin |

Then `bin/link-dotfiles.sh`, `bin/starship-setup.sh`, and `bin/backup.sh setup`.

`gentoo_enter.sh` re-enters the chroot from another Linux afterwards. It is the
first thing to reach for if this machine ever boots to a prompt it will not
leave — which it has, twice, and both times were repaired that way rather than
reinstalled.

## Portage

```
COMMON_FLAGS  -O2 -pipe -march=native      # GCC 15.3 resolves native to znver5
ABI_X86       64 32                        # native Steam needs a 32-bit userland
CPU_FLAGS_X86 from cpuid2cpuflags          # the full AVX-512 set on this CPU
MAKEOPTS      -j16 -l16
EMERGE_DEFAULT_OPTS  --jobs=2 …            # 2, not 4: 30 GB against ~2 GB per compiler
FEATURES      getbinpkg binpkg-request-signature
```

**`CPU_FLAGS_X86` is not `-march`, and one cannot substitute for the other.**
`-march` says what the compiler may emit; `CPU_FLAGS_X86` says which hand-written
SIMD paths ebuilds compile in *at all*. Without it, libaom, nss, libgcrypt and
friends build scalar paths on a CPU that has every extension they could use.

**Overlays:** GURU (quickshell, CoolerControl, Inter), hyproverlay (Hyprland and
its companions, all `-9999` live ebuilds, which need `**` rather than `~amd64`),
steam-overlay.

**Nothing syncs the tree by itself** — Gentoo ships no `emerge-sync.timer` — so
`fd44-portage-sync.timer` does it daily. Stop it before a long rebuild: changing
ebuilds under a running resolve is how a build fails at 3 a.m. for no
reconstructible reason.

## Traps this machine taught

**`nvidia_drm` is not autoloaded, and nothing says so.** udev loads a module on
demand *for* a DRM device, and the DRM device is what this module creates.
Without it `/dev/dri` does not exist, Hyprland dies with
`CBackend::create() failed!`, and because `~/.bash_profile` execs uwsm the tty
returns to a login prompt — indistinguishable from a refused password. Fixed by
`/etc/modules-load.d/fd44-nvidia.conf` plus `modeset=1`.

**`/dev/uinput` is root-only by default**, so Steam Input cannot create the
virtual pad it feeds games through: a controller the kernel handles perfectly
that Steam can do nothing with.

**`gamemoderun` silently stops applying under Proton.** pressure-vessel empties
`LD_PRELOAD` at the container boundary, so GameMode deregisters before the game
starts. `/usr/local/bin/fd44-gamemode-hold` holds the registration from a process
that never enters the container; `bin/steam-launch-options.sh` writes it onto
every game.

**polkit refuses removable mounts to anything that is not the active seat
session** — a timer, an ssh shell. `/etc/polkit-1/rules.d/50-fd44-udisks.rules`
grants one action to one user so the backup timer can work.

**No Bluetooth adapter**, so the bar's Bluetooth module hides itself and stops
polling after its first answer.

## Everyday

```sh
bin/updates.py status                  # emerge, from a cache: asking costs 11 s
bin/backup.sh status                   # T5, LaCie, then the NixOS drive as fallback
sudo emerge -vuDN --getbinpkg @world   # what the bar's box runs
eselect news read
```
