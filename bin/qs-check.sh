#!/usr/bin/env bash
# =========================================================================
# qs-check.sh - load the shell config and fail if it complains
# =========================================================================
#
# Usage:  bin/qs-check.sh [path to config dir or shell.qml]
#
# Exits 0 when the configuration loads clean, non-zero with the offending
# lines when it does not. Defaults to the quickshell/ folder beside this
# script, so from the repository it is just `bin/qs-check.sh`.
#
# WHY THIS EXISTS. The expensive failures in this repository are not crashes,
# they are configs that load WRONG, because nothing tells you until you look
# at the bar:
#
#   - `readonly property real fixedWidth` with a Behavior on it. A Behavior
#     animates by WRITING, so the assignment was refused, the whole config
#     failed to load, and the desktop had no bar at all for minutes until
#     `qs -p` was run by hand and printed the reason.
#
#   - a tray menu row built to the card's width instead of the column's,
#     which drew a hairline of separator on the wallpaper outside the card.
#     That one loaded silently and shipped.
#
# The first kind is exactly what a load produces an error for. This turns
# "run it and look" into something a pre-commit hook can do in five seconds.
# The second kind needs eyes on a screenshot and is not what this is for.
#
# IN A COMPOSITOR OF ITS OWN, and that is the whole difficulty. The config is
# a layer-shell client: it needs a Wayland compositor, and running it against
# the live one puts a second bar on screen over the real one and registers the
# global shortcuts twice. The alternatives were measured rather than assumed:
#
#   QT_QPA_PLATFORM=offscreen   loads, then EXITS 255 in teardown
#                               ("Trying to construct an instance of an
#                               invalid type") whether the config is good or
#                               bad - it cannot tell them apart, so it is
#                               useless as a test.
#
#   a second Hyprland           a real compositor on a Wayland socket of its
#                               own, which the shell then loads into.  <- this
#
# AND IT NESTS RATHER THAN RUNNING HEADLESS, which was worth finding out the
# hard way. Hyprland uses Aquamarine, not wlroots, so WLR_BACKENDS=headless is
# ignored, and AQ_BACKENDS, AQ_BACKEND and AQ_FORCE_BACKEND do nothing either:
# inside a session it opens a real window of class "aquamarine", measured at
# ~800ms of a 1.4s run, on whatever workspace you were looking at. A window
# that flashes up at every commit is how a useful check gets switched off, so
# hypr/rules.lua sends that class to a silent special workspace and it is never
# seen. Verified by watching `hyprctl clients` through a run.
#
# The other side of nesting is that it needs a session to nest INTO: over ssh
# with no WAYLAND_DISPLAY, Aquamarine falls through to DRM, finds no seat and
# aborts with "CBackend::create() failed!". That is not a broken config, so it
# exits 2 and says so rather than failing the commit.
#
# WHAT COUNTS AS FAILURE. "Configuration Loaded" must appear, and no WARN or
# ERROR lines may - except two that are not faults in the config:
#
#   the notification-server clash   a second instance cannot own
#                                   org.freedesktop.Notifications while the
#                                   real shell has it, and it says so every time
#
#   GlobalShortcut, under niri ONLY shell.qml's shortcuts speak
#                                   hyprland_global_shortcuts_v1, which niri
#                                   does not implement. On a niri machine the
#                                   binds live in niri/config.kdl and call
#                                   `qs ipc` instead. Under Hyprland the same
#                                   warning would be a real fault, so it is
#                                   filtered only for the compositor that
#                                   cannot answer it. The same applies to
#                                   quickshell's Hyprland module warning that
#                                   HYPRLAND_INSTANCE_SIGNATURE is unset:
#                                   Compositor.qml speaks to whichever
#                                   compositor is running, and under niri that
#                                   module simply has nothing to connect to.

set -uo pipefail

# Where the repository is, from this script's own location.
# Resolved through any symlink: ~/.local/bin/qs-check is a link to this file,
# and the parent of the LINK's directory is ~/.local, not the repository.
src="$(readlink -f "${BASH_SOURCE[0]:-}" 2>/dev/null || true)"
if [[ -n $src && -e $src ]]; then
    root="$(cd "$(dirname "$src")/.." && pwd)"
else
    root="${FD44_HYPRDOT_DIR:-$HOME/Work/fd44_hyprdot}"
fi

config="${1:-$root/quickshell}"

# How long to give each stage. The load itself takes about a second; the rest
# is starting a compositor.
#
# RAISED FROM 8, because 8 was not enough and the way it failed was confusing.
# A nested Hyprland usually has its socket in two or three seconds, but under
# load - another compositor starting, a model loading, a build running - it can
# take longer, and then this exits 2 with "no new Wayland socket". The
# pre-commit hook captures that stderr, prints "the configuration does not load"
# and re-runs visibly, where it passes. So a QML commit intermittently needed two
# attempts and the message blamed the config, which was fine all along.
#
# Reproduced deliberately on 2026-10-06 by running this while nested compositors
# were being started and stopped nearby: it failed, and the immediate retry with
# nothing stale left behind passed.
compositor_wait=25
load_wait=20

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
log()   { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[[ -e $config ]] || { red "qs-check: no such config: $config"; exit 2; }
command -v qs >/dev/null       || { red "qs-check: quickshell (qs) is not installed"; exit 2; }
# WHICHEVER COMPOSITOR THIS MACHINE HAS. The check needs a real one to nest in
# (see the header) and does not care which: it watches for a new Wayland socket
# and loads the shell into it. Hyprland first, because that is what this was
# written against and what most of these machines run; niri because framework00
# has no Hyprland at all, and a check that cannot run on the machine you are
# committing from is a check that stops being run.
if command -v Hyprland >/dev/null; then
    comp=hyprland
elif command -v niri >/dev/null; then
    comp=niri
else
    red "qs-check: neither Hyprland nor niri is installed"; exit 2
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# WHAT THE SESSION'S OWN ENVIRONMENT SAYS, BEFORE A NESTED COMPOSITOR LIES
# ABOUT IT. Hyprland exports WAYLAND_DISPLAY and friends into the systemd user
# manager when it starts - correct for the session's compositor, catastrophic
# for a throwaway one: the nested instance gets wayland-2, exports it, exits,
# and every app launched afterwards through systemd-run is pointed at a socket
# that no longer exists.
#
# Measured, not guessed. On the gaming desktop the app launcher stopped
# starting kitty, with "Wayland: Failed to connect to display" in the unit's
# journal, and:
#
#     before qs-check: WAYLAND_DISPLAY=wayland-1
#     after  qs-check: WAYLAND_DISPLAY=wayland-2      (no such socket)
#
# So the session's values are saved here and put back in cleanup.
declare -A saved_env=()
save_session_env() {
    local v value
    for v in WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP; do
        value="$(systemctl --user show-environment 2>/dev/null | sed -n "s/^$v=//p")"
        [[ -n $value ]] && saved_env["$v"]="$value"
    done
}

restore_session_env() {
    local v now
    for v in "${!saved_env[@]}"; do
        now="$(systemctl --user show-environment 2>/dev/null | sed -n "s/^$v=//p")"
        [[ $now == "${saved_env[$v]}" ]] && continue
        systemctl --user set-environment "$v=${saved_env[$v]}" 2>/dev/null || true
        # The bus keeps its own copy, and an app started by a .desktop
        # activation reads that one rather than the manager's.
        dbus-update-activation-environment --systemd "$v" 2>/dev/null || true
    done
}

work="$(mktemp -d)"
hl_pid=""
sig=""
cleanup() {
    [[ -n $hl_pid ]] && kill "$hl_pid" 2>/dev/null
    # The compositor's children go with it, but give them a moment to notice
    # before the socket disappears under them.
    sleep 0.3
    # Hyprland does not tidy its instance directory on the way out, so a check
    # run before every commit would otherwise leave a litter of them in
    # $XDG_RUNTIME_DIR/hypr - harmless on tmpfs, but they are also what any
    # `ls -t` lookup of "the current instance" trips over, including this
    # script's own.
    [[ -n $sig && -d $XDG_RUNTIME_DIR/hypr/$sig ]] && rm -rf "${XDG_RUNTIME_DIR:?}/hypr/${sig:?}"
    rm -rf "$work"

    # AFTER THE COMPOSITOR IS GONE, NOT BEFORE. Restoring first looks right
    # and does nothing: Hyprland writes its environment into the user manager
    # AGAIN on the way out, so a value put back while it was still running was
    # overwritten by its own shutdown. Traced on the desktop:
    #
    #     1 start:          wayland-1
    #     2 nested running: wayland-2
    #     3 after restore:  wayland-1
    #     4 after kill:     wayland-2      <- it rewrote it while dying
    #
    # So this waits for the process to actually be gone, and then checks its
    # own work - a late write would otherwise leave the session pointing at a
    # socket that no longer exists, which is what stopped the app launcher
    # from starting anything.
    local n
    for n in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$hl_pid" 2>/dev/null || break
        sleep 0.2
    done
    sleep 0.3
    restore_session_env
    sleep 0.5
    restore_session_env
}
trap cleanup EXIT INT TERM

# --- a compositor with no screen -----------------------------------------
#
# An EMPTY config, deliberately: the repository's own hypr config would start
# the autostart programs - a second quickshell among them - and this is a test
# of the QML, not a second desktop session.
# A configuration with nothing in it, so what is being tested is the SHELL and
# not the compositor's own settings. Both compositors accept an empty file;
# niri's is KDL and Hyprland's is its own syntax, but empty is empty.
: > "$work/empty.conf"
: > "$work/empty.kdl"

# The sockets that exist BEFORE, so the new one can be told apart from the
# session's own. Matching on mtime alone picked the live socket when the
# headless one was slow to appear.
mapfile -t before < <(cd "$XDG_RUNTIME_DIR" && ls -d wayland-[0-9]* 2>/dev/null)
is_old() { local s; for s in ${before+"${before[@]}"}; do [[ $s == "$1" ]] && return 0; done; return 1; }

# A session to nest into. Running from a terminal inside the session this is
# already set; over ssh it is not, and the session's own socket is the one to
# borrow - the nested compositor is a client of it like any other.
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
        [[ -S $s ]] && { export WAYLAND_DISPLAY="${s##*/}"; break; }
    done
fi
[[ -n ${WAYLAND_DISPLAY:-} ]] || {
    red "qs-check: no Wayland session to nest in - this needs a running desktop"
    exit 2
}

save_session_env

log "starting a nested compositor ($comp)"
if [[ $comp == hyprland ]]; then
    Hyprland -c "$work/empty.conf" > "$work/comp.log" 2>&1 &
else
    # niri picks its winit backend automatically when WAYLAND_DISPLAY is set,
    # which is the same nesting Hyprland does - a window inside the session
    # rather than a headless surface. hypr/rules.lua hides Hyprland's; niri's
    # is titled "niri" and lives for the ~2s of a run.
    niri -c "$work/empty.kdl" > "$work/comp.log" 2>&1 &
fi
hl_pid=$!

sock=""
for _ in $(seq 1 $((compositor_wait * 5))); do
    for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
        [[ -S $s ]] || continue
        name="${s##*/}"
        is_old "$name" || { sock="$name"; break; }
    done
    [[ -n $sock ]] && break
    kill -0 "$hl_pid" 2>/dev/null || {
        red "qs-check: the compositor exited early - this is not a config failure"
        tail -5 "$work/comp.log" | sed 's/^/  /'
        exit 2
    }
    sleep 0.2
done
[[ -n $sock ]] || { red "qs-check: no new Wayland socket after ${compositor_wait}s"; exit 2; }

# Hyprland's alone: it is how hyprctl finds the instance, and niri has no
# equivalent (its IPC socket is named in NIRI_SOCKET, which the shell does not
# need to load). Empty under niri, and an empty variable is not exported below.
sig=""
[[ $comp == hyprland ]] && sig="$(cd "$XDG_RUNTIME_DIR/hypr" && ls -t 2>/dev/null | head -1)"
log "compositor up on $sock"

# --- load the config -----------------------------------------------------
#
# It never exits on its own - a shell runs until it is killed - so waiting for
# it to finish means waiting out the whole timeout. WAIT FOR THE SENTENCE
# INSTEAD: quickshell prints "Configuration Loaded" when it is up, and that is
# the moment there is an answer. Sitting out the full timeout instead made a
# passing check take 20 seconds, which is 20 seconds nobody will accept before
# every commit; watching for the line brings it under five.
log "loading $config"
WAYLAND_DISPLAY="$sock" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
    qs -p "$config" > "$work/qs.log" 2>&1 &
qs_pid=$!

status=0
loaded=0
for _ in $(seq 1 $((load_wait * 5))); do
    if grep -qa 'Configuration Loaded' "$work/qs.log" 2>/dev/null; then
        loaded=1
        # A breath for anything the load logs immediately after saying it is
        # up - a binding evaluated on the first frame, a singleton's first
        # complaint - which would otherwise be killed before it was written.
        sleep 0.5
        break
    fi
    if ! kill -0 "$qs_pid" 2>/dev/null; then
        wait "$qs_pid"; status=$?
        break
    fi
    sleep 0.2
done

if kill -0 "$qs_pid" 2>/dev/null; then
    kill "$qs_pid" 2>/dev/null
    status=124                      # stopped by us, which is the good case
    wait "$qs_pid" 2>/dev/null
fi

plain() { sed 's/\x1b\[[0-9;]*m//g' "$work/qs.log"; }

# --- what is a fault and what is merely the harness ----------------------
#
# EVERY SUPPRESSED LINE IS COUNTED AND NAMED, which is the point of doing it
# this way. The two exceptions below used to be bare greps in a pipeline: they
# worked, but a filtered warning left no trace, so the run printed nothing about
# eight GlobalShortcut lines it had just thrown away. That is indistinguishable
# from a clean run, and it trains you to believe a silence that was never
# earned. Worse, when this shell grew warnings that were ALSO benign - the
# nested compositor having no outputs, Qt failing on an icon theme's SVG - the
# habit became "run it and ignore the noise", and a real warning would have gone
# past unread among them. It nearly did, several times, in the session that
# produced this.
#
# So: a line matching nothing here FAILS the check. A line matching something
# here is suppressed, counted, and the reason printed. Adding an entry is
# deliberate and leaves a record in the output, rather than a pipeline growing
# another `grep -v`.
#
# pattern@@why - @@ because the patterns themselves contain | for alternation.
known=(
    # The live shell already owns org.freedesktop.Notifications; a second
    # instance cannot, and says so every single time.
    'service\.notifications: (Could not register notification server|Registration will be attempted)@@the live shell already owns the notification bus name'

    # Monitors.qml asks the compositor for its outputs. The nested one is a
    # throwaway with no real display attached and answers with something that is
    # not JSON. Against the live compositor this same code populates the Display
    # page correctly, which is the proof that the parser is fine and the harness
    # is the odd one out.
    'monitors: the compositor gave something that is not JSON@@the nested compositor has no outputs to describe'

    # Qt's SVG renderer is not librsvg and does not implement all of SVG: the
    # icon themes in ~/.local/share/icons use pattern and filter references it
    # cannot resolve. Nothing in this repository can fix an upstream icon, and
    # it has no bearing on whether the configuration is correct.
    '(qt\.svg|qt\.svg\.draw):@@an icon theme SVG that Qt cannot render'
    # Shipped by the swappy package, not by anything here: its Exec line escapes
    # $ as \$ inside a quoted sh -c, which Quickshell's desktop entry parser
    # objects to and the spec does not allow. Nothing in this shell reads it -
    # the warning arrives because the launcher indexes every .desktop on the
    # machine - and it appeared the day swappy was installed for the screenshot
    # annotator.
    'Illegal escape sequence in desktop entry exec string@@a packaged .desktop file with a malformed Exec'
)

# AND UNDER niri, THE GLOBAL SHORTCUTS: not a fault in the config, but a
# protocol the compositor does not implement.
#
# GlobalShortcut in shell.qml speaks hyprland_global_shortcuts_v1, which is
# Hyprland's. niri has no equivalent and says so once per shortcut - eight
# identical pairs of lines on this shell. On a niri machine those binds are not
# used at all: niri/config.kdl calls `qs ipc` instead, which is the documented
# arrangement, so the components sit there inert.
#
# ONLY under niri. Under Hyprland the same warning would mean the protocol
# really is missing, which is worth failing on.
if [[ $comp == niri ]]; then
    known+=(
        'GlobalShortcut will not work|does not support hyprland_global_shortcuts_v1@@niri does not implement hyprland_global_shortcuts_v1'
        'HYPRLAND_INSTANCE_SIGNATURE is unset|Cannot connect to hyprland@@the Hyprland module has no Hyprland to talk to'
    )
fi

problems="$(plain | grep -aE 'WARN|ERROR' || true)"

suppressed=()
for entry in "${known[@]}"; do
    pat="${entry%%@@*}"
    why="${entry#*@@}"
    n="$(printf '%s\n' "$problems" | grep -acE "$pat" 2>/dev/null || true)"
    (( ${n:-0} == 0 )) && continue
    suppressed+=("$(printf '%4s  %s' "${n}x" "$why")")
    problems="$(printf '%s\n' "$problems" | grep -avE "$pat" || true)"
done
# grep on an empty string still yields one empty line, which would read as a
# problem with no text in it.
problems="$(printf '%s\n' "$problems" | grep -av '^[[:space:]]*$' || true)"

# Printed on success as well as failure. A check that says what it ignored is
# one whose silence means something.
show_suppressed() {
    (( ${#suppressed[@]} )) || return 0
    printf '\033[2m    known and ignored:\033[0m\n'
    printf '\033[2m    %s\033[0m\n' "${suppressed[@]}"
}

if (( ! loaded )); then
    red "qs-check: the configuration did NOT load"
    printf '%s\n' "----"
    plain | grep -aE 'ERROR|WARN|error:|\.qml' | head -20 | sed 's/^/  /'
    printf '%s\n' "----"
    exit 1
fi

if [[ -n $problems ]]; then
    red "qs-check: it loaded, but complained"
    printf '%s\n' "$problems" | head -20 | sed 's/^/  /'
    show_suppressed
    exit 1
fi

# 124 is the timeout, which is what a shell that stays up looks like. Anything
# else means it stopped by itself, which a working config does not do.
if (( status != 124 )); then
    red "qs-check: it exited on its own with status $status"
    plain | tail -10 | sed 's/^/  /'
    exit 1
fi

# --- every singleton member a file names actually exists there ---------------
#
# LOADING IS NOT RESOLVING. QML looks a function up when it is CALLED, so a
# singleton that has lost one still parses, still loads, and every panel still
# draws - the failure is a TypeError in a log at the moment someone uses it.
#
# Settings.setValue() was deleted by a careless span removal and nothing noticed
# for four commits: the shell came up each time and this script said "loads
# clean". It is the one write path for the whole settings panel.
#
# So: read every Foo.bar in the QML, with comments stripped so documentation
# mentioning another file does not count, and check Foo declares bar.
singleton_members() {
    python3 -I - "$config" <<'PY'
import re, sys, pathlib

qml = {p.stem: p.read_text() for p in pathlib.Path(sys.argv[1]).glob("*.qml")}
defs, props = {}, {}
for n, s in qml.items():
    defs[n] = set(re.findall(r"^\s*function\s+(\w+)\s*\(", s, re.M))
    props[n] = set(re.findall(r"^\s*(?:readonly\s+)?property\s+[\w<>]+\s+(\w+)", s, re.M))
    props[n] |= set(re.findall(r"^\s*property\s+alias\s+(\w+)", s, re.M))
    props[n] |= set(re.findall(r"^\s*signal\s+(\w+)", s, re.M))

# Members of Qt's own types, reached through a name that happens to start with a
# capital. Not ours to verify.
SKIP = {"qml","values","get","count","join","map","filter","find","push","slice",
        "indexOf","toFixed","replace","split","restart","start","stop","length",
        "forceActiveFocus","open","close","item","text","trim","pop","some","every"}

bad = []
for caller, s in qml.items():
    body = re.sub(r"//[^\n]*", "", s)
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    for m in re.finditer(r"\b([A-Z]\w+)\.(\w+)\b", body):
        obj, mem = m.group(1), m.group(2)
        if obj not in qml or mem in SKIP: continue
        if mem in defs[obj] or mem in props[obj]: continue
        bad.append(f"{caller}.qml  ->  {obj}.{mem}  is not declared in {obj}.qml")
for b in sorted(set(bad)):
    print(b)
PY
}

unresolved="$(singleton_members)"
if [[ -n $unresolved ]]; then
    red "qs-check: it loads, but names things that do not exist"
    printf '%s\n' "$unresolved" | head -20 | sed 's/^/  /'
    printf '  %s\n' "QML resolves these at call time, so the shell starts and fails later."
    exit 1
fi

# --- every `qs ipc call` names a handler that exists -------------------------
#
# `qs ipc call` EXITS 0 WHEN THE FUNCTION IS NOT THERE. It prints "Function not
# found" and succeeds, so a mistyped bind is indistinguishable from a working
# one: the key does nothing, the shell logs nothing, and the exit status says
# fine. A bind can be wrong from the day it is written and never be noticed
# until someone presses it and wonders.
#
# This reads the IpcHandler blocks for the targets and functions that really
# exist, then checks every call site in the keybinds, the scripts and the shell
# itself against them.
ipc_call_sites() {
    python3 - "$config" <<'PY'
import re, sys, pathlib, glob, os

root = pathlib.Path(sys.argv[1])
root = root.parent if root.is_file() else root
repo = root.parent

handlers = {}
for f in sorted(root.glob("*.qml")):
    s = f.read_text()
    for m in re.finditer(r"IpcHandler\s*\{", s):
        i = s.index("{", m.start()); d = 0; j = i
        while j < len(s):
            if s[j] == "{": d += 1
            elif s[j] == "}":
                d -= 1
                if d == 0: break
            j += 1
        blk = s[i:j]
        t = re.search(r'target:\s*"([a-z]+)"', blk)
        if t:
            handlers.setdefault(t.group(1), set()).update(
                re.findall(r"function\s+([a-zA-Z]+)\s*\(", blk))

if not handlers:
    sys.exit(0)

files = []
for pat in ("niri/*.kdl", "bin/*.sh", "bin/*.py", "quickshell/*.qml", "hypr/*.conf"):
    files += glob.glob(str(repo / pat))

for path in sorted(files):
    try: lines = pathlib.Path(path).read_text().splitlines()
    except Exception: continue
    for ln, line in enumerate(lines, 1):
        st = line.strip()
        if st.startswith("//") or st.startswith("#"): continue
        m = re.search(r'"qs"\s+"ipc"\s+"call"\s+"([a-z]+)"\s+"([a-zA-Z]+)"', line)
        if not m:
            m = re.search(r"\bqs ipc call ([a-z]+) ([a-zA-Z]+)", line)
        if not m: continue
        tgt, fn = m.group(1), m.group(2)
        rel = os.path.relpath(path, repo)
        if tgt not in handlers:
            print(f"{rel}:{ln}  qs ipc call {tgt} {fn}  ->  no target named {tgt}")
        elif fn not in handlers[tgt]:
            near = ", ".join(sorted(handlers[tgt])[:6])
            print(f"{rel}:{ln}  qs ipc call {tgt} {fn}  ->  {tgt} has no {fn}() ({near})")
PY
}

deadipc="$(ipc_call_sites)"
if [[ -n $deadipc ]]; then
    red "qs-check: a keybind or script calls an ipc function that is not there"
    printf '%s\n' "$deadipc" | head -20 | sed 's/^/  /'
    printf '  %s\n' "qs ipc call exits 0 for these, so nothing else will ever tell you."
    exit 1
fi

show_suppressed
green "qs-check: $config loads clean, every singleton member resolves, every ipc call lands"
