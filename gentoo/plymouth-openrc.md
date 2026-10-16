# Plymouth on Gentoo/OpenRC, without an initramfs

Gentoo's `sys-boot/plymouth` ships **systemd units only** — no `/etc/init.d`
script — so on OpenRC nothing starts it. `plymouth.initd` and
`plymouth-quit.local` here are what make it work on gentoo00.

## Install

    emerge sys-boot/plymouth
    install -m755 plymouth.initd       /etc/init.d/plymouth
    install -m755 plymouth-quit.local  /etc/local.d/00-plymouth-quit.start
    rc-update add plymouth boot

Kernel command line, in `/etc/default/grub`:

    GRUB_CMDLINE_LINUX_DEFAULT="... quiet splash loglevel=3"

`loglevel=3` is deliberate: errors still reach the console, so a real failure
is not hidden behind the splash.

## No initramfs, on purpose

This machine has none — every boot-critical driver is built into the kernel, so
root mounts directly. Plymouth therefore cannot start before root the way it
does elsewhere; it covers the OpenRC portion of the boot instead. That is most
of what is visible here precisely *because* there is no initramfs to sit
through. Adding dracut just for a splash would mean putting an initramfs back
into a working system for a cosmetic gain.

`after modules` in the init script is load-bearing: `nvidia_drm` is a module,
and with no DRM device Plymouth gets a blank screen or a text fallback rather
than a splash.

## The quit hook

Plymouth is meant to hand over to the display manager itself. If it does not it
keeps DRM master and SDDM comes up black — indistinguishable from a broken
graphics driver. `00-plymouth-quit.start` makes the handover unconditional.

## Hiding OpenRC's own messages

The `* Starting foo ... [ ok ]` lines come from OpenRC writing to the console,
so the kernel's `quiet` does not touch them. In `/etc/rc.conf`:

    rc_quiet="YES"

Undocumented in `rc.conf` but supported — both `rc_quiet` and `EINFO_QUIET` are
in the openrc binaries.

**`rc_logger` does not rescue what `rc_quiet` hides.** Measured on 2026-10-16:
with both set, `/var/log/rc.log` held 26 lines and none of the service status
messages, because `rc_quiet` suppresses them before the logger sees them. Keep
it for output that bypasses einfo, not as a safety net.

What remains for diagnosis:

| | |
|---|---|
| `rc-status --crashed` | services that died |
| `rc-status <runlevel>` | what is started, stopped, inactive |
| `/var/log/everything/` | daemons' own messages via metalog, unaffected |

`rc-service <svc> status` is **silent** with `rc_quiet` on. Use `rc-status`.

`NetworkManager` showing `inactive` in `rc-status` is normal here — it
backgrounds itself; the link, address and route are all up.
