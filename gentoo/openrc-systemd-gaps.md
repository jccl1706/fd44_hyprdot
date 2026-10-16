# Packages that ship systemd units and nothing else

A recurring shape on Gentoo/OpenRC: a package installs, reports success, and
then does nothing — because its only integration is a `.service` file. There is
no error anywhere. Three hit this machine in one day.

| package | what was missing | symptom |
|---|---|---|
| `sys-boot/plymouth` | no `/etc/init.d` script at all | installed, never ran, no splash |
| `sys-apps/tuned` (ppd shim) | `tuned-ppd` has a dbus service file that defers to systemd | Plasma's power profile switcher had no backend |
| `app-emulation/libvirt` | `virtlogd` not enabled; `rc_need="net"` deadlock | `libvirtd` silently refused to start |

Files here: `plymouth.initd`, `plymouth-quit.local`, `tuned-ppd.initd`,
`libvirtd.confd`. See also `plymouth-openrc.md`.

## tuned-ppd

tuned ships `/usr/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service`
containing:

    Exec=/bin/false
    SystemdService=tuned-ppd.service

On systemd, dbus activation hands off to systemd. Here it runs `/bin/false` and
logs *"Activated service 'org.freedesktop.UPower.PowerProfiles' failed"*.

Plasma's Performance / Balanced / Power Save switcher talks to that interface,
**not** to tuned directly — so `tuned` running is not sufficient, and the
switcher looks present while doing nothing.

    install -m755 tuned-ppd.initd /etc/init.d/tuned-ppd
    rc-update add tuned-ppd default

Verify with the interface, not the process:

    dbus-send --system --print-reply --dest=org.freedesktop.UPower.PowerProfiles \
      /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties.Get \
      string:org.freedesktop.UPower.PowerProfiles string:ActiveProfile

## libvirtd

Two separate problems, both of which bite at **every** boot:

**1. `virtlogd` must be enabled.** `libvirtd`'s `depend()` has `need virtlogd`.
Without it, libvirtd refuses to start.

    rc-update add virtlogd default
    rc-update add virtlockd default

**2. `rc_need="net"` deadlocks.** `/etc/conf.d/libvirtd` ships with it.
NetworkManager *provides* `net` but marks itself `inactive` after
`INACTIVE_TIMEOUT=1` so it does not hold up the boot — and never flips to
`started`. libvirtd waits for a state that never arrives:

    * WARNING: libvirtd will start when NetworkManager has started

`libvirtd.confd` here changes it to `rc_need=""` plus `rc_after="net"`, keeping
the ordering without the hard block. Correct on this machine regardless, since
libvirt builds its own `virbr0` and does not need the host uplink first.

## rc_quiet hides exactly these messages

The `WARNING: libvirtd will start when NetworkManager has started` line — the
one that explained everything — is suppressed by `rc_quiet="YES"`, and
`EINFO_QUIET=no` does **not** override it. Diagnosing this meant setting
`rc_quiet="NO"` in `/etc/rc.conf`, reproducing, and setting it back. Worth
remembering before spending time on a service that "just won't start".
