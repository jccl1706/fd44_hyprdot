#!/usr/bin/env bash
# =========================================================================
# wifi-wired-setup.sh - install the wifi/wired exclusivity dispatcher
# =========================================================================
#
# Usage:  sudo bin/wifi-wired-setup.sh [--dry-run]
#         sudo bin/wifi-wired-setup.sh --remove
#         bin/wifi-wired-setup.sh --status
#
# WHAT IT DOES
#   - installs network/50-wifi-wired-exclusive into
#     /etc/NetworkManager/dispatcher.d/no-wait.d/
#   - symlinks it from /etc/NetworkManager/dispatcher.d/, which is what makes
#     NetworkManager run it asynchronously
#   - makes sure NetworkManager-dispatcher.service is enabled, because the
#     directory existing is not the same as the service that reads it running
#
# THE SYMLINK IS THE POINT, not tidiness. A dispatcher script calling nmcli
# runs synchronously by default: the script waits on NetworkManager over D-Bus
# while NetworkManager waits on the script. NetworkManager-dispatcher(8) says a
# script that is a symlink pointing inside no-wait.d/ runs immediately and in
# parallel, which is the documented way out. Installing the file directly in
# dispatcher.d/ instead would appear to work and then hang on some cable event.
#
# PERMISSIONS ARE ENFORCED BY NetworkManager, not by preference: the man page
# requires each script be "a regular executable file owned by root ...  not
# writable by group or other, and not setuid". A script with the wrong mode is
# silently ignored, which is a miserable thing to debug, so this installs with
# an explicit 0755 and root:root rather than copying whatever the repo has.

set -euo pipefail

NAME=50-wifi-wired-exclusive
DISPATCH=/etc/NetworkManager/dispatcher.d
NOWAIT="$DISPATCH/no-wait.d"
OFFSWITCH=/etc/NetworkManager/wifi-wired-exclusive.off

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$here/network/$NAME"

dry_run=false
mode=install
for a in "$@"; do
    case "$a" in
        --dry-run) dry_run=true ;;
        --remove)  mode=remove ;;
        --status)  mode=status ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "wifi-wired-setup: unknown argument: $a" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
run() { if $dry_run; then printf '    would: %s\n' "$*"; else "$@"; fi; }

if [[ "$mode" == status ]]; then
    printf '  %-34s %s\n' "script" "$([[ -f "$NOWAIT/$NAME" ]] && echo installed || echo "not installed")"
    link="$(readlink "$DISPATCH/$NAME" 2>/dev/null || echo "")"
    printf '  %-34s %s\n' "symlink" "${link:-missing}"
    printf '  %-34s %s\n' "runs async (points into no-wait.d)" \
        "$([[ "$link" == *no-wait.d/* ]] && echo yes || echo 'NO - would block NetworkManager')"
    printf '  %-34s %s\n' "dispatcher service" "$(systemctl is-enabled NetworkManager-dispatcher.service 2>/dev/null)"
    printf '  %-34s %s\n' "disabled by off-switch" "$([[ -e "$OFFSWITCH" ]] && echo "YES - $OFFSWITCH exists" || echo no)"
    printf '  %-34s %s\n' "wifi radio now" "$(nmcli -t radio wifi 2>/dev/null)"
    exit 0
fi

# --dry-run changes nothing, so it must not demand root: a preview you can only
# see by escalating is not a preview anybody runs first.
$dry_run || [[ $EUID -eq 0 ]] || { echo "wifi-wired-setup: run with sudo" >&2; exit 2; }

if [[ "$mode" == remove ]]; then
    say "removing the dispatcher"
    run rm -f "$DISPATCH/$NAME" "$NOWAIT/$NAME"
    say "leaving the wifi radio enabled, so removing this cannot strand you offline"
    run nmcli radio wifi on
    exit 0
fi

[[ -f "$SRC" ]] || { echo "wifi-wired-setup: missing $SRC" >&2; exit 1; }

say "installing $NAME"
run install -d -m 0755 "$NOWAIT"
run install -m 0755 -o root -g root -T "$SRC" "$NOWAIT/$NAME"

# Relative target, so the link keeps working if /etc is ever moved or mounted
# somewhere else during an install.
run ln -sfn "no-wait.d/$NAME" "$DISPATCH/$NAME"

say "making sure the dispatcher service is enabled"
run systemctl enable --now NetworkManager-dispatcher.service

if ! $dry_run; then
    echo
    say "installed. Test it by pulling the cable and putting it back:"
    echo "    journalctl -t wifi-wired-exclusive -f"
    echo
    echo "    To suspend the behaviour without uninstalling:"
    echo "      sudo touch $OFFSWITCH"
fi
