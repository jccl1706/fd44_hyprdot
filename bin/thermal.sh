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

# The palette this report is drawn in. The first version used inline escapes
# at each printf, which was fine for two headings and unreadable once there
# were bars, labels and three severities.
green=$'\033[1;32m'; yellow=$'\033[1;33m'; red=$'\033[1;31m'
dim=$'\033[2m';      bold=$'\033[1m';     reset=$'\033[0m'

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

# A BAR, NOT A TABLE OF NUMBERS. nvidia-smi's own CSV is what this printed
# first, and reading it meant counting commas to find which field was the
# temperature - on a display that refreshes every two seconds, which is the
# one place a person should not be parsing. A number with a bar beside it
# answers "is that a lot" without arithmetic, and the limit is drawn in rather
# than remembered: 600 W means nothing until you see how much of it is used.
bar() { # value max width colour
    local v="$1" max="$2" w="${3:-20}" colour="${4:-}" filled i out=""
    [[ $v =~ ^[0-9.]+$ && $max =~ ^[0-9.]+$ ]] || { printf '%*s' "$w" ""; return; }
    filled=$(awk -v v="$v" -v m="$max" -v w="$w" 'BEGIN{ f=int(v/m*w); if(f<0)f=0; if(f>w)f=w; print f }')
    for ((i = 0; i < filled; i++)); do out+="█"; done
    for ((i = filled; i < w; i++)); do out+="·"; done
    printf '%s%s%s' "$colour" "$out" "$reset"
}

# Which colour a temperature deserves. The thresholds are the bar's, so the
# terminal and the pill never disagree about what counts as hot.
temp_colour() {
    local t="$1"
    [[ $t =~ ^[0-9]+$ ]] || { printf '%s' "$dim"; return; }
    (( t >= 83 )) && { printf '%s' "$red"; return; }
    (( t >= 70 )) && { printf '%s' "$yellow"; return; }
    printf '%s' "$green"
}

cmd_report() {
    local name temp util power limit clock vmem vtotal
    if command -v nvidia-smi >/dev/null 2>&1; then
        IFS=',' read -r name temp util power limit clock vmem vtotal < <(
            nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,power.draw,power.limit,clocks.current.graphics,memory.used,memory.total \
                --format=csv,noheader,nounits 2>/dev/null | head -1)
        name="${name# }"; temp="${temp# }"; util="${util# }"; power="${power# }"
        limit="${limit# }"; clock="${clock# }"; vmem="${vmem# }"; vtotal="${vtotal# }"
    fi

    if [[ -n ${name:-} ]]; then
        printf '\n  %s%s%s\n\n' "$bold" "$name" "$reset"
        printf '  %-7s %s%5s°%s  %s  %sthrottles at 83°%s\n' \
            "temp"  "$(temp_colour "$temp")" "$temp" "$reset" \
            "$(bar "$temp" 100 22 "$(temp_colour "$temp")")" "$dim" "$reset"
        printf '  %-7s %5s%%  %s\n' \
            "load"  "$util"  "$(bar "$util" 100 22 "$green")"
        printf '  %-7s %5.0fW  %s  %sof %.0f W%s\n' \
            "power" "$power" "$(bar "$power" "$limit" 22 "$green")" "$dim" "$limit" "$reset"
        printf '  %-7s %5s MHz\n' "clock" "$clock"
        printf '  %-7s %5.1f / %.1f GiB  %s\n' \
            "vram"  "$(awk -v m="$vmem" 'BEGIN{print m/1024}')" \
            "$(awk -v t="$vtotal" 'BEGIN{print t/1024}')" \
            "$(bar "$vmem" "$vtotal" 22 "$green")"
    fi

    # Everything else the machine measures, on one line each - by NAME, since
    # hwmonN numbering reshuffles between boots.
    printf '\n  %sthe rest of the machine%s\n\n' "$bold" "$reset"
    local h n t label
    for h in /sys/class/hwmon/hwmon*; do
        n="$(cat "$h/name" 2>/dev/null)" || continue
        t="$(read_milli "$h/temp1_input" 2>/dev/null)" || continue
        [[ -n $t ]] || continue
        case "$n" in
            k10temp|coretemp) label="cpu" ;;
            nvme)             label="nvme" ;;
            nct6799|nct6687)  label="board" ;;
            spd5118)          label="memory" ;;
            quadro)           label="fan hub" ;;
            *)                label="$n" ;;
        esac
        # Truncated to the column, because a driver name is not always short
        # - iwlwifi_1 pushed its own row one character out of line, which on a
        # screen full of aligned bars is the only thing the eye sees.
        printf '  %-9.9s %s%4s°%s  %s\n' \
            "$label" "$(temp_colour "$t")" "$t" "$reset" "$(bar "$t" 100 22 "$(temp_colour "$t")")"
    done

    local fan
    for h in /sys/class/hwmon/hwmon*; do
        [[ "$(cat "$h/name" 2>/dev/null)" =~ ^nct ]] || continue
        [[ -r $h/fan1_input ]] || continue
        fan="$(cat "$h/fan1_input" 2>/dev/null)"
        printf '  %-9.9s %4s rpm  %s\n' "fans" "$fan" \
            "$( (( fan == 0 )) && printf '%sstopped - below the curve%s' "$dim" "$reset" )"
        break
    done

    printf '\n  %sfor a fan curve, sample a real workload: bin/thermal-log.sh%s\n' "$dim" "$reset"
}

cmd_open() {
    # LIVE, because a single snapshot of a temperature is the least useful
    # form of it - what anyone opening this wants to see is the number moving
    # while a game runs.
    # -c, OR THE COLOURS ARE PRINTED RATHER THAN APPLIED. watch strips escape
    # sequences unless told to keep them, so without it the heading arrives as
    # a literal "[1;32m==>[0m" - seen on screen before this was added.
    # -t drops watch's own header, which would repeat the command line above a
    # report that already says what it is.
    exec "$self/in-terminal.sh" "Temperatures" \
        watch -c -n 2 -t "$self/thermal.sh" report
}

case "${1:-check}" in
    check)  cmd_check ;;
    report) cmd_report ;;
    open)   cmd_open ;;
    -h|--help|help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) printf 'thermal: unknown command: %s (check, report, open)\n' "$1" >&2; exit 2 ;;
esac
