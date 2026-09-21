# CoolerControl config, as it runs on nixos-gaming00

A copy of `/etc/coolercontrol/` from the NixOS install on the new gaming
desktop, taken once the fan curves were working and measured. It is a **file
copy, not a `coolercontrold --backup`**: the daemon's own backup format carries
a `manifest.toml` recording the daemon version, and `coolercontrold restore`
refuses a backup from a different version — which is the problem this directory
exists to work around.

Excluded on purpose, and they must stay excluded: `.passwd` (the API
credential), `coolercontrol.key` (private) and `coolercontrol.crt`.

Taken 2026-09-21 from **coolercontrold 4.3.1**, the nixpkgs version.

## What is wired where

| channel | fan | profile |
| --- | --- | --- |
| Quadro `fan4` | CPU cooler | `fd44 CPU fan - Tctl` |
| Quadro `fan3` | exhaust | `fd44 exhaust - max(CPU, GPU)` |
| Quadro `fan1` | **do not use** | Unmanaged |

**QUADRO CHANNEL 1 IS DEAD** — its PWM output, not its power or tach. The CPU
fan was on it first and behaved exactly like a 3-pin fan on a PWM header: the
duty changed and the speed did not. Forced to 80% it read 827 rpm; at 28%, 825.
It drew current and reported a tach throughout, so every reading said the
channel was alive except the one that mattered.

The same fan on channel 4 answers properly — 25% → 619 rpm, 50% → 1150,
80% → 1628. A fan that reaches 1628 rpm was never running flat out at 825, which
rules out the fan and the cable and leaves the channel. ch1 still works as a
power-and-tach header; nothing that needs controlling should go on it.

Nothing is connected to `fan2`, `fan5`, or to any `nct6799` channel — every fan
in the case is on the Quadro.

## The curves

```
fd44 CPU fan - Tctl         Graph, CPU temp1 (Tctl, NOT temp3/Tccd1)
                            40→25  60→35  70→50  80→75  88→100
                            function: fd44 smooth (2C, 2s)

fd44 GPU hotspot            Graph, GPU Temp Hotspot
                            50→30  70→45  85→70  95→100
                            function: fd44 GPU calm (3C, 4s, slow down)

fd44 exhaust - max(CPU,GPU) Mix, mix_function_type = "Max", of the two above
```

The Mix/Max is the point of the arrangement: exhaust carries heat from both the
CPU and the card, so it follows whichever is currently worse rather than either
alone.

The two functions are hysteresis, and they are why the fans do not audibly hunt.
Both are `f_type = "Standard"` with `threshold_hopping` on; the CPU one uses
deviance 2.0 and response_delay 2, the GPU one deviance 3.0, response_delay 4
and `step_size_min/max_decreasing` 1/3 so that it comes down slowly.

**The GPU's own fans are deliberately not driven.** CoolerControl can — it
reaches the card through NVML and lists `fan1`/`fan2` as channels — but the
firmware curve does that job well, and the 500 W power limit in fd44_nixos is
the lever that actually moves the card's temperature. `GPU Temp Hotspot` is
wanted here only as an input to the exhaust mix.

## Measured

16 threads for 60 seconds, sampled every 15:

| CPU | CPU fan | exhaust |
| --- | --- | --- |
| 45 °C | 625 rpm / 27% | 707 rpm / 30% |
| 67 °C | 962 rpm / 43% | 957 rpm / 43% |
| 69 °C | 991 rpm / 45% | 991 rpm / 45% |
| 70 °C | 1117 rpm / 49% | 1118 rpm / 49% |
| 51 °C (after) | 745 rpm / 30% | 745 rpm / 30% |

Before any of this both fans sat at a fixed duty whatever the temperature —
58% and 50% — which is what the exercise was for.

## Restoring onto a fresh install

1. **Set `liquidctl_integration = false` first.** Nothing else works until it is
   done, and it is not the default. With liquidctl enabled CoolerControl claims
   the Quadro through liqctld instead of hwmon, which gives it different sensor
   names — `temp1` "does not exist", so a profile reading it falls back to an
   emergency 100 °C and every fan it feeds pins at 100% — and a write path that
   fails with `Liqctld Request failed with status:502 Bad Gateway`. The Quadro
   has a kernel driver (`aquacomputer_d5next`); hwmon is the right source.
2. **Stop the daemon before editing** any of these files: it writes its
   in-memory state on shutdown and will overwrite the edit otherwise. Restart it
   afterwards, or it will not see devices that appeared since it started.
3. `nct6775` must be loaded or the board's sensors are absent entirely. On this
   machine `modules/cooling.nix` in fd44_nixos asks for it; nothing loads it
   otherwise.
4. Check the device UIDs before trusting `[device-settings.<uid>]`. A UID is a
   sha256 over the device's identity **including its name**, so a CoolerControl
   release that renames a device invalidates every setting and `temp_source`
   pointing at it. That is exactly what differs between this backup and
   `../coolercontrol-backup/`, which was made by 5.0.0 on Fedora where the
   Quadro is called `Aquacomputer Quadro` rather than `quadro`. The curves
   themselves — profiles, functions, speed points — transfer verbatim.

## Rebuilding by hand instead

The profiles can be created through the daemon's HTTP API on `127.0.0.1:11987`
rather than by editing TOML, which is how these were made: `POST /login` with
the CCAdmin credential for a session cookie, then `POST /functions`,
`POST /profiles`, and `PUT /devices/<uid>/settings/<channel>/profile`. Read
`GET /devices` first — profiles reference devices by the computed UID, so there
is no way to write valid TOML without asking the daemon what they are.

The UI does the same thing and needs no credential handling. Note its own
warning: **profiles are not auto-applied**. Creating one changes nothing until
it is assigned to a channel.
