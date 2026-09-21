#!/usr/bin/env bash
# =========================================================================
# steam-games.sh - the installed Steam games, as JSON
# =========================================================================
#
# Usage:
#   bin/steam-games.sh            one JSON array on stdout
#   bin/steam-games.sh --pretty   the same, one game per line, for reading
#
# Exists because STEAM GAMES ARE NOT DESKTOP ENTRIES. Nothing under
# XDG_DATA_DIRS mentions ARC Raiders or Fallout 76, so an application launcher
# that reads .desktop files cannot see them and launching a game means going
# through the Steam client. quickshell/SteamGames.qml runs this and merges the
# result into the launcher.
#
# Shell rather than QML because this is file parsing across several
# directories, which QML is poor at and a shell is good at - and because a
# script can be run and read on its own when the launcher shows something
# unexpected.
#
# TELLING A GAME FROM A TOOL. Proton, the Steam Linux Runtime and Steamworks
# Common Redistributables all install as ordinary apps with their own
# appmanifest, and nothing in the manifest says "this is a tool". The usable
# signal is UserConfig: Steam records a `language` there for games and leaves
# it empty for runtime tools. Measured on this machine:
#
#   1808500 ARC Raiders                        UserConfig: language
#   1493710 Proton Experimental                UserConfig: (empty)
#    228980 Steamworks Common Redistributables UserConfig: (empty)
#   4183110 Steam Linux Runtime 4.0            UserConfig: (empty)
#
# It is a heuristic and it is the best one available without parsing
# appinfo.vdf, which is a binary format Steam rewrites at will. If a game ever
# goes missing from the launcher, this test is the first thing to check.

set -euo pipefail

pretty=0
[[ ${1:-} == --pretty ]] && pretty=1

# Steam's root has moved over the years and the old paths are kept as symlinks,
# so take the first that actually has a steamapps directory.
root=""
for c in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
    [[ -d "$c/steamapps" ]] && { root="$c"; break; }
done
[[ -n $root ]] || { printf '[]\n'; exit 0; }

# Every library, not just the default one: a second drive is the normal case
# for a games library, and libraryfolders.vdf is where Steam records them.
libs=("$root")
vdf="$root/steamapps/libraryfolders.vdf"
if [[ -r $vdf ]]; then
    while IFS= read -r p; do
        [[ -d "$p/steamapps" ]] && libs+=("$p")
    done < <(grep -oP '"path"\s+"\K[^"]+' "$vdf" 2>/dev/null || true)
fi

# JSON string escaping. Game names carry colons, apostrophes and the odd
# backslash; printf %s into JSON without this produces a document that parses
# as nothing.
json_escape() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/}
    printf '%s' "$s"
}

declare -A seen=()
out=()
for lib in "${libs[@]}"; do
    for f in "$lib"/steamapps/appmanifest_*.acf; do
        [[ -f $f ]] || continue
        appid="$(grep -oP '"appid"\s+"\K[0-9]+' "$f" | head -1)"
        [[ -n $appid ]] || continue
        [[ -n ${seen[$appid]:-} ]] && continue     # same game in two libraries

        # The tool test, above. UserConfig is a block; a game has `language`
        # inside it.
        if ! sed -n '/"UserConfig"/,/^\t}/p' "$f" | grep -q '"language"'; then
            continue
        fi

        name="$(grep -oP '"name"\s+"\K[^"]+' "$f" | head -1)"
        [[ -n $name ]] || continue

        seen[$appid]=1
        out+=("{\"appid\":\"$appid\",\"name\":\"$(json_escape "$name")\"}")
    done
done

if (( pretty )); then
    printf '%s\n' "${out[@]:-}"
else
    printf '[%s]\n' "$(IFS=,; printf '%s' "${out[*]:-}")"
fi
