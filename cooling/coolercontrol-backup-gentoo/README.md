# CoolerControl on gentoo-gaming00, which runs the NixOS config unchanged

There is no config in this directory on purpose. The Gentoo install on the
desktop's second NVMe runs `../coolercontrol-backup-gaming00/`, and on
2026-09-29 the five files under `/etc/coolercontrol/` there were **byte for byte
identical** to that backup. A second copy would only be a thing that rots, so
what is recorded here is the part that is not obvious: that the config
transfers at all, and how it was proven to have taken.

## Why it transfers verbatim

CoolerControl keys everything by device UID - a sha256 over what makes a device
unique - so a profile is only as portable as those hashes. **They came out
identical on Gentoo**, which was not a foregone conclusion: the same machine
under Fedora and under NixOS had exposed the Quadro with different sensor
names, which is why `cooling/` has three backups instead of one. What made it
work here is that both sides run **coolercontrold 4.3.1** and the hardware is
literally the same box. The three UIDs the curves depend on:

| UID | device | used as |
| --- | --- | --- |
| `c1f24395…` | `quadro` (`aquacomputer_d5next`) | the fan controller |
| `3145e1a4…` | AMD Ryzen 7 9800X3D (`k10temp`) | `temp1`, Tctl |
| `85a21d26…` | NVIDIA GeForce RTX 5090 (NVML) | `GPU Temp Hotspot` |

A UID that did not match would fail **silently**: the profile binds to nothing
and the fan keeps whatever duty it had. Which is exactly the trap below.

## The trap: the Quadro remembers

Before the config was installed, `fan3` and `fan4` read 30% and 29% at 50 °C -
which is precisely what `fd44 CPU fan - Tctl` asks for at that temperature, and
it looked like the curves were already live. They were not. **The Quadro keeps
the last duty it was told in its own memory**, so those were leftovers from the
final NixOS session, and `fan1`/`fan2` still sat at the 58%/56% fixed values
from before any of this existed. A stored duty does not ramp; it would have held
30% while the CPU climbed.

So a static reading proves nothing. The only check that does is a load:

| | Tctl | fan4 (CPU) | fan3 (exhaust) |
| --- | --- | --- | --- |
| idle | 51 °C | 716 rpm / 30% | 754 rpm / 32% |
| 15 s load | 76 °C | 1419 rpm / 65% | 1379 rpm / 65% |
| 45 s load | 77 °C | 1456 rpm / 67% | 1432 rpm / 67% |
| 30 s after | 51 °C | 835 rpm / 32% | 824 rpm / 32% |

65% at 76 °C and 67% at 77 °C are the graph to the percentage point - it
specifies 50% at 70 and 75% at 80. The slower fall than rise is the
`fd44 GPU calm` hysteresis.

## Gentoo particulars

`liquidctl` is not installed, so the daemon logs a Python environment error
about it on every start. It is harmless and expected: the config sets
`liquidctl_integration = false` and every fan here is on the Quadro's hwmon
driver. `sys-apps/coolercontrold` and `sys-apps/coolercontrol` (the GUI, which
drags in `dev-qt/qtwebengine` and is a long build) both come from GURU.

The TLS pair and `.passwd` under `/etc/coolercontrol/` are this install's own
credentials, generated on first start. They are excluded from every backup in
`cooling/` and must stay excluded.
