# CoolerControl configs from the NixOS install on the gaming desktop

Newest first. Each directory is a file copy of `/etc/coolercontrol/`, not a
`coolercontrold --backup`, and carries its own README.

| taken | describes | use it? |
| --- | --- | --- |
| `2026-10-04T13-10-00` | 9800X3D, RTX 5090, Quadro via hwmon. Restored onto Fedora unchanged and verified. | **yes** |
| `2026-09-17T10-37-59` | the earlier ASRock B650I / RX 9070 XT build, amdgpu sensors | no — names devices this machine does not have |

Both depend on `liquidctl_integration = false`: it decides whether the Quadro is
called `"quadro"` or `"Aquacomputer Quadro"`, and the device uid is a hash of
that name. The newest README explains it.
