# Wiping the Framework and reinstalling with KDE

Written on the Framework on 2026-10-15, the day before it is erased, so that
the work can continue from the gaming desktop once this machine is off. Delete
this file when the reinstall is done and working.

## Why it is written down

The imaging happens with the Framework's NVMe in a USB enclosure on the gaming
desktop. The Framework must therefore be powered off, and anything running on
it - including the session this plan was made in - is gone at that moment. The
repository is the only thing that crosses the gap.

## Before the disk is touched

Everything was checked on 2026-10-15:

| repo | state |
| --- | --- |
| `fd44_hyprdot` | pushed |
| `fd44_nixos` | pushed |
| `fd44_steamos` | pushed |
| `btrfs-patrol` | pushed |
| `void-qtile` | local is BEHIND GitHub, nothing unpushed |
| `debian-xfce4/xfce4-dots` | no commits, no remote - **deliberately abandoned**, a friend has a copy |

No uncommitted changes and no stashes anywhere. Four of the repos use SSH
remotes, so they were verified against GitHub's API rather than against local
tracking refs - which is how `void-qtile` was caught looking in sync while
GitHub actually held a later commit (`53303ce`) the checkout had never fetched.

**Still needed after the wipe, and not on the disk:** the restic repository
password, and the ssh key passphrases. The keys themselves are inside the
restic backup, so the password is the only way back to them. See
[key-rotation.md](key-rotation.md).

## The disk

```
Sabrent Rocket 4.0 1TB    serial 0546071110F388396596
931.5G    4.0G used
  p1    1G      vfat    /boot
  p2    930.5G  LUKS -> LVM (vg0) -> btrfs  /
```

## Imaging it, on the gaming desktop

The NVMe goes in a USB enclosure and is plugged into the desktop. Do not mount
it - `bin/disk-image.sh` refuses a mounted disk on purpose.

```sh
sudo ./bin/disk-image.sh measure 0546071110F388396596
sudo ./bin/disk-image.sh image   0546071110F388396596 /home/images
sudo ./bin/disk-image.sh verify  0546071110F388396596 /home/images
```

`measure` first, always. A LUKS disk is ciphertext and does not compress, but
never-written blocks are usually zeros and compress to nothing - so this image
could be 5 GB or 931 GB and only the drive's history decides which. Reading
takes about the same either way, since every block is read regardless.

Check before starting, because neither could be checked from the Framework:

- `/home` on the desktop has room for whatever `measure` predicts
- `zstd`, `gdisk` and `cryptsetup` are installed there

Going back one day is `restore` with the same serial. It asks for the serial to
be typed before it writes anything.

## Then the reinstall

Back in the Framework, booted from Fedora 44 install media:

```sh
./install/install_fedora.sh --check-repos   # 118/118 resolved on 2026-10-15
./install/install_fedora.sh --preflight
./install/install_fedora.sh --dry-run
./install/install_fedora.sh --plasma
```

`--plasma` installs 84 named packages, which dnf resolves to roughly 412 and
about 2 GB. `$terminal` switches from kitty to konsole by itself when Plasma is
chosen, and `libva-utils` is skipped because this is the AMD branch. The full
list is in `install_fedora.sh`: `basepacs`, `hwpacs`, `plasmapacs`, `apppacs`.

## Things this machine knows that a fresh one will not

- Hibernation is off on purpose - resume crashes on this hardware.
- The USB-C ethernet adapter only enumerates in the right slot; controller
  `c1:00.3` never sees it at boot.
- `daylight.timer` rotates the wallpaper hourly and takes the darker half of
  the collection after sunset; the location is written into
  `daylight/slots.conf` rather than inferred from the timezone.
