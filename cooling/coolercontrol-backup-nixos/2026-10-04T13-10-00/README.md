# CoolerControl config, as it runs on NixOS — and now on Fedora too

A copy of `/etc/coolercontrol/` from the NixOS install on the gaming desktop,
taken on 2026-10-04 while NixOS was shut down and its root mounted read-only
from the Fedora beside it. A **file copy, not a `coolercontrold --backup`**: the
daemon's own format carries a `manifest.toml` naming the daemon version, and
`coolercontrold restore` refuses a backup from a different version.

Excluded on purpose: `coolercontrol.key` (private) and `coolercontrol.crt`.

This directory **supersedes `../2026-09-17T10-37-59/`**, which is from the
ASRock B650I / RX 9070 XT build and names amdgpu sensors and channels this
machine no longer has. Restoring that one here would leave profiles pointing at
devices that do not exist.

## It was restored onto Fedora unchanged, and that was the surprise

The September README predicted a rewrite would be needed, because nixpkgs then
had coolercontrold 4.3.1 against Fedora's 5.0.0 and the two named the Quadro
differently. That is no longer true: **both installs now agree on every device
uid this config uses**, so the file copies over with nothing edited.

| device | uid | both installs |
| --- | --- | --- |
| AMD Ryzen 7 9800X3D | `3145e1a4…` | same |
| NVIDIA GeForce RTX 5090 | `85a21d26…` | same |
| Quadro, through hwmon | `c1f24395…` = `"quadro"` | same |

## One setting is load-bearing: `liquidctl_integration = false`

The uids match **only while liquidctl is off on both machines.** The Quadro is
supported by liquidctl and by the kernel's `aquacomputer_d5next`, CoolerControl
prefers liquidctl, and the uid is a sha256 that includes the device NAME — so
the same card is `"Aquacomputer Quadro"` (`027c45e6…`) through liquidctl and
`"quadro"` (`c1f24395…`) through hwmon. Every `[device-settings.<uid>]` and
`temp_source` here names the hwmon one.

Turning liquidctl back on therefore does not merely change a sensor source: it
makes every profile in this file point at a device that is not there. It also
breaks the old way, independently — different sensor names, so `temp1` "does not
exist" and the profile reading it falls back to an emergency 100 %, and a write
path that fails with `Liqctld Request failed with status:502 Bad Gateway`.

What it costs: the **ASUS Aura LED controller** vanishes from CoolerControl, RGB
being the one thing only liquidctl offers. Both installs accept that.

`install/fedora_gaming.sh` sets it on a fresh Fedora; `bin/cooling-setup.sh`
does the same at more length and explains the ordering.

## Restoring it

1. **Stop the daemon first.** It writes its in-memory settings to the config on
   shutdown and will overwrite the edit otherwise.
2. Copy `config.toml` to `/etc/coolercontrol/`.
3. Validate: `coolercontrold check` (5.x; 4.3.1 used `coolercontrold --config`).
   Under NixOS the binary is not on `$PATH` —
   `systemctl show coolercontrold -p ExecStart --value`.
4. Start it and read the journal. `Successfully applied::` for each channel is
   the pass; any `is missing for Profile` is the failure, and one unresolvable
   sensor inside a `max()` pins the fans it feeds at 100 % indefinitely, looking
   like a hardware fault rather than a config one.

## What it controls

Two of the Quadro's four channels. The CPU and GPU are temperature *sources*
only — nothing writes to the 5090's own fans, so `amdgpu.ppfeaturemask`
overdrive is irrelevant to this configuration.

| channel | profile | follows |
| --- | --- | --- |
| fan1 | `Unmanaged` | nothing — no fan on this channel (0 rpm) |
| fan3 | `fd44 exhaust - max(CPU, GPU)` | the hotter of the two curves below |
| fan4 | `fd44 CPU fan - Tctl` | CPU Tctl: 40 °C→25%, 60→35, 70→50, 80→75, 88→100 |

The GPU side of that mix is `fd44 GPU hotspot`, reading `GPU Temp Hotspot`:
50 °C→30%, 70→45, 85→70, 95→100. Smoothing comes from two functions, `fd44
smooth (2C, 2s)` on the CPU curve and `fd44 GPU calm (3C, 4s, slow down)` on
the GPU one.

Verified on Fedora immediately after the restore: fan3 at pwm 82 / 748 rpm,
fan4 at pwm 74 / 687 rpm, Quadro `temp1` 44.5 °C, and no missing-sensor lines.
