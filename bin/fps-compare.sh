#!/usr/bin/env bash
# =========================================================================
# fps-compare.sh - turn MangoHud logs into a comparison you can trust
# =========================================================================
#
# Usage:
#   bin/fps-compare.sh <path> [<path> ...]
#   bin/fps-compare.sh fedora=~/logs/fedora nixos=~/logs/nixos
#
# A path is a CSV or a directory of them. Naming a group is optional; with
# exactly two groups it also prints the difference between them.
#
# WHY THIS AND NOT THE AVERAGE. An average frame rate hides the thing you
# actually feel. A run that holds 100 fps and one that alternates 140 and 60
# average the same and play nothing alike. The percentiles are the point.
#
# HOW THE NUMBERS ARE DEFINED. From the frametime column, not the fps column:
# MangoHud's fps field is a smoothed counter, while frametime is what was
# actually measured, and the 1% low is defined in terms of it.
#
#   avg         frames / total time, which is the only honest "average fps":
#               the mean of a per-frame fps column over-weights fast frames,
#               because a 200 fps frame occupies half the time of a 100 fps one
#               and yet counts once either way.
#   median      the middle frame.
#   1% low      the 99th-percentile frametime expressed as fps - the same
#               definition MangoHud shows on screen, so the two agree.
#   0.1% low    the 99.9th percentile, which is where stutter lives.
#   worst 1%    the mean of the slowest 1% of frames. Always lower than the
#               1% low above; quoted because people mean either by "1% low"
#               and comparing one against the other is a common mistake.
#
# Per-file rows come first so run-to-run spread is visible, and the verdict is
# made against that measured spread rather than a fixed percentage. A fixed
# threshold is wrong here, and specifically wrong at the tail: the 0.1% low is
# the worst frame in a thousand, so 0.7 ms becomes a 7% swing in fps and reads
# like a result when it is one slightly late frame. The frametime percentiles
# printed underneath each group are the same numbers without that distortion -
# compare p99.9 in milliseconds before believing anything about a 0.1% low.

set -euo pipefail

die() { printf '\033[1;31mfps-compare:\033[0m %s\n' "$*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The frametimes of one CSV, one per line, in milliseconds.
#
# MangoHud writes two metadata lines before the real header, so the data starts
# after the line beginning "fps," - found rather than assumed, because that
# preamble has gained columns between releases. The frametime column is located
# by name for the same reason.
frametimes() {
    local f="$1" h idx
    h="$(grep -n '^fps,' "$f" 2>/dev/null | head -1 | cut -d: -f1 || true)"
    [[ -n $h ]] || return 1
    idx="$(sed -n "${h}p" "$f" | tr ',' '\n' | grep -nx 'frametime' | head -1 | cut -d: -f1 || true)"
    [[ -n $idx ]] || return 1
    # Drop anything non-numeric or zero: a log cut off mid-write ends in a
    # partial line, and a zero frametime would divide by zero below.
    tail -n +"$((h + 1))" "$f" | cut -d, -f"$idx" \
        | grep -E '^[0-9]+(\.[0-9]+)?$' | awk '$1 > 0'
}

# The metadata line, so the report can say what was actually measured.
meta() {
    local f="$1"
    head -1 "$f" | grep -q '^os,' || return 1
    sed -n '2p' "$f"
}

# Percentile of a sorted file: pct_line <sorted-file> <count> <percentile>
pct_line() {
    local file="$1" n="$2" p="$3" i
    i="$(awk -v n="$n" -v p="$p" 'BEGIN{ i=int(n*p/100 + 0.5); if (i<1) i=1; if (i>n) i=n; print i }')"
    sed -n "${i}p" "$file"
}

# stats <sorted-frametime-file> -> "frames seconds avg median low1 low01 worst1"
# The file is sorted ASCENDING, so the slowest frames - the ones that matter -
# are at the end.
stats() {
    local sorted="$1" n total med p99 p999 k
    n="$(wc -l < "$sorted")"
    (( n > 0 )) || return 1
    total="$(awk '{s+=$1} END{printf "%.6f", s/1000}' "$sorted")"
    med="$(pct_line "$sorted" "$n" 50)"
    p99="$(pct_line "$sorted" "$n" 99)"
    p999="$(pct_line "$sorted" "$n" 99.9)"
    # mean of the slowest 1%: the last k lines, k rounded up to at least one
    k="$(awk -v n="$n" 'BEGIN{ k=int(n*0.01 + 0.5); if (k<1) k=1; print k }')"
    tail -n "$k" "$sorted" \
        | awk -v n="$n" -v total="$total" -v med="$med" -v p99="$p99" -v p999="$p999" \
            '{ w+=$1; c++ }
             END {
               printf "%d %.1f %.1f %.1f %.1f %.1f %.1f",
                 n, total, n/total, 1000/med, 1000/p99, 1000/p999, (c ? 1000/(w/c) : 0)
             }'
}

row() { printf '  %-22s %8s %8s %8s %8s %8s %8s %8s\n' "$@"; }

# --- collect the groups ----------------------------------------------------
(( $# )) || die "usage: fps-compare.sh [name=]<csv-or-dir> [[name=]<csv-or-dir> ...]"

names=(); dirs=()
for arg in "$@"; do
    if [[ $arg == *=* && -e ${arg#*=} ]]; then
        names+=("${arg%%=*}"); dirs+=("${arg#*=}")
    else
        names+=("$(basename "${arg%/}")"); dirs+=("$arg")
    fi
done

# max - min of a list, printed with one decimal. One value means no spread.
spread() {
    printf '%s\n' "$@" | awk 'NR==1{mn=mx=$1} {if($1<mn)mn=$1; if($1>mx)mx=$1} END{printf "%.1f", mx-mn}'
}

declare -a g_avg g_low1 g_low01 g_frames g_p999 g_p99 g_med
declare -a g_spread_avg g_spread_low1 g_spread_low01
declare -a run_avg run_low1 run_low01
for gi in "${!dirs[@]}"; do
    path="${dirs[$gi]}"
    [[ -e $path ]] || die "no such path: $path"
    # MangoHud writes <name>_summary.csv beside every log: its own precomputed
    # figures, not frame data. Skipped rather than reported as unreadable.
    mapfile -t files < <(if [[ -d $path ]]; then find "$path" -maxdepth 1 -name '*.csv' ! -name '*_summary.csv' | sort; else printf '%s\n' "$path"; fi)
    (( ${#files[@]} )) || die "no CSV files in $path"

    printf '\n\033[1m%s\033[0m  (%d file%s)\n' "${names[$gi]}" "${#files[@]}" "$( (( ${#files[@]} == 1 )) || echo s)"
    m="$(meta "${files[0]}" 2>/dev/null || true)"
    [[ -n $m ]] && printf '  %s\n' "$m"
    row "run" "frames" "seconds" "avg" "median" "1% low" "0.1% low" "worst 1%"

    : > "$tmp/all"
    run_avg=(); run_low1=(); run_low01=()
    for f in "${files[@]}"; do
        if ! frametimes "$f" > "$tmp/one" 2>/dev/null || [[ ! -s $tmp/one ]]; then
            row "$(basename "$f")" "-" "-" "-" "-" "-" "-" "-"
            continue
        fi
        cat "$tmp/one" >> "$tmp/all"
        sort -n "$tmp/one" > "$tmp/one.s"
        read -r n s avg med l1 l01 w1 <<<"$(stats "$tmp/one.s")"
        row "$(basename "$f" .csv | cut -c1-22)" "$n" "$s" "$avg" "$med" "$l1" "$l01" "$w1"
        run_avg+=("$avg"); run_low1+=("$l1"); run_low01+=("$l01")
    done

    sort -n "$tmp/all" > "$tmp/all.s"
    read -r n s avg med l1 l01 w1 <<<"$(stats "$tmp/all.s")"
    printf '  %s\n' "$(printf '%.0s-' {1..86})"
    row "ALL" "$n" "$s" "$avg" "$med" "$l1" "$l01" "$w1"

    # The same distribution as frametimes, which is what was measured and the
    # only form in which the tail can be read honestly.
    printf '  frametime ms           median %5.2f   p95 %5.2f   p99 %5.2f   p99.9 %5.2f   max %6.2f\n' \
        "$(pct_line "$tmp/all.s" "$n" 50)" "$(pct_line "$tmp/all.s" "$n" 95)" \
        "$(pct_line "$tmp/all.s" "$n" 99)" "$(pct_line "$tmp/all.s" "$n" 99.9)" \
        "$(tail -1 "$tmp/all.s")"

    # Spread between repeats of THIS configuration: the yardstick any
    # difference between configurations has to clear.
    if (( ${#run_avg[@]} > 1 )); then
        printf '  spread across runs     avg %.1f   1%% low %.1f   0.1%% low %.1f   (fps, max - min)\n' \
            "$(spread "${run_avg[@]}")" "$(spread "${run_low1[@]}")" "$(spread "${run_low01[@]}")"
    fi

    g_frames[$gi]="$n"; g_avg[$gi]="$avg"; g_low1[$gi]="$l1"; g_low01[$gi]="$l01"
    g_p999[$gi]="$(pct_line "$tmp/all.s" "$n" 99.9)"
    g_p99[$gi]="$(pct_line "$tmp/all.s" "$n" 99)"
    g_med[$gi]="$(pct_line "$tmp/all.s" "$n" 50)"
    g_spread_avg[$gi]="$(spread "${run_avg[@]}")"
    g_spread_low1[$gi]="$(spread "${run_low1[@]}")"
    g_spread_low01[$gi]="$(spread "${run_low01[@]}")"
done

# --- and the difference, if there are exactly two --------------------------
if (( ${#dirs[@]} == 2 )); then
    printf '\n\033[1m%s vs %s\033[0m\n' "${names[0]}" "${names[1]}"
    printf '  %-12s %10s %10s %10s %9s %9s   %s\n' \
        "metric" "${names[0]:0:10}" "${names[1]:0:10}" "diff" "percent" "spread" "verdict"
    for pair in "avg:${g_avg[0]}:${g_avg[1]}:${g_spread_avg[0]:-0}:${g_spread_avg[1]:-0}" \
                "1% low:${g_low1[0]}:${g_low1[1]}:${g_spread_low1[0]:-0}:${g_spread_low1[1]:-0}" \
                "0.1% low:${g_low01[0]}:${g_low01[1]}:${g_spread_low01[0]:-0}:${g_spread_low01[1]:-0}"; do
        IFS=: read -r label a b sa sb <<<"$pair"
        # The yardstick is the WIDER of the two systems' own run-to-run spreads.
        # A difference smaller than that is not distinguishable from running the
        # same benchmark twice on one machine.
        awk -v l="$label" -v a="$a" -v b="$b" -v sa="$sa" -v sb="$sb" \
            -v n0="${names[0]}" -v n1="${names[1]}" \
            'BEGIN{ d=b-a; p=(a? d*100/a : 0); s=(sa>sb?sa:sb); ad=(d<0?-d:d);
                    v = (ad <= s) ? "within run-to-run spread" : (d>0 ? n1 " ahead" : n0 " ahead");
                    printf "  %-12s %10.1f %10.1f %+10.1f %+8.1f%% %9.1f   %s\n", l, a, b, d, p, s, v }'
    done

    printf '\n  the same tail as frametimes, undistorted:\n'
    printf '  %-12s %10s %10s %10s\n' "percentile" "${names[0]:0:10}" "${names[1]:0:10}" "diff ms"
    for pair in "median:${g_med[0]}:${g_med[1]}" "p99:${g_p99[0]}:${g_p99[1]}" "p99.9:${g_p999[0]}:${g_p999[1]}"; do
        IFS=: read -r label a b <<<"$pair"
        awk -v l="$label" -v a="$a" -v b="$b" \
            'BEGIN{ printf "  %-12s %10.2f %10.2f %+10.2f\n", l, a, b, b-a }'
    done
    printf '\n  A percentage on a 0.1%% low exaggerates: it is the worst frame in a\n'
    printf '  thousand, so a fraction of a millisecond reads as several percent.\n'
fi
