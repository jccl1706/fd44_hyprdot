#!/usr/bin/env bash
# =========================================================================
# thermal-log.sh - sample temperatures, fans and power over a real workload
# =========================================================================
#
# Usage:
#   bin/thermal-log.sh                       log to ~/thermal.log until Ctrl-C
#   bin/thermal-log.sh -o run.log -i 2       somewhere else, every 2 seconds
#   bin/thermal-log.sh -d 600                stop after ten minutes
#   bin/thermal-log.sh --summary run.log     read a log back as statistics
#   bin/thermal-log.sh --probe               say what it found and exit
#
# WHY THIS EXISTS. Fan curves and power limits are only as good as the
# measurement behind them, and the measurement that matters is a real workload
# rather than a synthetic one. A `yes` loop heats the CPU with the GPU idle; a
# benchmark loop does the opposite. Neither tells you what a game does to the
# case, which is the thing the exhaust fan is actually responding to.
#
# It was written to answer four questions, and the summary reports them:
#   - does anything throttle, and how close does it come?
#   - is a power limit binding, or is it a number that never applies?
#   - which side - CPU or GPU - is driving a max() mix profile?
#   - WHICH FAN IS THE NOISE: the case fans on their curves, or the graphics
#     card on its own firmware curve, which nothing here controls.
#
# SENSORS ARE FOUND BY NAME, NOT BY INDEX. /sys/class/hwmon/hwmonN numbering is
# assignment order and it reshuffles between boots: on the gaming desktop the
# Quadro has been hwmon2 and hwmon3 on consecutive boots, and reading the fixed
# path produced a confident page of numbers belonging to a different chip.
# Everything here resolves hwmon entries by their `name` file.
#
# FAN CHANNELS ARE DISCOVERED, not configured. Any channel reporting a non-zero
# reading is logged; empty headers are skipped. That keeps the script portable
# between machines whose fans are wired differently, and means it does not need
# to know that this desktop puts the CPU fan on Quadro channel 4.
#
# CPU POWER comes from the RAPL energy counter as a delta between samples, not
# as an instantaneous reading - the counter is cumulative microjoules and a raw
# value is meaningless. The file is root-only on most systems (energy readings
# are a side channel, CVE-2020-8694); without access the column reads 0 rather
# than failing. On the gaming desktop modules/gaming.nix opens it to the
# `gamemode` group for MangoHud, which is why it works there.

set -u

out="$HOME/thermal.log"
interval=5
duration=0
mode=log

while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -i) interval="$2"; shift 2 ;;
        -d) duration="$2"; shift 2 ;;
        --probe) mode=probe; shift ;;
        --summary) mode=summary; out="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'thermal-log.sh: unknown argument %s\n' "$1" >&2; exit 1 ;;
    esac
done

# --- finding things -------------------------------------------------------

hwmon_by_name() {
    for h in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$h/name" 2>/dev/null)" = "$1" ] && { printf '%s' "$h"; return 0; }
    done
    return 1
}

# The CPU package temperature, whatever drives it. k10temp's temp1 is Tctl,
# which is the one fan curves should read - temp3 is Tccd1 and runs about 10 C
# cooler, so a curve pointed at it acts late.
cpu_hwmon="$(hwmon_by_name k10temp || hwmon_by_name coretemp || true)"
cpu_temp="${cpu_hwmon:+$cpu_hwmon/temp1_input}"

have_nvidia=0
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 && have_nvidia=1
amd_hwmon="$(hwmon_by_name amdgpu || true)"

# Fan channels worth logging: any with a reading now. A header with nothing in
# it reports 0 forever and only makes the log wider.
fan_paths=(); fan_names=()
for h in /sys/class/hwmon/hwmon*; do
    n="$(cat "$h/name" 2>/dev/null)" || continue
    for f in "$h"/fan*_input; do
        [ -e "$f" ] || continue
        [ "$(cat "$f" 2>/dev/null || echo 0)" -gt 0 ] 2>/dev/null || continue
        ch="$(basename "$f" _input)"
        fan_paths+=("$h:$ch"); fan_names+=("$n/$ch")
    done
done

rapl=/sys/class/powercap/intel-rapl:0/energy_uj   # Intel's name; AMD Zen uses it

if [ "$mode" = probe ]; then
    printf 'CPU temp   : %s\n' "${cpu_temp:-(none found)}"
    printf 'GPU        : %s\n' \
        "$( [ "$have_nvidia" = 1 ] && echo "nvidia-smi" || echo "${amd_hwmon:-(none found)}" )"
    printf 'CPU power  : %s\n' "$( [ -r "$rapl" ] && echo "$rapl" || echo '(not readable - column will read 0)' )"
    printf 'fans       : %s\n' "${fan_names[*]:-(none spinning)}"
    exit 0
fi

# --- summary --------------------------------------------------------------

if [ "$mode" = summary ]; then
    [ -r "${out:-}" ] || { printf 'thermal-log.sh: cannot read %s\n' "${out:-<no file>}" >&2; exit 1; }
    awk '
    NR==1 { for (i=1;i<=NF;i++) col[i]=$i; ncol=NF; next }
    {
        for (i=2;i<=ncol;i++) {
            v=$i+0
            if (!(i in n) || v<mn[i]) mn[i]=v
            if (!(i in n) || v>mx[i]) mx[i]=v
            n[i]++; s[i]+=v; vals[i,n[i]]=v
        }
        rows++
    }
    END {
        if (!rows) { print "no samples"; exit }
        printf "%d samples\n\n", rows
        printf "  %-8s %8s %8s %8s\n", "column", "median", "min", "max"
        for (i=2;i<=ncol;i++) {
            cnt=n[i]
            for (a=1;a<=cnt;a++) for (b=a+1;b<=cnt;b++)
                if (vals[i,b]<vals[i,a]) { t=vals[i,a]; vals[i,a]=vals[i,b]; vals[i,b]=t }
            med = (cnt%2) ? vals[i,(cnt+1)/2] : (vals[i,cnt/2]+vals[i,cnt/2+1])/2
            printf "  %-8s %8.0f %8.0f %8.0f\n", col[i], med, mn[i], mx[i]
        }
    }' "$out"
    exit 0
fi

# --- logging --------------------------------------------------------------

{
    printf '%-7s %5s %5s' time cpuC cpuW
    [ "$have_nvidia" = 1 ] && printf ' %5s %5s %5s %5s %6s %6s' gpuC tlim gpuW gpu_ mhz gpufan
    [ -n "$amd_hwmon" ] && [ "$have_nvidia" = 0 ] && printf ' %5s' gpuC
    for nm in "${fan_names[@]}"; do printf ' %9s %4s' "${nm##*/}" pct; done
    printf '\n'
} > "$out"

start=$(date +%s)
e0=$(cat "$rapl" 2>/dev/null || echo 0); t0=$(date +%s%N)

printf 'logging to %s every %ss - Ctrl-C to stop\n' "$out" "$interval" >&2
while :; do
    sleep "$interval"

    e1=$(cat "$rapl" 2>/dev/null || echo 0); t1=$(date +%s%N)
    cw=$(awk -v a="$e0" -v b="$e1" -v x="$t0" -v y="$t1" \
         'BEGIN{d=(y-x)/1e9; printf "%.0f", (d>0 && b>=a) ? ((b-a)/1e6)/d : 0}')
    e0=$e1; t0=$t1

    line=$(printf '%-7s %5s %5s' "$(( $(date +%s) - start ))s" \
        "$( [ -n "$cpu_temp" ] && echo $(( $(cat "$cpu_temp")/1000 )) || echo 0 )" "$cw")

    if [ "$have_nvidia" = 1 ]; then
        # tlimit is DEGREES OF HEADROOM before the card throttles, counting
        # down - not a temperature. It is the honest throttle indicator.
        # THE CARD'S OWN FAN IS LOGGED TOO, and leaving it out was a real gap.
        # This tool answers "is the machine hot, and what is making the noise",
        # and on a gaming PC the loudest thing is usually the graphics card -
        # whose fan runs on its firmware curve, under nobody's control. A log of
        # the case fans alone cannot tell you which fan you are hearing, which
        # is exactly the question it failed to answer after a Cyberpunk session.
        read -r gt tl gw gu gc gf <<<"$(nvidia-smi \
            --query-gpu=temperature.gpu,temperature.gpu.tlimit,power.draw,utilization.gpu,clocks.current.graphics,fan.speed \
            --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ,)"
        line+=$(printf ' %5s %5s %5s %5s %6s %6s' "${gt:-0}" "${tl:-0}" "${gw%.*}" "${gu:-0}" "${gc:-0}" "${gf:-0}")
    elif [ -n "$amd_hwmon" ]; then
        line+=$(printf ' %5s' "$(( $(cat "$amd_hwmon/temp1_input" 2>/dev/null || echo 0)/1000 ))")
    fi

    for spec in "${fan_paths[@]}"; do
        h="${spec%%:*}"; ch="${spec##*:}"; idx="${ch#fan}"
        rpm=$(cat "$h/${ch}_input" 2>/dev/null || echo 0)
        pwm=$(cat "$h/pwm$idx" 2>/dev/null || echo 0)
        line+=$(printf ' %9s %4s' "$rpm" "$(( pwm * 100 / 255 ))")
    done

    printf '%s\n' "$line" >> "$out"

    [ "$duration" -gt 0 ] && [ $(( $(date +%s) - start )) -ge "$duration" ] && break
done
