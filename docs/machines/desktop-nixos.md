# Gaming desktop — NixOS

`nixos-gaming00`, on the desktop's Samsung NVMe. The same hardware as the Gentoo
install on the other drive, reached from the firmware boot menu.

| | |
|---|---|
| CPU · GPU · RAM | Ryzen 7 9800X3D · RTX 5090 · 30 GB |
| disk | Samsung 3.6 TB — `NIXESP`, `NIXROOT` (300 GB), `NIXHOME` (3.3 TB) |
| config | **[`fd44_nixos`](https://github.com/jccl1706/fd44_nixos)**, a separate repository — `/etc/nixos` is a clone of it |
| rebuild | `sudo nixos-rebuild switch --flake .#nixos-gaming00` |

**Why a second repository at all:** this one holds the desktop — quickshell,
hypr, bin — and is shared by all three machines. NixOS system configuration is
not shareable, so it lives beside it rather than inside it. `bin/updates.py`
knows about both: on this machine "pending" means how far `flake.lock` trails
nixpkgs, counted in **days**, because nothing is pending on a system that is
whatever its flake evaluates to.

## Installing it from nothing

The authoritative steps are in **[`fd44_nixos`](https://github.com/jccl1706/fd44_nixos)**'s
README, under *Installing from scratch*. In outline:

1. Boot the **NixOS installer ISO**.
2. `disko` partitions the disk from `disko.nix` — **pinned to the revision
   `flake.lock` names**, so the CLI and the module cannot disagree about the
   layout.
3. `nixos-install --flake /path/to/fd44_nixos#nixos-gaming00 --no-root-passwd`
4. **Set a password before rebooting.** `nixos-install` leaves both accounts
   without one.
5. Clone this repository into `~/Work`, then `bin/link-dotfiles.sh` and
   `bin/starship-setup.sh`.

Unlike Gentoo beside it, this needs no other running system — the installer ISO
is enough, which is why it is the sensible one to put on a blank desktop first.

## What lives in the NixOS repo, not this one

| module | what it does |
|---|---|
| `gaming.nix` | `fd44-gamemode-hold` (GameMode across the pressure-vessel boundary), `fd44-epp`, GameMode hooks for do-not-disturb |
| `fd44.nix` | the GPU power limit |
| `cooling.nix` | CoolerControl, whose fan curves the Gentoo install adopted unchanged |
| `hardware.nix` | RTKit and the rest |

The Gentoo install reimplements several of these as scripts under
`/usr/local/bin` — `fd44-gamemode-hold`, `fd44-epp` — because a distribution
without Nix has nowhere else to put them. They are deliberately the same
behaviour, and `install/gentoo_gaming.sh` says so where it writes them.

## Open on this machine

- **No backup is configured.** The laptop and the Gentoo install both have one;
  this does not. It is the largest remaining gap on the desktop.
- **`python3` was added to `packages.nix` on 2026-09-30 and needs a rebuild.**
  Until then the bar's update box reads "unknown" here, silently — an indicator
  that cannot answer is supposed to draw nothing. `bin/updates.py` replaced a
  shell script that parsed JSON with `nix eval` precisely because NixOS carries
  no python3 unless asked.
- Those NixOS code paths in `updates.py` are carried over by inspection and have
  not been run on this machine yet.

## Everyday

```sh
bin/updates.py status     # days behind the pin, not a package count
bin/theme.sh              # the same desktop as the other two machines
```
