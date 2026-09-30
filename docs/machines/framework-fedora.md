# Framework 13 (AMD) — Fedora

The laptop. The machine this configuration was written on, and the one every
other install is compared against.

| | |
|---|---|
| model | Framework Laptop 13, AMD Ryzen 7040 series |
| CPU | Ryzen 5 7640U, Radeon 760M graphics — **no discrete GPU** |
| RAM | 54 GB |
| disk | 931 GB NVMe, LUKS → LVM → Btrfs |
| hostname | `framework` |
| built by | [`install/install_fedora.sh`](../../install/install_fedora.sh) |

## What is different here

**Encrypted root.** `CRYPTROOT` → `cryptlvm` → `vg0-root`, Btrfs on top. The LUKS
passphrase and a *header backup* both belong off the machine — a damaged header
cannot be opened by any passphrase. See [backup.md](../backup.md).

**No discrete GPU**, so the bar's thermal readout is absent by design:
`bin/thermal.sh` answers `ok: false` and `ThermalButton` draws nothing. Same
mechanism that keeps the Bluetooth glyph off the Gentoo desktop.

**Hibernation is deliberately off.** Resuming from it has crashed this machine,
so it is not configured and should not be added back.

**The EVO4 audio interface** has its own WirePlumber rule in `wireplumber/` —
software volume, matched to that device only.

**Bluetooth works and is used** (the Buds3 Pro live here). The desktop has no
adapter at all, which is why the module hides itself there.

## Everyday

```sh
bin/updates.py status      # dnf, and the bar's count
bin/backup.sh status       # T5 and LaCie, whichever is plugged in
bin/theme.sh               # dark / cream
```

## Installing it from nothing

1. Fedora Workstation live ISO, then `install/install_fedora.sh` — it asks for a
   dotfiles git URL; give it this repository.
2. `bin/link-dotfiles.sh`, then `bin/starship-setup.sh` for the prompt.
3. Restore from a backup disk: [backup.md](../backup.md) has the order, and the
   part it cannot restore — wifi credentials live in root-owned
   `/etc/NetworkManager`.
