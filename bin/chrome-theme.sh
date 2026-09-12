#!/usr/bin/env bash
# =========================================================================
# chrome-theme.sh - set Chromium's theme colour, live
# =========================================================================
#
# Usage:  sudo chrome-theme.sh <rrggbb>   apply a colour
#         sudo chrome-theme.sh off        remove the policy again
#
# Chromium themes are normally extensions, and nothing outside the browser
# can swap an extension without restarting it. This takes the other route:
# ENTERPRISE POLICY. Two keys in a JSON file under /etc do the whole job.
#
#   BrowserThemeColor   one seed colour. Chromium generates a full theme
#                       from it - the same machinery as the colour picker
#                       in Customize Chrome.
#   BrowserColorScheme  "device", so light/dark still follows the system,
#                       which bin/theme.sh already drives through gsettings
#                       and xdg-desktop-portal.
#
# The browser is then told to re-read policy without being restarted:
#   chromium --refresh-platform-policy --no-startup-window
#
# WHY THIS NEEDS ROOT, AND WHY IT IS A SEPARATE SCRIPT. Chromium reads policy
# only from /etc - there is no per-user policy path - so the write is
# privileged. Keeping it in its own small script means theme.sh stays
# unprivileged and this is the only thing that ever needs elevating, which is
# also what makes a narrowly-scoped sudoers rule possible later if the colour
# is ever to follow the theme automatically. Without such a rule this is a
# one-off you run by hand, and the browser keeps whatever colour it was last
# given.
#
# The colour is validated to exactly six hex digits before it reaches a file
# under /etc. It is the only caller-controlled value here - the paths are
# fixed in this file - and validating it is what keeps that true.

set -euo pipefail

# Pinned: when this runs under sudo, secure_path decides where a bare command
# resolves, and everything called below is a system tool. Nothing here should
# ever resolve out of a user-writable directory.
PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

# Only directories a browser package already created. Creating one would hand
# a browser a managed-policy root it did not previously have, which is a
# bigger change than setting a colour and not one this should make silently.
# /etc/chromium/policies ships with Fedora's chromium package; the "managed"
# leaf inside it is the documented location and is created here.
POLICY_PARENTS=(
    /etc/chromium/policies
    /etc/opt/chrome/policies
    /etc/brave/policies
)

die() { printf 'chrome-theme: %s\n' "$*" >&2; exit 1; }

refresh() {
    # Signals a running browser to re-read policy. --no-startup-window keeps it
    # from opening a window when none is running. Failure is not fatal: no
    # browser running is a perfectly normal state.
    local c
    for c in chromium-browser chromium google-chrome-stable brave-browser; do
        command -v "$c" >/dev/null 2>&1 || continue
        "$c" --refresh-platform-policy --no-startup-window >/dev/null 2>&1 || true
    done
}

[[ $# -eq 1 ]] || die "usage: chrome-theme.sh <rrggbb|off>"
(( EUID == 0 )) || die "must run as root - try: sudo $0 $1"

# Validated once, before any directory is touched and before the loop that
# might not run at all. Checking inside the loop would mean a malformed colour
# passed silently on a machine with no policy directory, and only failed on a
# machine that had one - the worst place for an input check to live.
color=""
if [[ $1 != off ]]; then
    color="${1#\#}"
    [[ $color =~ ^[0-9a-fA-F]{6}$ ]] || die "expected six hex digits, got '$1'"
fi

written=0
for parent in "${POLICY_PARENTS[@]}"; do
    [[ -d $parent && ! -L $parent ]] || continue
    dest="$parent/managed/color.json"

    if [[ $1 == off ]]; then
        rm -f "$dest"
        written=1
        continue
    fi

    mkdir -p "$parent/managed"
    # install -T writes atomically with the mode and ownership set in one step,
    # so the file is never briefly world-writable or owned by the wrong user.
    printf '{"BrowserThemeColor": "#%s", "BrowserColorScheme": "device"}\n' "$color" \
        | install -m 0644 -o root -g root -T /dev/stdin "$dest"
    written=1
done

(( written )) || die "no browser policy directory found - is chromium installed?"

refresh

if [[ $1 == off ]]; then
    printf 'chrome-theme: policy removed\n'
else
    printf 'chrome-theme: #%s applied\n' "${1#\#}"
fi
