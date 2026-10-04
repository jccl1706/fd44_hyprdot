# Starting from nothing

The machine is gone — stolen, dead, or wiped. **The steps for each system live
on that system's page**; this page is what is true of all three, and the order
to do them in.

| system | its install steps |
|---|---|
| Framework 13 — Fedora | [machines/framework-fedora.md](machines/framework-fedora.md#installing-it-from-nothing) |
| Gaming desktop — NixOS | [machines/desktop-nixos.md](machines/desktop-nixos.md#installing-it-from-nothing) |
| Gaming desktop — Fedora | [machines/desktop-fedora.md](machines/desktop-fedora.md#installing-it-from-nothing) |

> **Read the next section today, not on the day.** Everything here assumes you
> can decrypt a backup. If you cannot, the rest is only a fresh install of an
> operating system, and the four private keys in `~/.ssh` are gone for good.

---

## What you must have, and cannot recover

`bin/backup.sh escrow` prints the current list on any working machine. It is
short, and it decides whether this is a restore or merely a reinstall:

| | |
|---|---|
| **the restic repository password** | lives in `~/.config/fd44-backup/password`, on a machine that may not exist any more. Without it every snapshot on every disk is unreadable — by design, permanently |
| **which disks hold repositories** | the T5 and the LaCie, by UUID |
| **the LUKS passphrase** *and* **a header backup** | not the same thing: a damaged header cannot be opened by any passphrase. `backup.sh run` copies the header onto each disk it writes to, so it travels with the repository |
| **wifi credentials** | in no backup — they are root-owned system state in `/etc/NetworkManager`. Know the password, or use a cable |

A safe, a paper note, a password manager on a phone. Anywhere that survives the
machine.

---

## The order, when more than one is gone

**On a blank gaming desktop, install NixOS first.** Fedora's installer runs from
a *running Linux* rather than from its own ISO — that is deliberate, and it
means the desktop needs something to install from. NixOS's installer ISO needs
nothing, so it is the sensible first system; Fedora then goes onto the other
drive from inside it. A live ISO works too, but a working NixOS is more use
afterwards than a live session is.

The laptop has no such constraint: its installer is its ISO.

---

## After any of them

Every system ends the same way:

```sh
bin/link-dotfiles.sh          # the configs, symlinked from the checkout
bin/starship-setup.sh         # the prompt
bin/backup.sh setup           # point it at a disk again
bin/backup.sh verify          # prove a restore works, rather than hoping
```

Restoring the data itself — one file, a whole home, or a bare machine — is
[backup.md](backup.md), which also lists the bootstrap order and the parts a
backup cannot contain.

The machine you have just rebuilt is also the machine that now has to back
itself up. The escrow list above is what makes the *next* recovery possible.
