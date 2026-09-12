#!/usr/bin/env bash
# =========================================================================
# chrome-theme.sh - set Chromium's browser chrome to match the theme
# =========================================================================
#
# Usage:  chrome-theme.sh <rrggbb> <light|dark>    apply
#         chrome-theme.sh off                      remove the policy
#
# NO ROOT AT RUN TIME. See the one-time setup below.
#
# HOW IT WORKS. Chromium themes are normally extensions, and nothing outside
# the browser can swap an extension without restarting it, which rules them
# out for a keybind. This uses enterprise policy instead - two keys in a JSON
# file that Chromium reads from /etc - and then tells a running browser to
# re-read it:
#
#   chromium --refresh-platform-policy --no-startup-window
#
# Live, no restart, no tabs closed, nothing installed in the browser.
#
#   BrowserThemeColor   ONE SEED COLOUR, NOT A LITERAL ONE. Chromium keeps
#                       its hue, roughly doubles the saturation and derives a
#                       whole tab/toolbar scheme from it. Measured on this
#                       machine: seeding #faf4ed gave a tab strip of #f1dfc9,
#                       and seeding #575279 gave #36344c. So a seed is chosen
#                       by what it GENERATES, never by how it looks. An exact
#                       match to the bar is not reachable this way at all -
#                       only an extension can set explicit per-element
#                       colours, and that is the thing that cannot switch
#                       live.
#
#   BrowserColorScheme  "light" or "dark", passed in explicitly rather than
#                       omarchy's "device". "device" defers to the OS signal,
#                       which is one more thing that has to be working; naming
#                       it directly means the browser cannot disagree with the
#                       desktop that just told it what to be.
#
# THE SEED AND THE SCHEME CAN CONTRADICT EACH OTHER, and that is the subtle
# part. A near-black seed under scheme "light" renders a near-black browser -
# the seed's own brightness wins and the result is the inverse of what was
# asked for. The caller is responsible for not doing that; bin/theme.sh
# applies a luminance guard before calling here.
#
# ONE-TIME SETUP, and the reason there is no sudo anywhere below:
#
#   sudo install -d -o "$USER" -g "$USER" -m 755 /etc/chromium/policies/managed
#
# Chromium reads policy only from /etc, so SOMETHING has to be privileged.
# The alternative - a passwordless sudoers rule for a helper script - hands a
# script the ability to run as root forever, and a flaw in it becomes a root
# flaw. Owning one policy directory grants exactly one power: writing browser
# policy. That is not nothing (policy can force-install extensions, so treat
# it as part of the browser's trust boundary), but it is bounded, and it is
# strictly less than root.
#
# Without that setup this exits 0 and does nothing, so a machine that has not
# run it still switches themes normally - it just leaves the browser alone.

set -euo pipefail

POLICY_DIRS=(
    /etc/chromium/policies/managed
    /etc/opt/chrome/policies/managed
    /etc/brave/policies/managed
)

die() { printf 'chrome-theme: %s\n' "$*" >&2; exit 1; }

refresh() {
    # Tells an already-running browser to re-read policy. --no-startup-window
    # stops it opening a window when none is running. Backgrounded and
    # disowned: it talks to the running instance and should never make the
    # caller - a theme switch on a keypress - wait for it.
    local c comm
    for c in chromium-browser chromium google-chrome-stable brave-browser; do
        command -v "$c" >/dev/null 2>&1 || continue

        # TRUNCATE TO 15 CHARACTERS. The kernel stores a process's comm in a
        # 16-byte field, so "chromium-browser" - Fedora's binary name, and 16
        # characters exactly - appears in the process table as
        # "chromium-browse". `pgrep -x chromium-browser` therefore matches
        # nothing at all, silently, and pgrep only warns about it on a tty.
        #
        # That is not a cosmetic bug: this guard failing means the refresh
        # never runs, so the policy file is written and the browser does not
        # hear about it until it next polls on its own - which looks exactly
        # like "the theme takes a while to switch".
        #
        # Matching comm rather than `pgrep -f` on the path deliberately: -f
        # searches whole command lines and would happily match the shell that
        # invoked this script.
        comm="$(basename "$c" | cut -c1-15)"
        pgrep -x "$comm" >/dev/null 2>&1 || continue

        "$c" --refresh-platform-policy --no-startup-window >/dev/null 2>&1 &
        disown
    done
}

case "${1:-}" in
    off)
        wrote=0
        for d in "${POLICY_DIRS[@]}"; do
            [[ -d $d && -w $d ]] || continue
            rm -f "$d/color.json"; wrote=1
        done
        (( wrote )) && refresh
        printf 'chrome-theme: policy removed\n'
        exit 0
        ;;
    "")
        die "usage: chrome-theme.sh <rrggbb> <light|dark> | off"
        ;;
esac

color="${1#\#}"
scheme="${2:-}"

# Validated before anything is written. The colour is the only value that
# reaches a file here - the paths are fixed above - so this is the whole of
# the input checking that matters.
[[ $color =~ ^[0-9a-fA-F]{6}$ ]] || die "expected six hex digits, got '$1'"
[[ $scheme == light || $scheme == dark ]] || die "scheme must be light or dark, got '${scheme:-}'"

wrote=0
for d in "${POLICY_DIRS[@]}"; do
    # Writable means the one-time setup has been done for this browser. Not
    # writable, or absent, is the normal state on a machine that never ran it,
    # and is not an error: the theme switch that called this should not fail
    # because the browser is not set up.
    [[ -d $d && -w $d ]] || continue
    printf '{"BrowserThemeColor": "#%s", "BrowserColorScheme": "%s"}\n' "$color" "$scheme" \
        > "$d/color.json"
    wrote=1
done

if (( ! wrote )); then
    printf 'chrome-theme: no writable policy directory - run once:\n' >&2
    printf '  sudo install -d -o "$USER" -g "$USER" -m 755 %s\n' "${POLICY_DIRS[0]}" >&2
    exit 0
fi

refresh
printf 'chrome-theme: #%s / %s\n' "$color" "$scheme"
