# CoolerControl config, as it runs on NixOS

A copy of `/etc/coolercontrol/` from the NixOS install on the gaming desktop,
taken once the fan curves were working. It is a **file copy, not a
`coolercontrold --backup`**: the daemon's own backup format carries a
`manifest.toml` recording the daemon version, and `coolercontrold restore`
refuses a backup from a different version — which is exactly the problem this
directory exists to work around.

Excluded on purpose: `coolercontrol.key` (private), `coolercontrol.crt`, and the
`config.toml.*` working copies left by the edits.

## Why this is not the same file as ../coolercontrol-backup/

That one was made on Fedora by **coolercontrold 5.0.0**, from the COPR. nixpkgs
has **4.3.1**, including on nixos-unstable, so the two machines cannot share a
backup. Two things differ:

| | Fedora, 5.0.0 | NixOS, 4.3.1 |
| --- | --- | --- |
| Quadro device name | `quadro` | `Aquacomputer Quadro` |
| its device id | `89ddebd3…` | `bf328bd1…` |

The id is a hash that includes the name, so renaming the device between releases
changes it, and every `[device-settings.<id>]` and `temp_source` in the 5.0.0
backup points at a device 4.3.1 does not have. The curves themselves — profiles,
functions, speed points — are identical and transfer verbatim.

## Restoring this onto a fresh NixOS install

1. **Set `liquidctl_integration = false` first.** Nothing else works until this
   is done, and it is not the default. With liquidctl enabled, CoolerControl
   claims the Quadro through liqctld instead of hwmon, which gives it different
   sensor names — `temp1` "does not exist", so any profile reading it falls back
   to an emergency 100 °C — and a write path that fails: `Liqctld Request failed
   with status:502 Bad Gateway` when setting fan3. The Quadro has a kernel
   driver (`aquacomputer_d5next`); hwmon is the right source. This is the same
   setting `bin/cooling-setup.sh` sets on Fedora, for the same reason.
2. Stop the daemon **before** editing: it writes its in-memory settings to the
   config on shutdown and will overwrite the edit otherwise.
3. Copy `config.toml` into `/etc/coolercontrol/`, or graft its `[[profiles]]`,
   `[[functions]]` and `[device-settings.…]` blocks onto the existing file,
   rewriting the device id to whatever this machine calls the Quadro:
   `awk -F' = ' '/"Aquacomputer Quadro"/{print $1}' /etc/coolercontrol/config.toml`
4. Validate with `coolercontrold --config` — note 4.3.1 uses that flag, while
   5.0.0 has a `check` subcommand instead. The binary is not on `$PATH` under
   NixOS; resolve it from the unit:
   `systemctl show coolercontrold -p ExecStart --value`
5. Start the daemon and confirm the journal has no `is missing for Profile`
   lines. One unresolvable sensor inside a `max()` mix pins the fans it feeds at
   100% indefinitely, and looks like a hardware problem rather than a config one.

## What it controls

Three Quadro channels. The amdgpu and CPU devices are temperature *sources*
only — no profile writes to the GPU's own fan, so `amdgpu.ppfeaturemask`
overdrive is **not** needed for this configuration.

| channel | profile | follows |
| --- | --- | --- |
| fan1 | `fd44 CPU fan - Tctl` | CPU Tctl: 40 °C→25%, 60→35, 70→50, 80→75, 88→100 |
| fan2, fan3 | `fd44 case fans - max(air, GPU edge)` | the hotter of case air and GPU edge |

Verified idle at 28 °C case air / 41 °C GPU edge: all three channels at pwm 77,
about 730 rpm, no errors from the daemon.
