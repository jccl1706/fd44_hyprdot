#!/usr/bin/env bash
# =========================================================================
# thermal.sh - what the graphics card and the CPU are doing, in one line
# =========================================================================
#
# Usage:  bin/thermal.sh check     temperatures and load, as JSON
#         bin/thermal.sh report    the full picture, for reading
#         bin/thermal.sh open      that report, live, in a terminal
#
# The bar's thermal readout (quickshell/Thermals.qml) calls `check` on a timer
# and `open` when clicked. bin/thermal-log.sh is the other half of this: that
# one SAMPLES over a workload and reports statistics afterwards, which is what
# a fan curve is designed from. This one answers "what is it doing right now".
#
# THE GPU IS NOT IN hwmon, which is the first thing anyone assumes. On the
# gaming desktop /sys/class/hwmon holds nvme, nct6799 (the board), k10temp (the
# CPU), spd5118 (the DIMMs) and `quadro` - which is the Aquacomputer fan
# controller, NOT the Quadro-branded card someone might expect. The NVIDIA
# driver publishes nothing there, so the GPU's numbers come from nvidia-smi:
# one call, measured at 43ms, which is what makes a five-second poll
# reasonable.
#
# EVERYTHING ELSE IS READ FROM sysfs BY NAME. hwmonN numbering is assignment
# order and reshuffles between boots - bin/thermal-log.sh documents the card
# moving between hwmon2 and hwmon3 on consecutive boots - so a fixed path
# produces a confident page of numbers belonging to a different chip.
#
# NO GPU MEANS NO READOUT, not an error: the laptop has no discrete card, and
# the bar draws nothing there rather than showing half an answer.

set -uo pipefail

src="${BASH_SOURCE[0]:-}"
if [[ -n $src && -e $src ]]; then
    self="$(cd "$(dirname "$src")" && pwd)"
else
    self="${FD44_HYPRDOT_DIR:-$HOME/Work/fd44_hyprdot}/bin"
fi

# The hwmon directory whose `name` is $1, or nothing.
hwmon_by_name() {
    local want="$1" h
    for h in /sys/class/hwmon/hwmon*; do
        [[ -r $h/name ]] || continue
        [[ "$(cat "$h/name" 2>/dev/null)" == "$want" ]] && { printf '%s' "$h"; return 0; }
    done
    return 1
}

read_milli() { # file -> whole degrees, or nothing
    local f="$1" v
    [[ -r $f ]] || return 1
    v="$(cat "$f" 2>/dev/null)" || return 1
    [[ $v =~ ^-?[0-9]+$ ]] || return 1
    printf '%s' $(( v / 1000 ))
}

cmd_check() {
    local gpu_temp="" gpu_util="" gpu_power="" gpu_clock="" gpu_name=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        local line
        line="$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,clocks.current.graphics \
                --format=csv,noheader,nounits 2>/dev/null | head -1)"
        if [[ -n $line ]]; then
            IFS=',' read -r gpu_temp gpu_util gpu_power gpu_clock <<<"${line// /}"
        fi
    fi

    local cpu_temp="" h
    if h="$(hwmon_by_name k10temp)" || h="$(hwmon_by_name coretemp)"; then
        cpu_temp="$(read_milli "$h/temp1_input" || true)"
    fi

    # The case fans, from the board's own chip. Zero is a real answer - these
    # boards stop the fans entirely below a threshold - so it is reported
    # rather than treated as missing.
    local fan=""
    if h="$(hwmon_by_name nct6799)" || h="$(hwmon_by_name nct6687)"; then
        [[ -r $h/fan1_input ]] && fan="$(cat "$h/fan1_input" 2>/dev/null)"
    fi

    # `ok` is what the bar reads: no GPU, no readout.
    local ok=false
    [[ -n $gpu_temp ]] && ok=true

    printf '{"ok":%s,"gpu_temp":%s,"gpu_util":%s,"gpu_power":%s,"gpu_clock":%s,"cpu_temp":%s,"fan":%s}\n' \
        "$ok" "${gpu_temp:-null}" "${gpu_util:-null}" "${gpu_power:-null}" \
        "${gpu_clock:-null}" "${cpu_temp:-null}" "${fan:-null}"
}

cmd_report() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        printf '\033[1;32m==>\033[0m %s\n\n' "graphics card"
        nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,power.draw,power.limit,clocks.current.graphics,memory.used,memory.total \
            --format=csv 2>/dev/null | sed 's/^/  /'
    fi
    printf '\n\033[1;32m==>\033[0m %s\n\n' "everything the board reports"
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | sed 's/^/  /'
    else
        local h n
        for h in /sys/class/hwmon/hwmon*; do
            n="$(cat "$h/name" 2>/dev/null)" || continue
            printf '  %-12s %s\n' "$n" "$(read_milli "$h/temp1_input" 2>/dev/null | sed 's/$/C/')"
        done
    fi
    printf '\n\033[2m%s\033[0m\n' "  for a fan curve, sample a real workload instead: bin/thermal-log.sh"
}

cmd_open() {
    # LIVE, because a single snapshot of a temperature is the least useful
    # form of it - what anyone opening this wants to see is the number moving
    # while a game runs.
    exec "$self/in-terminal.sh" "Temperatures" \
        watch -n 2 -t "$self/thermal.sh" report
}

case "${1:-check}" in
    check)  cmd_check ;;
    report) cmd_report ;;
    open)   cmd_open ;;
    -h|--help|help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) printf 'thermal: unknown command: %s (check, report, open)\n' "$1" >&2; exit 2 ;;
esac
