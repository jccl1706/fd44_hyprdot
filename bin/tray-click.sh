#!/usr/bin/env bash
# =========================================================================
# tray-click.sh - make a tray icon do something for applications that will not
# =========================================================================
#
# Usage:  bin/tray-click.sh "<tray item title>"
#
# Called by quickshell/Tray.qml when a tray item has no DBus menu to show.
# Everything here is a fallback: an application that implements its own
# StatusNotifierItem.Activate properly never needs it.
#
# WHY IT EXISTS. Battle.net under Proton advertises Activate, returns success
# from it, and does nothing - measured with its window present and another
# program focused, which stayed focused. What it DOES answer is ContextMenu,
# which makes it draw its own little menu window. Quickshell's SystemTrayItem
# exposes activate(), secondaryActivate() and scroll(), but not ContextMenu,
# so there is no way to ask for that from QML and this shells out to busctl.
#
# MATCHED ON TITLE, because Quickshell's SystemTrayItem does not expose the
# bus name or object path of the item behind it, and the title is the only
# thing both sides agree on. Two tray items with the same title would be
# ambiguous; nothing on this machine is.

set -uo pipefail

title="${1:-}"
[[ -z "$title" ]] && { echo "usage: ${0##*/} <tray item title>" >&2; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---- ask the item to show its own menu -----------------------------------
#
# NO WINDOW-FOCUSING FIRST, and that was tried and removed. Focusing a window
# whose title matches looked like the friendlier answer - a click brings the
# program forward - but Battle.net's MENU window carries the same title as its
# main window, "Battle.net", with only its size telling them apart. So the
# first ContextMenu left a 236x377 menu on screen that then satisfied the
# title match forever after, and every later click focused that instead of
# doing anything. Sizes are not a key worth keying on.
#
# Asking for the menu every time is also simply what a tray icon does. The
# application decides what goes in it, including whether "open the window" is
# an entry, which is a better division of labour than guessing.

have busctl || { echo "no busctl; cannot reach the tray item" >&2; exit 1; }

watcher=$(busctl --user get-property org.kde.StatusNotifierWatcher \
              /StatusNotifierWatcher org.kde.StatusNotifierWatcher \
              RegisteredStatusNotifierItems 2>/dev/null)
[[ -z "$watcher" ]] && { echo "no StatusNotifierWatcher" >&2; exit 1; }

# Entries look like  ":1.1314/StatusNotifierItem"  - a bus name and an object
# path glued together with no separator of their own, so the first slash is
# the split point.
while read -r entry; do
    [[ -z "$entry" ]] && continue
    owner="${entry%%/*}"
    path="/${entry#*/}"

    t=$(busctl --user get-property "$owner" "$path" \
            org.kde.StatusNotifierItem Title 2>/dev/null | sed 's/^s //; s/^"//; s/"$//')
    [[ "$t" == "$title" ]] || continue

    busctl --user call "$owner" "$path" \
        org.kde.StatusNotifierItem ContextMenu ii 0 0 >/dev/null 2>&1
    exit $?
done < <(grep -oE '"[^"]+"' <<<"$watcher" | tr -d '"')

exit 1
