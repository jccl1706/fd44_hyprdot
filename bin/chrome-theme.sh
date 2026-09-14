#!/usr/bin/env bash
# =========================================================================
# chrome-theme.sh - set Chromium's browser chrome to match the theme
# =========================================================================
#
# Usage:  chrome-theme.sh <rrggbb> <light|dark>    apply
#         chrome-theme.sh off                      remove the policy
#
# NO ROOT, NO SUDO. See "HOW THE WRITE HAPPENS" below.
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
#                       "device", so the browser cannot disagree with the
#                       desktop that just told it what to be.
#
# THE SEED AND THE SCHEME CAN CONTRADICT EACH OTHER. A near-black seed under
# scheme "light" renders a near-black browser - the seed's own brightness wins.
# The caller is responsible for not doing that; bin/theme.sh applies a
# luminance guard before calling here.
#
# HOW THE WRITE HAPPENS. /etc/chromium/policies/managed belongs to root, and
# this script never touches it. It writes the request - "<rrggbb> <scheme>" or
# "off" - to a file in the user's own state directory, and a root service set
# up once by `sudo bin/chromium-policy-setup.sh` sees the change, checks the
# request is exactly that shape, and writes color.json. The user can ask for a
# colour and nothing more. (The directory used to be user-owned, which let any
# program running as the user write ANY browser policy - see the setup script.)
#
# Without that setup this exits 0 and does nothing, so a machine that has not
# run it still switches themes normally - it just leaves the browser alone.

set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/fd44-hyprdot"
request="$state_dir/chromium-theme"
policy="/etc/chromium/policies/managed/color.json"

die() { printf 'chrome-theme: %s\n' "$*" >&2; exit 1; }

refresh() {
    # Tells an already-running browser to re-read policy. --no-startup-window
    # stops it opening a window when none is running.
    local c comm
    for c in chromium-browser chromium google-chrome-stable brave-browser; do
        command -v "$c" >/dev/null 2>&1 || continue

        # TRUNCATE TO 15 CHARACTERS. The kernel stores a process's comm in a
        # 16-byte field, so "chromium-browser" - Fedora's binary name, and 16
        # characters exactly - appears in the process table as
        # "chromium-browse". `pgrep -x chromium-browser` therefore matches
        # nothing at all, silently.
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

# Written to a temp file and renamed into place, so the root service - which
# runs on every change - never reads half a line.
send() {
    mkdir -p "$state_dir"
    local tmp
    tmp="$(mktemp "$request.XXXXXX")"
    printf '%s\n' "$1" > "$tmp"
    mv -f "$tmp" "$request"
}

# Waits (briefly) for the service to have written what was asked, then tells
# the browser. In the background: a theme switch on a keypress must not wait
# on it.
apply_when_written() {
    local want="$1"
    (
        for _ in $(seq 1 30); do
            if [[ $want == off ]]; then
                [[ ! -e $policy ]] && break
            else
                grep -qF "$want" "$policy" 2>/dev/null && break
            fi
            sleep 0.1
        done
        refresh
    ) >/dev/null 2>&1 &
    disown
}

if ! systemctl is-enabled --quiet fd44-chromium-theme.path 2>/dev/null; then
    printf 'chrome-theme: the Chromium theme service is not set up - run once:\n' >&2
    printf '  sudo %s/chromium-policy-setup.sh\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" >&2
    exit 0
fi

case "${1:-}" in
    off)
        send off
        apply_when_written off
        printf 'chrome-theme: policy removal requested\n'
        exit 0
        ;;
    "")
        die "usage: chrome-theme.sh <rrggbb> <light|dark> | off"
        ;;
esac

color="${1#\#}"
scheme="${2:-}"

# Checked here as well as by the root helper, so a mistake is reported to the
# caller instead of only in the service's journal.
[[ $color =~ ^[0-9a-fA-F]{6}$ ]] || die "expected six hex digits, got '$1'"
[[ $scheme == light || $scheme == dark ]] || die "scheme must be light or dark, got '${scheme:-}'"

send "$color $scheme"
apply_when_written "\"#$color\""
printf 'chrome-theme: #%s / %s\n' "$color" "$scheme"
