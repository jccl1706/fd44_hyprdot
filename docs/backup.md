# Backup and restore

The copy that is not on this disk — what it holds, how to check it, and how to
get everything back. The source of truth is
[`bin/backup.sh`](../bin/backup.sh); this is the page to read when something has
gone wrong and reading a shell script is not what you want to be doing.

> **A backup nobody has restored from is not a backup, it is a hope.**
> `bin/backup.sh verify` restores the latest snapshot into a temporary directory
> and diffs it against the real thing. Run it occasionally. It is the only
> command here that proves anything.

---

## What this answers, and what it does not

Three different failures, three different answers, and only one of them is on
this page:

| failure | answer |
|---|---|
| "I deleted it an hour ago" | btrfs snapshots (`btrfs-patrol`), on the same disk |
| "the disk is rotting" | `bin/btrfs-scrub.sh`, on the same disk |
| **"the disk is gone"** | **this** — a repository on a different disk entirely |

The first two live on the disk they protect, so neither survives a drive dying,
a theft or a fire. Until 2026-09-24 this repository had no answer to that at all.

---

## What is copied

An **include list**, not "everything minus exclusions" — the two fail in
opposite directions. An include list fails by missing a file, which a restore
shows you. An exclude list fails by quietly copying a 50 GB cache, and nobody
notices until the disk is full.

- `~/.ssh` — four private keys. The one thing here that cannot be regenerated.
- `~/.config/gh`, `~/.config/copr` — tokens that act as this account.
- `~/.claude`, `~/.claude.json` — sessions, memory and settings.
- `~/.config/chromium` — logins, cookies, bookmarks. What stands in for a
  password manager right now.
- `~/.bashrc`, `~/.bashrc.d`, `~/.bash_profile`, `~/.gitconfig`
- `~/Work/*` — the checkouts. All pushed, but what is *not* pushed is whatever
  you were writing when the disk died.

Measured rather than guessed: about 400 MB, of which the part that would really
hurt is 80 KB of keys.

restic encrypts the repository itself — contents, metadata and filenames — so
the disk holding it needs no LUKS of its own. One less passphrase, and a disk
readable on any machine that has the password.

---

## Where it goes

`BACKUP_UUID` in `~/.config/fd44-backup/config` is an ordered **list**, and
**the first attached disk wins**. That is what makes "one disk in use, one in a
drawer" work without re-running setup on every swap.

| machine | disks, in order |
|---|---|
| Framework (Fedora) | Samsung T5 `8C26-3AF6`, LaCie `b2bddbef…` |
| Desktop (Fedora) | **not set up yet** |
| Desktop (NixOS) | T5, LaCie |

Each disk holds a **complete repository of its own**, not half of one, so either
can restore a machine alone. They are independent: a snapshot taken while the T5
was attached is not on the LaCie until the LaCie is attached and a run happens.

Gentoo used to hold a third entry here — an internal cross-disk copy onto the
NixOS drive. Gentoo was replaced by Fedora on 2026-10-04 and **Fedora has no
backup configured at all**, which is the largest open item on this page.

**NixOS no longer has the mirror image of that either.** It used to mount
Gentoo's root at `/mnt/gentoo` and keep a third repository there; that was
dropped on 2026-10-04 and it now backs up to the external disks only. A copy on another
partition of the same machine survives a dead drive and nothing else — not
theft, not a power supply taking the board with it, not the mistake that deletes
the wrong thing twice. The repository already written there is left in place,
about 95 MB, and went with the disk when Fedora replaced Gentoo.

The T5 now holds **two machines' snapshots in one repository**, tagged by host.
That is how restic is designed to work and it dedupes across both.

Retention is `--keep-daily 7 --keep-weekly 4 --keep-monthly 12`, applied with
`--prune` after each run.

---

## Every day

Nothing, normally. A user timer runs it daily (`systemd/backup.timer`,
~00:28 with 30 minutes of jitter, `Persistent=true` so a machine that was off
catches up), and the bar's backup glyph appears only when the last run is
getting old — amber at half the patience, red past a fortnight or if the machine
has never backed up at all. One click runs one in a terminal.

By hand:

```sh
bin/backup.sh status      # when the last one was, and to which disk
bin/backup.sh run         # take one now
bin/backup.sh disks       # the disks it knows, and which is attached
bin/backup.sh snapshots   # what is on the attached disk
bin/backup.sh check       # verify the repository's integrity
bin/backup.sh verify      # restore the latest snapshot and diff it
bin/backup.sh escrow      # what must be kept OFF this machine
```

---

## Restore

### One file, or one directory

```sh
bin/backup.sh mount ~/snapshots     # the snapshots as a filesystem
ls ~/snapshots/snapshots/latest/    # browse, copy what you want, Ctrl-C to unmount
```

Nothing is written to the machine; it is a read-only view of every snapshot.

### Everything, onto the machine you are on

```sh
bin/backup.sh restore /tmp/restored   # into a directory, to look first
```

Restoring straight over `$HOME` is deliberately not a command here. Restore
beside it, look, then move what you want.

### A machine that is gone

On a fresh install with nothing but restic and the disk — no checkout of this
repository, no config:

```sh
restic -r /run/media/<you>/<disk>/fd44-backup snapshots
restic -r /run/media/<you>/<disk>/fd44-backup restore latest --target /
```

It will ask for the repository password. **If you do not have it, nothing on
that disk can ever be read** — see escrow below.

Each disk also carries its own copy of these instructions at
`<disk>/fd44-backup/RESTORE.md`, written by `bin/backup.sh readme`, because
instructions that live only on the machine that died are not instructions.

The order that works on a bare machine:

1. Install the OS and get on the network. **Wi-Fi credentials are not in the
   backup** — they live in root-owned `/etc/NetworkManager`. Know the password.
2. Install `restic`; restore as above.
3. `git clone` this repository into `~/Work`, then `bin/link-dotfiles.sh`.
4. `bin/backup.sh setup` to point the new machine at the disk again.

---

## Escrow: what no backup can contain

Run `bin/backup.sh escrow` for the current list. It is short and it is the whole
game:

1. **The repository password.** It is in `~/.config/fd44-backup/password` on a
   machine that may not exist when you need it. A safe, a paper note, a password
   manager on a phone — anywhere that survives the machine.
2. **Which disks** carry the repositories (their UUIDs).
3. **The LUKS passphrase** for any encrypted root, *and a header backup*, which
   is not the same thing: a damaged header cannot be opened by any passphrase.
   `sudo cryptsetup luksHeaderBackup <dev> --header-backup-file luks-header.img`,
   kept with the note rather than on the machine it unlocks.

`bin/backup.sh run` copies the header backups onto each disk it writes to, so
they travel with the repository.

---

## Traps this arrangement has already hit

**polkit, on a machine with nobody sitting at it.** `backup.sh` mounts through
`udisksctl` on purpose — it runs as you, because the files are yours — and
polkit's default answer for mounting removable media is "yes, if the caller is
the active seat session". A systemd timer is not a seat session and neither is
ssh, so the mount is refused at exactly the moment a backup should happen:

```
Error mounting /dev/sda1: ...NotAuthorizedCanObtain: Not authorized
```

The old Gentoo desktop carried a narrow rule for this in
`/etc/polkit-1/rules.d/50-fd44-udisks.rules`: one action
(`filesystem-mount`), one user. On Fedora it never surfaced because the disks
get mounted in-session when you plug them in.

**Internal targets are a different polkit action.** Mounting an internal,
non-removable partition is `filesystem-mount-system`, whose default is
`auth_admin` — a password prompt, which a timer cannot answer. So the desktop's
internal fallback is mounted from `/etc/fstab` at boot instead, and
`backup.sh` finds it already mounted and never asks udisks at all.

**`status` over ssh looks broken and is not.** It mounts the disk to read the
repository, so from an ssh session it prints "the backup disk is not connected"
about a disk that is plugged in. Run it on the machine.

**The first configured disk wins, not the newest.** If the list is
`T5 LaCie internal` and all three are attached, everything goes to the T5. Order
the list the way you want the answer.
