#!/usr/bin/env bash
#
# Idle actions for hypridle. Exists so hypridle.conf holds plain commands
# instead of nested shell quoting, and so the logic can be tested directly
# with --dry-run.
#
# Usage:
#   idle-action.sh lock    {battery|always}   lock the session
#   idle-action.sh blank   {battery|always}   turn the display off
#   idle-action.sh suspend {battery|always}   suspend the machine
#   idle-action.sh wake                       turn the display back on
#   idle-action.sh presleep                   lock, and wait for it to paint
#
# "battery" means: do nothing when running on AC, because the later
# unconditional listener handles that case.
#
#
# ===========================================================================
# THE TWO BUGS THIS SCRIPT EXISTS TO WORK AROUND
# ===========================================================================
#
# 1. `hyprctl dispatch dpms off` DOES NOT WORK on Hyprland 0.56.
#    `hyprctl dispatch` evaluates LUA, not the old space-separated string
#    form, so the widely-copied form is a parse error:
#        error: [string "return hl.dispatch(dpms off)"]:1: ')' expected near 'off'
#    It fails SILENTLY - hypridle logs that it ran the command and the screen
#    simply never blanks. The Lua form used below is the working equivalent.
#
# 2. `hl.dsp.dpms(...)` IGNORES ITS ARGUMENT AND TOGGLES.
#    Verified on Hyprland 0.56.2: three consecutive dpms("on") calls produce
#    dpmsStatus 1 -> 0 -> 1 -> 0, with or without a monitor name. "on" and
#    "off" are interchangeable; the call is a flip.
#
#    This matters enormously because hypridle fires on-resume for EVERY armed
#    listener simultaneously. Two unguarded toggles cancel out, leaving the
#    display off while both calls log "ok" - which is precisely what stranded
#    this machine on 2026-09-11: the screen blanked on schedule, a keypress
#    fired two wake calls in the same second, and it never came back. The only
#    way out was a VT switch.
#
#    Therefore every dpms change here reads the CURRENT state and only toggles
#    when the state actually needs to change, under an flock so simultaneous
#    callers serialise instead of racing.
# ===========================================================================

set -u

AC_ONLINE=/sys/class/power_supply/ACAD/online
LOCKFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/idle-action.lock"

DRY=0
args=()
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        *)         args+=("$a") ;;
    esac
done
action="${args[0]:-}"
scope="${args[1]:-always}"

log() { printf '[idle-action] %s\n' "$*"; }

on_ac() {
    [[ -r $AC_ONLINE ]] || return 1     # unreadable -> treat as battery
    [[ $(< "$AC_ONLINE") == 1 ]]
}

dpms_state() {   # echoes 1 (on) or 0 (off), empty if unknown
    hyprctl monitors 2>/dev/null | grep -o 'dpmsStatus: [01]' | head -1 | awk '{print $2}'
}

# set_dpms on|off - idempotent despite the underlying call being a toggle.
set_dpms() {
    local want="$1" want_num cur
    [[ $want == on ]] && want_num=1 || want_num=0

    exec 9>"$LOCKFILE"
    flock 9

    cur=$(dpms_state)
    if [[ -z $cur ]]; then
        log "cannot read dpmsStatus (is Hyprland running?) - skipping"
        return 0
    fi
    if [[ $cur == "$want_num" ]]; then
        log "display already ${want} (dpmsStatus=$cur) - nothing to do"
        return 0
    fi

    if (( DRY )); then
        log "would toggle display ${want} (currently dpmsStatus=$cur)"
        return 0
    fi

    log "toggling display ${want} (was dpmsStatus=$cur)"
    hyprctl dispatch 'hl.dsp.dpms("on")'   # argument is ignored; this flips
}

# Returns 0 if this action should proceed for the current power source.
in_scope() {
    case "$scope" in
        always)  return 0 ;;
        battery)
            if on_ac; then
                # For "blank" a later unconditional listener picks this up on
                # AC. For "suspend" there deliberately is no AC equivalent -
                # plugged in, the machine stays awake (lid close still
                # suspends, via logind's HandleLidSwitchExternalPower).
                log "on AC - skipping this battery-scoped $action"
                return 1
            fi
            return 0
            ;;
        *) echo "unknown scope: $scope" >&2; exit 2 ;;
    esac
}

case "$action" in
    lock)
        in_scope || exit 0
        log "locking session (scope: $scope)"
        if (( DRY )); then log "would run: loginctl lock-session"; else loginctl lock-session; fi
        ;;
    presleep)
        # Runs from hypridle's before_sleep_cmd, while it still holds a delay
        # inhibitor, so sleeping here genuinely delays the suspend.
        #
        # Locking is not the slow part - the compositor stops showing clients
        # the moment the session lock is acquired. PAINTING is. The panel is
        # not blanked before an idle-suspend, so across s2idle it keeps
        # scanning out the last composited frame; if hyprlock has not drawn
        # one yet, that frame is the desktop and it is what comes back on
        # resume. This waits for hyprlock to exist and then gives it a moment
        # to put something on screen.
        #
        # BOUNDED, because this is holding up a suspend. systemd's
        # InhibitDelayMaxSec is 5s by default and blowing through it means
        # logind suspends anyway with the inhibitor ignored, so the total here
        # stays far under that: at most 1.5s of polling plus 0.4s of settle.
        log "locking before sleep"
        if (( DRY )); then
            log "would run: loginctl lock-session, then wait for hyprlock"
        else
            loginctl lock-session
            for _ in $(seq 1 30); do
                pidof hyprlock >/dev/null 2>&1 && break
                sleep 0.05
            done
            sleep 0.4
        fi
        ;;
    blank)
        in_scope || exit 0
        set_dpms off
        ;;
    wake)
        set_dpms on
        ;;
    suspend)
        in_scope || exit 0
        # systemctl suspend goes through logind, so it honours inhibitors:
        # a "block" inhibitor stops it outright, a "delay" one (NetworkManager,
        # UPower, hypridle's own before_sleep handling) just postpones it until
        # that handler is done. Verified allowed for this user without root
        # (pkcheck org.freedesktop.login1.suspend -> 0).
        #
        # No on-resume is needed for this listener: hypridle's after_sleep_cmd
        # already runs "idle-action.sh wake" when the machine comes back.
        log "suspending (scope: $scope)"
        if (( DRY )); then log "would run: systemctl suspend"; else systemctl suspend; fi
        ;;
    *)
        echo "usage: $0 {lock|blank|wake|presleep|suspend} [battery|always] [--dry-run]" >&2
        echo "       $0 wake [--dry-run]" >&2
        exit 2
        ;;
esac
