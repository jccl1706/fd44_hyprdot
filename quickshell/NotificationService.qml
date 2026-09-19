pragma Singleton

// =========================================================================
// NotificationService - the desktop's notification daemon
// =========================================================================
//
// There is no dunst or mako here. Quickshell's NotificationServer claims
// org.freedesktop.Notifications on the session bus itself, so anything that
// speaks the freedesktop protocol - notify-send, libnotify apps, Chromium
// web apps - lands in this shell and is drawn by Notifications.qml.
//
// That follows the same rule as Media.qml speaking MPRIS directly rather
// than forking playerctl: a feature the bar owns belongs inside the bar,
// not in a second daemon with its own config file and its own theme.
//
// THE DESIGN OWES A LOT TO OMARCHY, whose Quickshell shell (MIT licensed,
// github.com/omacom/omarchy, shell/plugins/notifications) solved several of
// these problems first. Where a comment below says something was learned
// rather than measured, that is where it was learned. The code is written
// for this shell rather than copied.
//
// State lives in ~/.local/state/fd44-hyprdot/notifications.json, beside the
// bar layout and the active theme.

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: service

    // Rows currently on screen, newest first. A ListModel rather than a JS
    // array because a Repeater over it moves one delegate instead of
    // rebuilding every card when a toast expires.
    property ListModel popups: ListModel {}

    // What has been and gone, newest first, capped at historyLimit.
    property var history: []
    readonly property int historyLimit: 30

    property bool doNotDisturb: false

    // The live Notification objects, keyed by the row key. The model holds
    // plain values for display; actions and dismissal need the real object.
    property var live: ({})

    // --- lifetimes ---------------------------------------------------------
    //
    // Low is a glance, normal is a read, critical waits for you. The ceiling
    // exists because a sender may ask for any expire_timeout it likes and a
    // toast that will not go away is the sender's bug, not the user's
    // problem. From Omarchy, whose numbers these are.
    readonly property int lowMs:      5000
    readonly property int normalMs:   8000
    readonly property int maxMs:     30000

    function durationFor(urgency, requested) {
        if (urgency === NotificationUrgency.Critical) return 0      // sticky
        const base = urgency === NotificationUrgency.Low ? service.lowMs
                                                         : service.normalMs
        // -1 means "server decides", 0 means "never expire" from a sender
        // that is not critical - which we decline, see above.
        if (requested === undefined || requested === null || requested < 0) return base
        if (requested === 0) return service.maxMs
        return Math.min(Math.max(requested, base), service.maxMs)
    }

    // --- do not disturb ----------------------------------------------------
    //
    // TWO THINGS PUNCH THROUGH, and the narrowness is the point. Urgency
    // critical ALONE is not enough: chat apps set critical to force
    // visibility, and they set app_name to their own brand. A bare CLI
    // sender is a different kind of message - a script that has decided
    // something is wrong. Learned from Omarchy, whose reasoning this is.
    readonly property var cliSenders: ["notify-send", "fd44"]

    function bypassesDnd(n) {
        if (n.urgency !== NotificationUrgency.Critical) return false
        const app = String(n.appName || "")
        for (let i = 0; i < service.cliSenders.length; i++) {
            if (app === service.cliSenders[i] || app.indexOf("fd44") === 0) return true
        }
        return false
    }

    // Nothing worth looking back at: the freedesktop `transient` hint is the
    // sender saying so itself, and a volume OSD is the classic example.
    function isEphemeral(n) {
        return n.transient === true
    }

    // --- arrival -----------------------------------------------------------

    function handle(n) {
        // WITHOUT THIS THE OBJECT IS DESTROYED the moment this handler
        // returns, and every reference kept for the card goes null with it.
        // The single most important line in the file; learned from Omarchy.
        n.tracked = true

        if (service.doNotDisturb && !service.bypassesDnd(n)) {
            // Silenced, but not erased: "what did I miss" is exactly what
            // history is for. Genuinely ephemeral things are simply dropped.
            if (!service.isEphemeral(n)) service.remember(service.rowOf(n))
            n.tracked = false
            return
        }

        const row = service.rowOf(n)
        service.live[row.key] = n

        // A replaces_id update rewrites the object in place and never fires
        // onNotification a second time, so an existing row for the same
        // server id has to be replaced rather than duplicated.
        service.dropRows(n.id)

        n.closed.connect(function() { service.onClosed(row.key) })

        // Qt.callLater, because inserting into a model a Repeater is still
        // incubating can crash it. From Omarchy, and not a hypothetical.
        Qt.callLater(function() { service.popups.insert(0, row) })
    }

    function rowOf(n) {
        return {
            key:      String(n.id) + "-" + Date.now(),
            nid:      n.id,
            summary:  String(n.summary || ""),
            body:     String(n.body || ""),
            appName:  String(n.appName || ""),
            appIcon:  String(n.appIcon || ""),
            image:    String(n.image || ""),
            urgency:  n.urgency,
            ts:       Date.now(),
            duration: service.durationFor(n.urgency, n.expireTimeout)
        }
    }

    function dropRows(nid) {
        for (let i = service.popups.count - 1; i >= 0; i--) {
            if (service.popups.get(i).nid === nid) {
                const key = service.popups.get(i).key
                delete service.live[key]
                service.popups.remove(i)
            }
        }
    }

    function indexOfKey(key) {
        for (let i = 0; i < service.popups.count; i++) {
            if (service.popups.get(i).key === key) return i
        }
        return -1
    }

    // --- leaving the screen ------------------------------------------------

    function onClosed(key) {
        const i = service.indexOfKey(key)
        if (i < 0) return
        service.remember(service.popups.get(i))
        delete service.live[key]
        service.popups.remove(i)
    }

    // Expired or dismissed by the user. dismiss() tells the sender, which
    // matters for apps that track their own notifications; expire() is the
    // timeout path and is what a sender expects when nobody touched it.
    function close(key, byUser) {
        const n = service.live[key]
        const i = service.indexOfKey(key)
        if (n) {
            // REMEMBERING IS onClosed's JOB, NOT THIS ONE'S. dismiss() and
            // expire() both make the server emit `closed`, which lands in
            // onClosed and files the row - doing it here as well wrote every
            // notification into history twice, with identical timestamps.
            if (byUser) n.dismiss()
            else n.expire()
        } else if (i >= 0) {
            // No live object: nothing will emit `closed`, so this is the
            // only chance to file it.
            service.remember(service.popups.get(i))
            service.popups.remove(i)
        }
    }

    function dismissAll() {
        for (let i = service.popups.count - 1; i >= 0; i--) {
            service.close(service.popups.get(i).key, true)
        }
    }

    // Click: run the sender's default action if it registered one. Without
    // one there is nothing sensible to do but dismiss - this shell does not
    // guess at focusing the sender's window.
    function activate(key) {
        const n = service.live[key]
        if (n && n.actions) {
            for (let i = 0; i < n.actions.length; i++) {
                if (String(n.actions[i].identifier) === "default") {
                    n.actions[i].invoke()
                    return
                }
            }
        }
        service.close(key, true)
    }

    // --- posting from inside the shell ---------------------------------------
    //
    // A notification the shell raises itself - a low battery, say. It goes
    // through the same rows, the same do-not-disturb rules and the same
    // history as anything a client sends; it simply has no client behind it,
    // so there is nothing to dismiss upstream and no action to invoke.
    //
    // NOT VIA notify-send. Forking a program to talk over the bus to a daemon
    // running in this very process would be a long way round, and the toast
    // would be indistinguishable at the end of it.
    //
    // `appName` is "fd44" so the DND rule already written for CLI senders
    // covers these: a critical one gets through, a merely low one does not
    // and waits in history. See bypassesDnd().
    property int syntheticId: -1

    function post(summary, body, urgency): void {
        const u = (urgency === undefined) ? NotificationUrgency.Normal : urgency
        const row = {
            key:      "fd44-" + Date.now() + "-" + (-service.syntheticId),
            // Negative and unique, so dropRows() can never confuse two of
            // these with each other or with a real notification's id.
            nid:      service.syntheticId,
            summary:  String(summary),
            body:     String(body || ""),
            appName:  "fd44",
            appIcon:  "",
            image:    "",
            urgency:  u,
            ts:       Date.now(),
            duration: service.durationFor(u, -1)
        }
        service.syntheticId--

        if (service.doNotDisturb && u !== NotificationUrgency.Critical) {
            service.remember(row)
            return
        }
        Qt.callLater(function() { service.popups.insert(0, row) })
    }

    // --- history -----------------------------------------------------------

    function remember(row) {
        if (!row) return
        const entry = {
            summary: row.summary, body: row.body, appName: row.appName,
            appIcon: row.appIcon, urgency: row.urgency, ts: row.ts
        }
        const next = [entry].concat(service.history)
        service.history = next.slice(0, service.historyLimit)
        service.save()
    }

    function clearHistory() {
        service.history = []
        service.save()
    }

    // --- persistence -------------------------------------------------------

    function setDnd(on) {
        service.doNotDisturb = !!on
        service.save()
    }

    function toggleDnd() { service.setDnd(!service.doNotDisturb) }

    function save() {
        file.setText(JSON.stringify({
            dnd: service.doNotDisturb,
            history: service.history
        }, null, 2))
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/fd44-hyprdot/notifications.json"
        // No file until the first notification or the first DND toggle, which
        // is not worth a warning in the log on every start.
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(file.text())
                service.doNotDisturb = !!d.dnd
                service.history = Array.isArray(d.history) ? d.history : []
            } catch (e) {
                console.warn("notifications: ignoring unreadable", file.path, "-", e)
            }
        }
        onSaveFailed: err => console.warn("notifications: could not save:",
                                          FileViewError.toString(err))
    }

    // --- the server --------------------------------------------------------

    NotificationServer {
        id: server

        // TRUE, unlike Omarchy's. They restart the whole shell process on
        // update and rebuild live toasts from files; here `qs` reloads its
        // config in-process every time one of these files is saved, and
        // losing every toast on screen each time would be its own bug.
        keepOnReload: true

        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: n => service.handle(n)
    }
}
