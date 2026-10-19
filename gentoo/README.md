# Gentoo on the gaming desktop (gentoo00)

Built 2026-10-16, wiped for a Windows 11 install when Proton could not run
certain kernel-anti-cheat games. Everything here is what it took to get it
working, kept so a rebuild starts from the answers instead of rediscovering
them.

## What is here

| | |
|---|---|
| `make.conf` | Portage config, documented. The live copy also carried a generated `CPU_FLAGS_X86` line from `cpuid2cpuflags` — regenerate it, do not copy it |
| `kernel/config-7.2.11` | the kernel config as actually built |
| `etc/` | the `/etc` customisations, verbatim |
| `world` | the `@world` package set — 27 explicit choices behind 998 installed packages |
| `coolercontrol-curves.toml` | hand-tuned Quadro fan curves |
| `plymouth.initd`, `tuned-ppd.initd`, `libvirtd.confd` | services Gentoo ships systemd-only |
| `openrc-systemd-gaps.md`, `plymouth-openrc.md` | why those exist |

## The kernel config is the valuable part

`bin/gentoo-kernel-config.sh` regenerates it, but the config itself is proof
the script's symbol list is complete. Five separate rounds found things
`defconfig` leaves out, each of which only surfaced when something needed it:

- **zram** — the machine had no swap of any kind, so pressure meant OOM-kill
- **exfat, ntfs3, udf** — a Samsung T5 would not mount: "unknown filesystem type"
- **TUN, BRIDGE, VHOST_NET** — `/dev/kvm` worked, but guests had no network
- **netfilter, entirely absent** — `libvirtd` would not start, and no firewall
  was possible at all
- **`NETFILTER_XTABLES_LEGACY`** — one missing master switch left nine other
  netfilter symbols silently unsettable

The lesson under all five: `scripts/config` accepts symbol names that do not
exist and symbols whose dependencies are unmet, in silence. Set, then read
back. Never set and assume.

## Hardware notes that outlive this install

- **Suspend uses s2idle, not deep S3.** On deep, the board cuts USB power and
  the KBDFANS keyboard re-enumerates ~28 s *after* resume, so the lock screen
  takes input from a dead device, PAM logs "conversation failed", and
  `pam_faillock` counts it as a wrong password. See `etc/default/grub`.
- **Disk names are not stable.** `nvme0n1` and `nvme1n1` traded places between
  two boots of the same OS on this machine. Everything destructive keys on
  serial: Gentoo was the Samsung 990 PRO `S7KGNJ0X134514R`.
- **nvidia needs the open modules** (Blackwell GB202) and `@module-rebuild`
  after every kernel build — a module three hours older than its kernel can
  fail to load and leave you with no display.
