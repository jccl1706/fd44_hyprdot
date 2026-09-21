// =========================================================================
// SteamGames - installed Steam games, for machines that have Steam
// =========================================================================
//
// STEAM GAMES ARE NOT DESKTOP ENTRIES. Nothing under XDG_DATA_DIRS mentions
// ARC Raiders or Fallout 76, so a launcher that reads .desktop files cannot
// see them and starting a game means going through the Steam client. This
// singleton runs bin/steam-games.sh and hands the launcher entries shaped like
// the ones DesktopEntries provides.
//
// ONLY WHERE STEAM IS, which is the same arrangement as Couch.qml: this config
// is one checkout shared between the desktop and the Framework, and the laptop
// has no Steam binary and no steamapps directory at all. `available` stays
// false there, the launcher concatenates nothing, and no games section appears.
// A machine that gains Steam later needs no edit - the next scan finds it.
//
// THE SCAN IS A SCRIPT, not QML. It walks libraryfolders.vdf and every
// appmanifest across every library, which a shell does well and QML does not,
// and it can be run by hand when the launcher shows something surprising:
//
//   bin/steam-games.sh --pretty
//
// RE-SCANNED WHEN THE LAUNCHER OPENS rather than once at startup, so a game
// installed during the session appears without restarting quickshell. It is
// one short script run against a handful of small files.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: steam

    // False until a scan has found at least one game. The launcher checks this
    // rather than counting `games`, so the intent reads at the call site.
    property bool available: false

    // Launcher-shaped entries: the delegate wants name, icon, comment and
    // genericName, and launch() wants id.
    property var games: []

    // ~/.config/quickshell is a symlink into the checkout, so resolving it and
    // taking its parent finds bin/ wherever the repository happens to live.
    // Same trick as ThemeToggle.qml.
    readonly property string repoBin:
        "\"$(dirname \"$(readlink -f '" + Quickshell.shellDir + "')\")/bin\""

    // FALSE THEN TRUE, not just true. `running` is a plain property, so
    // assigning the value it already holds emits no change and the process
    // never re-runs - which is exactly what happened: the scan fired once at
    // startup and never again, so a game installed mid-session stayed
    // invisible until quickshell restarted. Caught by watching /proc while
    // opening the launcher and seeing nothing start.
    function refresh(): void {
        scan.running = false
        scan.running = true
    }

    function launch(appid: string): void {
        if (!appid) return
        // Through uwsm, so the game is its own systemd scope rather than a
        // child of quickshell - the same reasoning as AppLaunch.qml, and it
        // matters more here because a game outlives any shell restart.
        runner.command = ["uwsm", "app", "--", "steam", "steam://rungameid/" + appid]
        runner.running = true
    }

    Process { id: runner }

    Component.onCompleted: steam.refresh()

    Process {
        id: scan
        // Started from Component.onCompleted rather than `running: true`: a
        // declarative binding there fights with refresh() assigning the same
        // property, and a broken binding is a worse way to find that out.
        command: ["sh", "-c", steam.repoBin + "/steam-games.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = []
                try {
                    const parsed = JSON.parse(this.text)
                    if (Array.isArray(parsed)) list = parsed
                } catch (e) {
                    // A machine without Steam gets "[]" and never lands here.
                    // Anything else means the script or the manifests changed
                    // shape, which should be visible rather than silent.
                    console.warn("SteamGames: could not parse the scan:", e)
                }

                steam.games = list.map(g => ({
                    // Prefixed so it cannot collide with a desktop entry id,
                    // and stable across reinstalls - LauncherFrecency keys on
                    // it, so a game keeps its history when it is reinstalled.
                    id: "steam:" + g.appid,
                    appid: g.appid,
                    name: g.name,
                    // One icon for every game rather than Steam's per-game
                    // artwork: that lives in hashed directories under
                    // appcache/librarycache with inconsistent filenames, and
                    // what is there is wide logos and portrait capsules rather
                    // than square icons. A Steam mark says "this starts
                    // through Steam", which is the useful thing to know.
                    icon: "steam",
                    genericName: "Steam game",
                    comment: "",
                    keywords: ["steam", "game"],
                    noDisplay: false,
                    isSteamGame: true
                }))
                steam.available = steam.games.length > 0
            }
        }
    }
}
