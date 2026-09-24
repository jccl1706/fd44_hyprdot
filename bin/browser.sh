#!/usr/bin/env sh
# =========================================================================
# browser.sh - run the browser this machine actually calls it
# =========================================================================
#
# Usage:  bin/browser.sh [args...]        exec the browser with those args
#         bin/browser.sh --which          print the binary it would use
#
# THE BINARY HAS A DIFFERENT NAME ON EVERY DISTRIBUTION. Fedora's chromium
# package installs "chromium-browser" and ships no "chromium" symlink; Debian
# installs "chromium" and nothing else. hypr/hyprland.lua had Fedora's
# spelling written into Apps.browser, which every machine in the repository
# reads.
#
# The NixOS desktop turned out to have BOTH names, so nothing was actually
# broken there - that was a guess, and checking it afterwards is what turned
# it into a fact. The shim stays anyway: one machine carrying both spellings
# is not a reason to depend on it.
#
# The order is the same one bin/chrome-theme.sh already searches, and for the
# same reason: whichever of these is installed is the one the theme script
# will be styling, so the two agree about what "the browser" means.
#
# sh AND NOT bash, because it does nothing that needs bash and is on the
# critical path of a keypress.

set -eu

for c in chromium-browser chromium google-chrome-stable brave-browser firefox; do
    if command -v "$c" >/dev/null 2>&1; then
        [ "${1-}" = "--which" ] && { command -v "$c"; exit 0; }
        exec "$c" "$@"
    fi
done

# NOTIFY RATHER THAN FAIL SILENTLY. This is reached from a keybind and from a
# launcher entry, neither of which has anywhere to print: without this the key
# simply does nothing and looks broken rather than unconfigured.
echo "browser.sh: none of chromium-browser, chromium, google-chrome-stable, brave-browser or firefox is installed" >&2
command -v notify-send >/dev/null 2>&1 &&
    notify-send -a "Browser" "No browser found" "Install one of chromium, google-chrome or firefox"
exit 1
