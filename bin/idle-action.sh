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
#   idle-action.sh suspend-if-idle            suspend if on battery with the
#                                             display still idle-blanked
#   idle-action.sh wake                       turn the display back on
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
    # NO BATTERY AT ALL means permanently on mains - a desktop, or a VM. That
    # is NOT the same as "the AC file is unreadable", which is how this used to
    # decide, and the difference matters a great deal: every battery-scoped
    # listener fired on such a machine, including the idle SUSPEND. A desktop
    # that suspends itself because it cannot find a battery is worse than one
    # that never suspends at all.
    #
    # Found by a VM test - the guest has neither ACAD nor BAT*, idled into the
    # battery lock at 5:00 and the battery blank at 5:30, and the display did
    # not come back. The installer supports machine=desktop, so this was
    # reachable on real hardware too, not only under qemu.
    #
    # Checked before the AC file, because a machine with no battery has no
    # meaningful AC state either - some report AC offline regardless.
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null || return 0

    # There IS a battery. Now an unreadable AC file genuinely does mean
    # "assume battery" - the cautious reading, since guessing AC on a laptop
    # means never suspending and flattening it in a bag.
    [[ -r $AC_ONLINE ]] || return 1
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
    suspend-if-idle)
        # Scheduled by power-mode.sh when the charger is pulled out while the
        # display is already idle-blanked: the case where hypridle's own
        # suspend listener has ALREADY fired this idle period - on AC, so it
        # skipped - and will not fire again. See the note in power-mode.sh.
        #
        # Both conditions are re-read now rather than trusted from when this
        # was scheduled. The display being off is what "still idle" means
        # here: any input since the blank ran hypridle's wake and turned it on.
        if on_ac; then
            log "back on AC - not suspending"
            exit 0
        fi
        cur=$(dpms_state)
        if [[ $cur == 1 ]]; then
            log "display is on again - someone came back, not suspending"
            exit 0
        elif [[ -z $cur ]]; then
            log "cannot read the display state - not suspending"
            exit 0
        fi
        log "still idle on battery since the charger was pulled - suspending"
        if (( DRY )); then log "would run: systemctl suspend"; else systemctl suspend; fi
        ;;
    *)
        echo "usage: $0 {lock|blank|wake|suspend} [battery|always] [--dry-run]" >&2
        echo "       $0 wake [--dry-run]" >&2
        exit 2
        ;;
esac
