# Changing the repository password

The password on `~/.config/fd44-backup/password` is the only thing between
someone holding the backup disk and everything on it: `~/.ssh` with ten keys,
`~/.config/gh`, `~/.claude`, and seven work directories. It is worth being long.

This is the procedure for changing it. The source of truth for everything else
about backups is [`backup.md`](backup.md) and
[`bin/backup.sh`](../bin/backup.sh); this page exists because key rotation is
the one operation on the repository that `bin/backup.sh` deliberately does not
wrap, and getting the ORDER wrong locks you out of your own backup.

> **The repository password is the backup.** restic cannot recover data from a
> repository whose passwords are all lost — there is no reset, no escrow, no
> support address. Write the new one down somewhere physical BEFORE you type it.


## Why this is cheap

`restic key add` adds a second password that unlocks the SAME data keys. The
snapshots are not re-encrypted, nothing is re-uploaded, and the repository is
unchanged apart from one small key file. Removing the old password afterwards is
equally cheap.

So this takes about a minute and touches none of the data. It is not a
migration.


## Before you start

Have the new password decided and recorded. A passphrase of four or five
unrelated words beats a short jumble of symbols: it is longer, and you can copy
it off a piece of paper correctly at 2am on a machine that has just died.


## 1. Connect the disk and find the repository

```sh
cd ~/Work/fd44_hyprdot
bin/backup.sh status
```

Wait for `connected  yes`, then resolve the path the same way the script does —
by UUID, because the mount point under `/run/media` is not stable:

```sh
REPO="$(lsblk -rno UUID,MOUNTPOINT |
        awk '$1=="b2bddbef-d595-4d29-810a-68b8084bec3f" && $2!="" {print $2; exit}')/fd44-backup"
echo "$REPO"
```

That must print a real path ending in `/fd44-backup`. Empty means the disk is
not mounted yet — run `bin/backup.sh status` again, which mounts it.


## 2. See what keys exist

```sh
restic -r "$REPO" --password-file ~/.config/fd44-backup/password key list
```

One row, marked `*`: the key you are using now. Note its ID.


## 3. Add the new key

```sh
restic -r "$REPO" --password-file ~/.config/fd44-backup/password key add
```

It asks for the NEW password twice. It does not ask for the old one — that comes
from the file.


## 4. Put the new password in the file

```sh
printf '%s' 'YOUR NEW PASSWORD' > ~/.config/fd44-backup/password
chmod 600 ~/.config/fd44-backup/password
```

Single quotes, and no trailing newline — `printf '%s'` rather than `echo`.
If the password itself contains a single quote:

```sh
cat > ~/.config/fd44-backup/password <<'EOF'
YOUR NEW PASSWORD
EOF
truncate -s -1 ~/.config/fd44-backup/password
```


## 5. Verify before removing anything

```sh
restic -r "$REPO" --password-file ~/.config/fd44-backup/password snapshots | tail -5
```

**If this fails, stop here.** The old key still works: put the old password back
in the file and work out what went wrong. Nothing is lost at this point, because
nothing has been removed.


## 6. Remove the old key

```sh
restic -r "$REPO" --password-file ~/.config/fd44-backup/password key list
restic -r "$REPO" --password-file ~/.config/fd44-backup/password key remove <OLD_ID>
```

The ID from step 2 — the one that is no longer marked `*`.


## 7. Confirm the ordinary path still works

```sh
bin/backup.sh status
bin/backup.sh run
```


## The one mistake that locks you out

**Do not remove the old key before steps 4 and 5.**

`bin/backup.sh` reads the password from `~/.config/fd44-backup/password`. Between
`key add` and updating that file, the file still holds the OLD password — so
removing the old key at that moment leaves the script holding a password the
repository no longer accepts, and the only copy of the working password is
whatever you typed into step 3 and may not have written down.

The order above exists for that reason: add, switch, verify, and only then
remove.


## Afterwards

Update wherever the old password was recorded — the safe, the paper note, the
password manager. A backup whose password is written down in one place that is
now wrong is in a worse state than one whose password was never written down at
all, because you will trust it.
