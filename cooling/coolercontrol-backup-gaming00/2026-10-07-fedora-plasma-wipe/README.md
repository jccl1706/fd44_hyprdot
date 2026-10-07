# CoolerControl config, Fedora 44 + niri, taken before the Plasma rebuild

A file copy of `/etc/coolercontrol/config.toml` from the install that was
wiped on 7 October 2026 to make way for Fedora + KDE Plasma. Same reasoning as
the sibling directories: a file copy, not `coolercontrold --backup`, because
the daemon refuses a backup taken from a different version.

Excluded on purpose: `.passwd`, `coolercontrol.key`, `coolercontrol.crt`.

Taken from coolercontrold 5.0.1, the Fedora package.

## Why this one matters

It is the first copy taken from a **Fedora** install rather than NixOS. The
curves themselves were restored from the NixOS backup earlier the same day and
were measured working: at Tctl 52.6 C the CPU fan sat at 30% / 728 rpm and the
exhaust at 32% / 769 rpm, within 2% of the figures in the 2026-09-21 README.

`liquidctl_integration` is `false` here, which is what makes the hwmon sensor
names - and therefore every device uid in this file - match the NixOS ones.

## Also here

- `packages.txt` - every package installed on that machine, for comparing
  against whatever the Plasma install produces.
- `versionlock.txt` - the dnf version locks, which at the time was
  xwayland-satellite held at 0.8.1 because 0.8.2 breaks X11 menus. That lock is
  niri-specific and a Plasma install does not need it.
