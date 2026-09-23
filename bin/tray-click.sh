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
# TWO CASES, IN ORDER, because they need different answers:
#
#   the window exists    -> focus it. This is the common case: the program is
#                           running with a window somewhere and the click
#                           should bring it forward.
#   no window at all     -> ContextMenu, and let the application put something
#                           on screen itself. This is the only thing that
#                           works once Battle.net has closed to the tray.
#
# MATCHED ON TITLE, which is the only handle a tray item and a window share.
# Battle.net's item calls itself "Battle.net" while its window's class is
# "steam_app_3062427963" - a Steam shortcut id nothing could have guessed.
# The risk is another window with the same title; there is no better key.

set -uo pipefail

title="${1:-}"
[[ -z "$title" ]] && { echo "usage: ${0##*/} <tray item title>" >&2; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---- 1. a window with that title ----------------------------------------
#
# Hyprland 0.56 evaluates dispatches as Lua, so the old "focuswindow title:X"
# string form is a syntax error rather than a command - see the comment in
# quickshell/Workspaces.qml, which learned this the same way.
if have hyprctl; then
    if hyprctl clients 2>/dev/null | grep -qxF "	title: $title"; then
        hyprctl dispatch "hl.dsp.focus({ window = \"title:${title//\"/}\" })" >/dev/null 2>&1
        exit 0
    fi
fi

# ---- 2. no window: ask the item to show its own menu ---------------------
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
