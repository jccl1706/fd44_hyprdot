# Thermal logs — nixos-gaming00

Sampled measurements from real gameplay on the gaming desktop, kept as the
evidence behind the fan curves in `../coolercontrol-backup-gaming00/` and the
GPU power limit in `fd44_nixos/modules/fd44.nix`.

Both runs are **ARC Raiders**, 2026-09-21, same settings, same machine, taken
five seconds apart per sample with `bin/thermal-log.sh`.

| file | samples | play time | GPU limit |
| --- | --- | --- | --- |
| `2026-09-21-arcraiders-500w.log` | 244 | 17m40s | 500 W |
| `2026-09-21-arcraiders-600w.log` | 127 | 9m40s | 600 W (the card's default) |

## THE FAN COLUMNS ARE NOT IN THE SAME ORDER

The 500 W log was taken with an ad-hoc script that named the channels by role;
the 600 W log with `bin/thermal-log.sh`, which **discovers** fan channels and
therefore emits them in numeric order — so the exhaust comes first:

```
500 W:  time cpuC cpuW gpuC tlim gpuW gpu%  gfxMHz  cpufan pct   exh   pct
                                                    ^fan4        ^fan3
600 W:  time cpuC cpuW gpuC tlim gpuW gpu_  mhz     fan3   pct   fan4  pct
                                                    ^exhaust     ^CPU fan
```

Quadro **fan4 is the CPU fan** and **fan3 is the exhaust** (see the backup
README for why, and for why channel 1 is dead). Read the header, not the
position. The files are left exactly as recorded rather than normalised,
because they are measurements.

## What the columns mean

| column | |
| --- | --- |
| `cpuC` | CPU package temperature, Tctl from k10temp — the one the curves read |
| `cpuW` | CPU package power, a RAPL delta between samples, not an instantaneous read |
| `gpuC` | GPU core temperature |
| `tlim` | **degrees of headroom before the card throttles**, counting down. Not a temperature — this is the honest throttle indicator |
| `gpuW` | GPU board power draw |
| `gpu%` / `gpu_` | GPU utilisation |
| `gfxMHz` / `mhz` | GPU core clock |
| `pct` | the fan's duty as a percentage of 255 |

## What they showed

**The 500 W cap was inert, and the second run proves it rather than arguing it.**

| under GPU load | 500 W capped | 600 W uncapped |
| --- | --- | --- |
| GPU power, median / max | 314 / 328 W | 316 / 333 W |
| core clock, median | 2805 MHz | 2820 MHz |
| GPU temp, median / max | 61 / 63 °C | 62 / 63 °C |
| headroom to throttle | 29 °C, never below 27 | 28 °C, never below 27 |
| CPU temp, median | 56 °C | 58 °C |

5 W of peak draw and 15 MHz of clock — 0.5%, and across runs of different
length and different gameplay, so inside run-to-run noise. The card never came
within 170 W of the cap it was under, which is why the limit went back to the
card's own 600 W default.

**The GPU drives the exhaust, not the CPU.** Comparing what each curve would
ask for at each sample, the GPU side was the higher of the two in **86%** of the
first run and **98%** of the second. That is the justification for the exhaust
being a `Max` mix rather than a CPU-only curve: for almost the whole of a
gaming session it is the card the case has to ventilate.

**The exception is loading, and it is the interesting one.** At t=123–144s in
the 500 W log, during shader compilation with the GPU nearly idle:

```
CPU 79 °C, 110 W     GPU 27% util     fans → 70%
t=150s  game starts, CPU 66 °C        fans → 36%
```

A GPU-only exhaust curve would have left the case unventilated through the
hottest CPU moment of the session. That is precisely the case the `Max` exists
for, and it caught it.

## What these logs do NOT establish

One game, one set of settings, and neither run went anywhere near the
interesting part of either curve — the GPU peaked at 63 °C with 28 °C of
headroom, and the CPU curve's upper breakpoints (80 °C → 75%, 88 °C → 100%)
were only ever touched by that loading spike.

So these settings are demonstrated comfortable for this workload and unproven
for anything heavier. Something that pushes the card past ~450 W or the CPU past
75 °C would be a genuinely new data point and worth logging the same way:

```sh
bin/thermal-log.sh --probe             # check it finds the sensors first
bin/thermal-log.sh -o run.log          # Ctrl-C when done
bin/thermal-log.sh --summary run.log
```
