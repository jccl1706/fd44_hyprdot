#!/usr/bin/env bash
# =========================================================================
# chromium-policy-setup.sh - let the theme switch set Chromium's colours
#                            without giving the user write access to /etc
# =========================================================================
#
# Usage:  sudo bin/chromium-policy-setup.sh              set up, or repair
#         sudo bin/chromium-policy-setup.sh --remove     take it all out
#         install/install_fedora.sh runs it in the chroot with --user NAME
#
# WHY. bin/chrome-theme.sh themes Chromium through an enterprise policy file,
# and Chromium reads policy only from /etc/chromium/policies/managed. This used
# to be solved by making that directory owned by the user - which meant ANY
# program running as the user could drop in its own policy: force-install an
# extension the browser will not let you remove, set a proxy, turn off Safe
# Browsing. Owning the directory granted all of browser policy to get one
# colour.
#
# NOW the directory is root's again, and a small root service writes the one
# file the theme needs:
#
#   chrome-theme.sh (user)   writes "<rrggbb> <light|dark>" (or "off") to
#                            ~/.local/state/fd44-hyprdot/chromium-theme
#   fd44-chromium-theme.path (root) notices the file change
#   fd44-chromium-theme.service (root) runs the helper, which accepts ONLY a
#                            six-digit colour and light/dark, and writes
#                            color.json - nothing else, ever
#
# No sudo at theme-switch time and no passwordless sudoers rule: the user can
# ask for a colour, and that is the whole of what they can ask for. The service
# is sandboxed - read-only system, no network, and the single capability it
# needs to read the request file inside a 0700 home directory.

set -euo pipefail

die() { printf '\033[1;31mchromium-policy-setup:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }


# -------------------------------------------------------------------------
# This is the Fedora setup script
# -------------------------------------------------------------------------
# It installs packages with dnf and writes to /usr and /etc, none of which
# exists in that form on NixOS. Without this check the failure arrives several
# steps in as `dnf: command not found` or a write to a directory that is not
# there, which reads like a broken script rather than the wrong machine.
#
# ID_LIKE is accepted too, so Fedora derivatives (Nobara, Bazzite) still work.
# FD44_SKIP_DISTRO_CHECK=1 overrides it for anyone who knows better.
require_fedora() {
    [[ -n ${FD44_SKIP_DISTRO_CHECK:-} ]] && return 0
    # --help always works, wherever you are. Two of these scripts parse their
    # arguments AFTER this point, and a help text you cannot read on the wrong
    # machine is exactly the sort of small obstruction this check exists to
    # remove rather than add.
    case "${1:-}" in -h|--help) return 0 ;; esac
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
        like="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}")"
    fi
    [[ $id == fedora || " $like " == *" fedora "* ]] && return 0
    printf '\033[1;31merror:\033[0m %s is the Fedora setup script; this system reports ID=%s.\n' \
        "$(basename "$0")" "${id:-unknown}" >&2
    printf '       %s\n' "On NixOS this is a systemd unit: see modules/fd44.nix in fd44_nixos." >&2
    printf '       Override with FD44_SKIP_DISTRO_CHECK=1 if you are sure.\n' >&2
    exit 1
}
require_fedora "$@"

(( EUID == 0 )) || die "must run as root - try: sudo $0"

user="${SUDO_USER:-}"
remove=0
while (( $# )); do
    case "$1" in
        --user)   user="${2:?--user needs a name}"; shift ;;
        --remove) remove=1 ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done
[[ -n $user ]] || die "run it with sudo from your own account, or pass --user NAME"
home="$(getent passwd "$user" | cut -d: -f6)"
[[ -n $home && -d $home ]] || die "no home directory for $user"

policy_dir=/etc/chromium/policies/managed
helper=/usr/local/libexec/fd44-chromium-theme
unit=fd44-chromium-theme
request="$home/.local/state/fd44-hyprdot/chromium-theme"

# systemctl cannot start or stop anything inside the installer's chroot - it
# only enables, which is all a system that has not booted yet needs.
if [[ -d /run/systemd/system ]] && ! systemd-detect-virt --chroot -q 2>/dev/null; then
    live=1
else
    live=0
fi

if (( remove )); then
    log "removing the Chromium theme service"
    if (( live )); then systemctl disable --now "$unit.path" 2>/dev/null || true
    else systemctl disable "$unit.path" 2>/dev/null || true; fi
    rm -f "/etc/systemd/system/$unit.path" "/etc/systemd/system/$unit.service" "$helper"
    rm -f "$policy_dir/color.json"
    (( live )) && systemctl daemon-reload
    log "done - Chromium no longer follows the theme"
    exit 0
fi

# --- the policy directory, root's ------------------------------------------
#
# chown/chmod explicitly rather than trusting `install -d`: on a machine set up
# the old way the directory already exists, owned by the user, and so may the
# color.json inside it.
log "policy directory: $policy_dir, owned by root"
install -d -m 755 "$policy_dir"
chown root:root /etc/chromium /etc/chromium/policies "$policy_dir"
chmod 755 /etc/chromium /etc/chromium/policies "$policy_dir"
find "$policy_dir" -maxdepth 1 -type f -exec chown root:root {} + -exec chmod 644 {} +

# --- the helper ------------------------------------------------------------
log "helper: $helper"
install -d -m 755 "$(dirname "$helper")"
cat > "$helper.tmp" <<'HELPER'
#!/bin/sh
# Written by bin/chromium-policy-setup.sh (fd44_hyprdot). Run as root by
# fd44-chromium-theme.service when the user's request file changes.
#
#   fd44-chromium-theme <request-file> <owner>
#
# The request must be exactly "<rrggbb> <light|dark>" or "off", in a regular
# file owned by <owner>. Anything else is refused without being echoed - the
# request path is in a user's home, and a symlinked or hostile file must not
# turn this into a way to read or write anything else.
#
# LOOPS until the request stops changing. The path unit does not trigger
# again for a change that lands while this is still running, so with the
# theme toggled several times a second the last request could be missed and
# Chromium left on the wrong scheme. Re-checking after each write catches it.
# By modification time, not content: a toggle there and back rewrites the
# same line, and that must still count as a change.
set -eu
req="$1"
owner="$2"
dir=/etc/chromium/policies/managed

applied=""
rounds=0
while :; do
    [ -e "$req" ] || exit 0
    if [ -L "$req" ] || [ ! -f "$req" ]; then
        echo "fd44-chromium-theme: request is not a regular file - ignored" >&2
        exit 1
    fi
    if [ "$(stat -c %U -- "$req")" != "$owner" ]; then
        echo "fd44-chromium-theme: request is not owned by $owner - ignored" >&2
        exit 1
    fi

    stamp="$(stat -c %y -- "$req")"
    [ -n "$applied" ] && [ "$stamp" = "$applied" ] && exit 0
    line="$(head -c 64 -- "$req" | head -n 1)"

    if [ "$line" = off ]; then
        rm -f "$dir/color.json"
        echo "fd44-chromium-theme: policy removed"
    else
        color="${line%% *}"
        scheme="${line#* }"
        case "$color" in
            [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
            *) echo "fd44-chromium-theme: malformed request - ignored" >&2; exit 1 ;;
        esac
        case "$scheme" in
            light|dark) ;;
            *) echo "fd44-chromium-theme: malformed request - ignored" >&2; exit 1 ;;
        esac

        tmp="$(mktemp "$dir/.color.json.XXXXXX")"
        printf '{"BrowserThemeColor": "#%s", "BrowserColorScheme": "%s"}\n' "$color" "$scheme" > "$tmp"
        chmod 644 "$tmp"
        mv -f "$tmp" "$dir/color.json"
        echo "fd44-chromium-theme: #$color / $scheme"
    fi

    applied="$stamp"
    rounds=$((rounds + 1))
    [ "$rounds" -ge 50 ] && exit 0
    sleep 0.3
done
HELPER
chown root:root "$helper.tmp"
chmod 755 "$helper.tmp"
mv -f "$helper.tmp" "$helper"

# --- the units -------------------------------------------------------------
log "units: $unit.path and $unit.service"
cat > "/etc/systemd/system/$unit.service" <<UNIT
# Written by bin/chromium-policy-setup.sh (fd44_hyprdot).
[Unit]
Description=Apply the Chromium theme colour requested by $user
# No start rate limit. The default - 5 starts in 10 s - is one theme toggle
# pressed quickly a few times, and hitting it fails this unit AND the path
# unit watching for requests, so Chromium stops following the theme until
# root runs reset-failed. Each run is a few milliseconds of validated writes.
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=$helper $request $user

# Everything it does not need, taken away. It reads one file in a 0700 home
# (CAP_DAC_READ_SEARCH, and nothing else) and writes one directory.
CapabilityBoundingSet=CAP_DAC_READ_SEARCH
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=$policy_dir
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
PrivateNetwork=yes
RestrictAddressFamilies=AF_UNIX
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
UNIT
cat > "/etc/systemd/system/$unit.path" <<UNIT
# Written by bin/chromium-policy-setup.sh (fd44_hyprdot).
[Unit]
Description=Watch $user's Chromium theme request

[Path]
PathChanged=$request
Unit=$unit.service

[Install]
WantedBy=multi-user.target
UNIT
chmod 644 "/etc/systemd/system/$unit.service" "/etc/systemd/system/$unit.path"

if (( live )); then
    systemctl daemon-reload
    # A watcher that already hit the old start limit stays failed until this.
    systemctl reset-failed "$unit.path" "$unit.service" 2>/dev/null || true
    systemctl enable --now "$unit.path"
else
    systemctl enable "$unit.path"
fi

# --- verify ----------------------------------------------------------------
if (( live )); then
    log "verification"
    fail=0
    [[ $(stat -c '%U %a' "$policy_dir") == "root 755" ]] \
        && echo "    ok   $policy_dir is root's (755)" || { echo "    FAIL $policy_dir owner/mode: $(stat -c '%U %a' "$policy_dir")"; fail=1; }
    if runuser -u "$user" -- test -w "$policy_dir"; then
        echo "    FAIL $user can still write $policy_dir"; fail=1
    else
        echo "    ok   $user cannot write $policy_dir"
    fi
    [[ $(systemctl is-active "$unit.path") == active ]] \
        && echo "    ok   $unit.path is watching $request" || { echo "    FAIL $unit.path is not active"; fail=1; }
    (( fail )) && die "setup incomplete"
    log "done - switch the theme once (SUPER+T) to apply the current colour"
fi
