#!/usr/bin/env bash
# =========================================================================
# cooling-setup.sh - fan curves for the gaming desktop, with CoolerControl
# =========================================================================
#
# Usage:  sudo bin/cooling-setup.sh [--dry-run] [--gpu-overdrive] [-y]
#
# Opt-in, and not part of the installer or of gaming-setup.sh: fan control
# is specific to one machine's hardware. On the ASRock B650I / RX 9070 XT
# desktop every fan is on an Aquacomputer QUADRO, and until something drives
# it, its four channels sit at fixed duty values (64, 107, 107 and 133 of
# 255, measured) - the same speed idle as under a 300 W GPU load.
#
# WHAT THIS TOUCHES
#   - enables the codifryed/CoolerControl COPR (CoolerControl is packaged
#     nowhere else - not Fedora, not RPM Fusion)
#   - installs coolercontrold ONLY, and starts it
#   - with --gpu-overdrive: adds amdgpu's overdrive bit to the kernel
#     command line, which the GPU's own fan curve needs. Reboot required.
#   - verifies all of it
#
# THE DAEMON ALONE IS ENOUGH. coolercontrold carries CoolerControl's whole
# web UI inside its binary and serves it at http://127.0.0.1:11987 - so the
# desktop app is skipped. That app exists to show the same UI in a window,
# and it costs qt6-qtwebengine: 277 MB, plus a Qt base update, qtpdf and
# qtpositioning. Chromium is already here.
#
# TWO RECOMMENDS ARE DROPPED, BY NAME. coolercontrold recommends lm_sensors
# (which brings Perl and dmidecode) and python3-liquidctl (seven Python
# packages). liquidctl is for USB coolers WITHOUT a kernel driver; the Quadro
# has one, aquacomputer_d5next, and CoolerControl reads hwmon directly. They
# are excluded with -x, the way the installer excludes nwg-panel, rather
# than with install_weak_deps=False - that flag stays unused in this
# repository, for the firmware reasons written up in the installer. If the
# daemon somehow does not see the Quadro, installing python3-liquidctl is
# the fallback, and the verification pass says so.
#
# THE REPOSITORY WAS CHECKED BEFORE IT WAS TRUSTED. The COPR's signing key
# is E8AB88BC4834377F98A165F860E6A0997C96AB47, and coolercontrold 5.0.0 was
# verified against exactly that key in a throwaway rpm database: signature
# OK, header and payload digests OK. dnf checks it again on install
# (gpgcheck=1 in the COPR's repo file).

set -euo pipefail

DRY=0
GPU_OD=0
ASSUME_YES=()
COPR="codifryed/CoolerControl"
PORT=11987
KEY_ID="60e6a0997c96ab47"

while (( $# )); do
    case "$1" in
        --dry-run)       DRY=1 ;;
        --gpu-overdrive) GPU_OD=1 ;;
        -y|--yes)        ASSUME_YES=(-y) ;;
        -h|--help)       sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'cooling-setup: unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
run()  { if (( DRY )); then printf '\033[1;34mwould run:\033[0m %s\n' "$*"; else "$@"; fi; }

# Ensure amdgpu's overdrive bit is set in a kernel command line FILE, keeping
# every other argument. Idempotent: running it twice changes nothing.
# Prints what it did. Separate so it can be tested on a copy.
od_cmdline() {
    local f="$1" mask="$2" cur
    cur="$(tr ' ' '\n' < "$f" | sed -n 's/^amdgpu\.ppfeaturemask=//p' | head -1)"
    if [[ -z $cur ]]; then
        sed -i "1s/[[:space:]]*\$/ amdgpu.ppfeaturemask=$mask/" "$f"
        echo "added amdgpu.ppfeaturemask=$mask"
    elif (( cur & 0x4000 )); then
        echo "already present with the overdrive bit ($cur)"
    else
        sed -i "1s/amdgpu\.ppfeaturemask=[^[:space:]]*/amdgpu.ppfeaturemask=$mask/" "$f"
        echo "replaced amdgpu.ppfeaturemask=$cur with $mask"
    fi
}

# Set liquidctl_integration = false in a CoolerControl config FILE, touching
# nothing else. Idempotent. Reports through two globals, _LIQ_CHANGED and
# _LIQ_MSG, and prints nothing.
#
# CALL IT DIRECTLY, NEVER AS "$(liquidctl_off ...)". Command substitution runs
# the function in a subshell, so the flag it sets dies with that subshell. The
# first version was called exactly that way: it edited the config, reported
# success, lost the flag, and never restarted the daemon - which went on
# running with liquidctl enabled and logging the error. Measured: flag 0
# inside $(...), 1 when called directly.
_LIQ_CHANGED=0
_LIQ_MSG=""
liquidctl_off() {
    local f="$1"
    _LIQ_CHANGED=0
    if grep -q '^liquidctl_integration = true$' "$f"; then
        sed -i 's/^liquidctl_integration = true$/liquidctl_integration = false/' "$f"
        _LIQ_CHANGED=1; _LIQ_MSG="set liquidctl_integration = false"
    elif grep -q '^liquidctl_integration = false$' "$f"; then
        _LIQ_MSG="already liquidctl_integration = false"
    else
        _LIQ_MSG="liquidctl_integration not found in $f - left alone"
    fi
}

# True when the running coolercontrold started BEFORE FILE was last changed,
# i.e. it is running with a config it has not read. This is what makes a
# re-run repair a machine the earlier bug left behind: there, the config
# already says false, so nothing changes now - but the daemon predates it.
daemon_older_than() {
    local started cfgtime
    started="$(date -d "$(systemctl show -p ActiveEnterTimestamp --value coolercontrold 2>/dev/null)" +%s 2>/dev/null)" || return 1
    cfgtime="$(stat -c %Y "$1" 2>/dev/null)" || return 1
    (( cfgtime > started ))
}

# True when every listening address on stdin (address:port, one per line) is
# loopback, and there is at least one. The UI can change fan speeds; it has
# no business answering the network.
#
# `|| [[ -n $a ]]` is load-bearing. Plain `while read` returns false on a last
# line with no trailing newline and never runs the body for it - so in
# testing, "127.0.0.1 then a LAN address" came back loopback-only, because
# the LAN address was the unterminated last line. For a security check that
# is failing open. Here-strings add the newline and would have hidden it.
loopback_only() {
    local any=0 bad=0 a
    while read -r a || [[ -n $a ]]; do
        [[ -z $a ]] && continue
        any=1
        case "$a" in 127.*:*|'[::1]':*|::1:*) ;; *) bad=1 ;; esac
    done
    (( any && ! bad ))
}

# Sourced for testing: define the functions and stop.
[[ ${COOLING_SETUP_LIB:-0} == 1 ]] && return 0 2>/dev/null

(( EUID == 0 )) || die "must run as root - try: sudo $0"


# -------------------------------------------------------------------------
# What is here
# -------------------------------------------------------------------------
log "machine"
quadro=""
for h in /sys/class/hwmon/hwmon*; do
    [[ $(cat "$h/name" 2>/dev/null) == quadro ]] && quadro="$h"
done
if [[ -n $quadro ]]; then
    printf '    Aquacomputer Quadro: %s (%s pwm channel(s))\n' "$quadro" "$(ls "$quadro"/pwm[0-9] 2>/dev/null | wc -l)"
else
    warn "no Aquacomputer Quadro found - CoolerControl will still install, but"
    warn "  the fans this script was written for are not visible."
fi
printf '    amdgpu ppfeaturemask: %s\n' "$(cat /sys/module/amdgpu/parameters/ppfeaturemask 2>/dev/null || echo n/a)"


# -------------------------------------------------------------------------
# Repository and package
# -------------------------------------------------------------------------
log "CoolerControl COPR"
# grep -q FED BY A HERE-STRING, never by a pipe, everywhere in this script.
# Under `set -o pipefail`, `cmd | grep -q x` is a coin toss: grep exits at the
# first match, cmd dies of SIGPIPE, and the pipeline reports failure for a
# match it FOUND. Measured on this very script's Quadro check: exit 141 in
# five runs out of five, which is how the first run reported the Quadro
# missing while the daemon's log named it twice.
if grep -q 'codifryed:CoolerControl' <<<"$(dnf repolist --enabled 2>/dev/null)"; then
    printf '    already enabled\n'
else
    run dnf "${ASSUME_YES[@]}" copr enable "$COPR"
fi

log "coolercontrold (the daemon, with the web UI built in)"
run dnf install "${ASSUME_YES[@]}" coolercontrold -x lm_sensors -x python3-liquidctl

log "service"
run systemctl enable --now coolercontrold

# liquidctl integration OFF. liquidctl is deliberately not installed (see the
# header), and with the integration on, the daemon reports that as an error on
# every start: "Python Environment Error: Python liquidctl system package not
# detected ... liqctld exited with a non-zero exit code: 1". Its own message
# names the fix. The daemon writes its config on first start, so this waits
# for the file, flips the one key, and restarts it.
log "liquidctl integration off (liquidctl is deliberately not installed)"
cfg=/etc/coolercontrol/config.toml
if (( DRY )); then
    printf '\033[1;34mwould set:\033[0m liquidctl_integration = false in %s, then restart coolercontrold\n' "$cfg"
else
    for _ in $(seq 1 30); do [[ -f $cfg ]] && break; sleep 1; done
    liquidctl_off "$cfg"
    printf '    %s\n' "$_LIQ_MSG"
    if (( _LIQ_CHANGED )) || daemon_older_than "$cfg"; then
        systemctl restart coolercontrold
        printf '    coolercontrold restarted, so it runs with this setting\n'
    fi
fi


# -------------------------------------------------------------------------
# GPU fan curve (optional)
# -------------------------------------------------------------------------
# On RDNA3/4 the GPU's fan curve lives behind amdgpu's overdrive interface,
# and CoolerControl says so itself: "True indicates overdrive is enabled and
# fan control is available". Without the overdrive bit there is no
# gpu_od/fan_ctrl directory and nothing to write.
#
# ON THE KERNEL COMMAND LINE, NOT IN /etc/modprobe.d - which is where
# CoolerControl's own button would put it ("options amdgpu ppfeaturemask=").
# This machine boots Plymouth, whose dracut module pulls amdgpu into the
# initramfs, and amdgpu loads from there. A modprobe.d option only reaches
# the initramfs when it is rebuilt; forget that and the setting silently does
# nothing. A kernel argument applies however the module is loaded. It is also
# the installer's own mechanism: /etc/kernel/cmdline plus kernel-install add,
# so future kernels inherit it with no further action.
#
# The mask is the LIVE value with bit 0x4000 added, not a constant copied from
# a guide, so no other power feature this kernel enabled is switched off.
#
# What it costs: amdgpu logs, at critical level, "Overdrive is enabled,
# please disable it before reporting any bugs unrelated to overdrive."
if (( GPU_OD )); then
    log "GPU overdrive (for the GPU's own fan curve)"
    live="$(cat /sys/module/amdgpu/parameters/ppfeaturemask)"
    mask="$(printf '0x%x' $(( live | 0x4000 )))"
    if (( DRY )); then
        printf '\033[1;34mwould set:\033[0m amdgpu.ppfeaturemask=%s in /etc/kernel/cmdline, then kernel-install add %s\n' "$mask" "$(uname -r)"
    else
        printf '    %s\n' "$(od_cmdline /etc/kernel/cmdline "$mask")"
        kernel-install add "$(uname -r)" "/usr/lib/modules/$(uname -r)/vmlinuz"
        printf '    boot entry regenerated - REBOOT for it to take effect\n'
    fi
fi


# -------------------------------------------------------------------------
# Verification
# -------------------------------------------------------------------------
(( DRY )) && { log "dry run - skipping verification"; exit 0; }

printf '\n'
log "verification"
pass=0; fail=0
ok()   { printf '    \033[1;32mok\033[0m   %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '    \033[1;31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
note() { printf '    \033[1;33mnote\033[0m %s\n' "$*"; }

grep -q 'codifryed:CoolerControl' <<<"$(dnf repolist --enabled 2>/dev/null)" \
    && ok "COPR $COPR enabled" || bad "COPR $COPR not enabled"

if rpm -q coolercontrold >/dev/null 2>&1; then
    sig="$(rpm -q --qf '%{SIGPGP:pgpsig}' coolercontrold 2>/dev/null || true)"
    if [[ ${sig,,} == *"$KEY_ID"* ]]; then
        ok "coolercontrold $(rpm -q --qf '%{version}' coolercontrold), signed by the COPR key $KEY_ID"
    else
        bad "coolercontrold is installed but not signed by $KEY_ID (${sig:-no signature})"
    fi
else
    bad "coolercontrold not installed"
fi

for p in lm_sensors python3-liquidctl; do
    rpm -q "$p" >/dev/null 2>&1 \
        && note "$p is installed (not by this script's transaction - it was excluded)" \
        || ok "$p not pulled in"
done

[[ $(systemctl is-active coolercontrold 2>/dev/null) == active ]] \
    && ok "coolercontrold service active" || bad "coolercontrold service is not active"

# Loopback only. A fan controller reachable from the LAN is a remote way to
# stop someone's cooling.
addrs="$(ss -Htln "sport = :$PORT" 2>/dev/null | awk '{print $4}')"
if loopback_only <<<"$addrs"; then
    ok "UI listens on loopback only ($(paste -sd' ' <<<"$addrs"))"
else
    bad "UI port $PORT is not loopback-only: ${addrs:-nothing listening}"
fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$PORT/" || true)"
[[ $code =~ ^[23] ]] && ok "UI answers at http://127.0.0.1:$PORT (HTTP $code)" \
                      || bad "UI did not answer at http://127.0.0.1:$PORT (HTTP ${code:-none})"

# Did the daemon pick up the Quadro, and can it drive fan1-4? Read from the
# CURRENT daemon run's log only - selected by its systemd invocation ID, since
# -b would mix in the run before the liquidctl restart. The daemon lists what
# it initialised ("Initialized Hwmon Devices: {...\"quadro\"...}") and names
# every channel it cannot control ("Fan channel fanN at <path> is not
# controllable: <reason>"). fan5 is the flow sensor and has no PWM at all.
inv="$(systemctl show -p InvocationID --value coolercontrold 2>/dev/null || true)"
for _ in $(seq 1 60); do
    cclog="$(journalctl --no-pager "_SYSTEMD_INVOCATION_ID=$inv" 2>/dev/null || true)"
    grep -q 'Initialization Complete' <<<"$cclog" && break
    sleep 1
done
if [[ -z $quadro ]]; then
    note "no Quadro on this machine - nothing to check"
elif grep -q 'Initialized Hwmon Devices:.*"quadro"' <<<"$cclog"; then
    blocked="$(grep -cE "Fan channel fan[1-4] at ${quadro} is not controllable" <<<"$cclog" || true)"
    if (( blocked == 0 )); then
        ok "daemon detected the Quadro; none of fan1-4 reported uncontrollable"
    else
        bad "daemon detected the Quadro but reports $blocked of fan1-4 uncontrollable"
        grep -E "Fan channel fan[1-4] at ${quadro}" <<<"$cclog" | sed 's/^.*Fan channel/         Fan channel/' | head -4
    fi
else
    bad "the daemon did not initialise the Quadro - see: journalctl -u coolercontrold -b"
fi

grep -q '^liquidctl_integration = false$' /etc/coolercontrol/config.toml 2>/dev/null \
    && ok "liquidctl integration off" || bad "liquidctl_integration is not false in /etc/coolercontrol/config.toml"
if grep -q 'liquidctl system Python package not found' <<<"$cclog"; then
    bad "the daemon still reports the missing liquidctl package"
else
    ok "no liquidctl error in the current daemon run"
fi

if (( GPU_OD )) || grep -q 'amdgpu.ppfeaturemask' /etc/kernel/cmdline 2>/dev/null; then
    grep -q 'amdgpu.ppfeaturemask=' /etc/kernel/cmdline \
        && ok "overdrive requested in /etc/kernel/cmdline" || bad "overdrive not in /etc/kernel/cmdline"
    live="$(cat /sys/module/amdgpu/parameters/ppfeaturemask)"
    if (( live & 0x4000 )); then
        ok "overdrive active ($live) - GPU fan curve available"
    else
        note "overdrive not active yet ($live) - reboot, then run this again"
    fi
fi

printf '\n'
if (( fail )); then
    printf '\033[1;31m%d check(s) failed\033[0m, %d passed\n' "$fail" "$pass"
    exit 1
fi
log "all $pass checks passed"
printf '\nOpen http://127.0.0.1:%s in Chromium.\n' "$PORT"
