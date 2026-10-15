# Restoring the Framework to the niri/quickshell system

Written on the Framework on 2026-10-15, minutes before it is powered off and
its NVMe moved to an enclosure on the gaming desktop. Delete this file once the
restore is done and the laptop boots.

## What is being undone

The Framework was wiped this morning and reinstalled with KDE Plasma. The user
tried it for a day and chose to go back. The image taken before that wipe is a
byte-exact copy of the Fedora 44 + niri + quickshell system, verified when it
was made.

## The image

```
/home/jc/images/
  0546071110F388396596.img.zst          7.1 GiB   the whole disk, zstd
  0546071110F388396596.sda2.luks-header  16 MiB   root-only, 0600
  0546071110F388396596.sfdisk / .gpt              partition table, twice
  0546071110F388396596.source.sha256              c40b6218eca57bfb...
```

Decompresses to exactly 1,000,204,886,016 bytes. Partition UUIDs `812F3644…`
(EFISYSTEM) and `4FB06272…` (CRYPTROOT) match what was recorded on the laptop
before the drive first came out.

## Doing it

NVMe out of the Framework, into the USB enclosure, into this desktop. **Do not
mount it** - `disk-image.sh` refuses a mounted disk on purpose.

```sh
cd ~/Work/fd44_hyprdot
sudo ./bin/disk-image.sh restore 0546071110F388396596 /home/jc/images
```

It finds the disk by serial, never by `/dev/sdX`, asks for the serial to be
typed, writes 932 GiB, then reads the whole disk back and compares it against
the recorded checksum. Allow 40-60 minutes for the write over USB and roughly
the same again for the verify.

**This is the first time `restore` has ever run.** Two faults were found in it
by reading it beforehand (commit `09dce6f`): a missing `iflag=fullblock`, which
with `oflag=direct` could have failed partway through a disk already being
overwritten, and a success message printed without measuring anything. Both are
fixed. Watch it rather than walking away.

## Afterwards

- The drive goes back in the Framework and boots niri + quickshell.
- Its **old ssh host key returns**, so this desktop's `known_hosts` will object.
  That is expected: `ssh-keygen -R 192.168.10.163` and reconnect.
- `fd44_hyprdot` becomes a live configuration again rather than a repository
  describing no running machine. The memory note `framework-runs-kde-plasma`
  should be corrected or deleted once that is true.

## What is lost, and where it is instead

Everything done on the KDE install is replaced: the system, the restic
configuration, the btrfs scrub timer, and `~/.claude` - including the
conversation in which all of this was done.

**It is not gone.** The 16:07 backup on the T5 captured it: snapshot
`77c40876`, 817 MiB, including `~/.claude`. The restored system will have
`~/.claude` as of this morning instead. To bring today back afterwards:

```sh
restic restore 77c40876 --target / --include /home/jc/.claude
```

The restic repository itself lives on the T5 and is untouched by any of this.
