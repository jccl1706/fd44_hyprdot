#!/usr/bin/env bash
# =========================================================================
# lock-at-login.sh - lock the session at login when the disk is not encrypted
# =========================================================================
#
# Usage:  lock-at-login.sh           lock now, unless / is on an encrypted device
#         lock-at-login.sh --check   say what it would do, change nothing
#
# Run by hypr/autostart.lua when Hyprland starts.
#
# WHY. The installer sets up autologin on tty1, so switching the machine on
# lands straight in the desktop. On a LUKS machine that is fine: the boot
# passphrase IS the login. On one installed with --desktop (no encryption) it
# meant anyone who switched it on - or held the power button and switched it
# back on - got an unlocked desktop, with the browser sessions and ssh keys
# that come with it. So the session locks itself first; autologin still
# starts everything behind the lock, so nothing is slower once you are in.
#
# It also closes the crash case: .bash_profile logs out when a Hyprland session
# ends, getty autologins a new one, and this locks that one too.
#
# FAIL CLOSED. If it cannot tell whether the root filesystem is encrypted - no
# findmnt, an unexpected source, lsblk failing - it locks.
#
# The lock is started exactly as hypridle's lock_cmd starts it: in a systemd
# scope of its own, so restarting quickshell or hypridle cannot kill it.

set -u

check=0
[[ ${1:-} == --check ]] && check=1

# ROOT_SOURCE overrides the device, for testing the decision on a machine
# whose own disk says the opposite.
src="${ROOT_SOURCE:-$(findmnt -no SOURCE / 2>/dev/null || true)}"
src="${src%%\[*}"            # btrfs subvolume suffix: /dev/mapper/vg0-root[/root]

encrypted=unknown
if [[ -n $src ]]; then
    # Here-string, not a pipe into grep -q: under pipefail grep's early exit
    # can SIGPIPE lsblk and read as "not found". The whole chain of devices
    # under / is listed, so LUKS below LVM below Btrfs is still found.
    types="$(lsblk -rsno TYPE "$src" 2>/dev/null || true)"
    if [[ -n $types ]]; then
        if grep -qx crypt <<<"$types"; then encrypted=yes; else encrypted=no; fi
    fi
fi

if (( check )); then
    printf 'root device : %s\n' "${src:-(none found)}"
    printf 'device chain: %s\n' "$(lsblk -rsno TYPE "$src" 2>/dev/null | tr '\n' ' ')"
    printf 'encrypted   : %s\n' "$encrypted"
    if [[ $encrypted == yes ]]; then
        printf 'action      : none - the boot passphrase already guards the autologin\n'
    else
        printf 'action      : lock the session at login\n'
    fi
    exit 0
fi

[[ $encrypted == yes ]] && exit 0

pidof hyprlock >/dev/null 2>&1 && exit 0
exec systemd-run --user --scope --quiet --collect --unit=hyprlock \
    hyprlock --immediate-render --no-fade-in
