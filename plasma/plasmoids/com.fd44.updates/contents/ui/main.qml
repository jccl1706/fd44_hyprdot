// =========================================================================
// fd44 Updates - the bar's update box, for Plasma
// =========================================================================
//
// The same idea as quickshell/Updates.qml and, deliberately, the same BACKEND:
// bin/updates.py answers "what is waiting to be installed" on Fedora, Gentoo
// and NixOS alike, and both front ends do nothing but draw its answer. Adding
// a desktop must not mean a second copy of the distro logic - that is how the
// two would drift and one would start lying.
//
// IT HIDES ITSELF WHEN THERE IS NOTHING TO SAY. HiddenStatus, not Passive:
// passive still occupies a row in the tray's popup, which is a permanent
// reminder of a thing that is not happening. The box in the Hyprland bar
// behaves the same way, and that symmetry is the point.
//
// WHY A DataSource AND NOT A FILE READ. updates.py keeps a JSON cache and
// `status` prints it immediately, refreshing behind itself only when stale -
// so polling it is cheap and never blocks on dnf or nix. Reading the cache
// file directly would be cheaper still and wrong: it would skip the refresh,
// and the count would go stale the moment nothing else ran the script.
//
// org.kde.plasma.plasma5support IS A SEPARATE PACKAGE on NixOS and is not in
// a stock Plasma closure - see kdePackages.plasma5support in
// fd44_nixos/modules/desktop-plasma.nix. Without it this file loads and the
// applet shows nothing at all, with the reason only in the journal.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // -1 means "not asked yet", which is NOT the same as 0 and must not show
    // a reassuring "up to date" before the first answer arrives.
    property int    count:   -1
    property string summary: ""
    property string errText: ""

    // THE SCRIPT IS FOUND THROUGH THIS PLASMOID'S OWN SYMLINK rather than a
    // hardcoded ~/Work/fd44_hyprdot. link-dotfiles.sh links
    // ~/.local/share/plasma/plasmoids/com.fd44.updates at the directory in the
    // checkout, so resolving that link and stripping the known suffix gives the
    // repository root wherever it was cloned - the same trick the shell scripts
    // use, and it survives the checkout being moved.
    readonly property string repoCmd:
        "d=$(readlink -f \"$HOME/.local/share/plasma/plasmoids/com.fd44.updates\") && " +
        "exec \"${d%/plasma/plasmoids/com.fd44.updates}/bin/updates.py\""

    // Papirus's own panel icons, which is why they look like the rest of the
    // tray rather than like a bolted-on applet: it ships update-none/low/
    // medium/high specifically for this job.
    //
    // THE THRESHOLDS MEAN DIFFERENT THINGS PER DISTRIBUTION and that is
    // honest rather than sloppy - updates.py says so itself. On Fedora and
    // Gentoo `count` is a number of packages; on NixOS it is DAYS BEHIND the
    // nixpkgs pin. A week behind and a week's worth of packages are both "a
    // little", which is the only claim these three icons make.
    readonly property string statusIcon:
          count <= 0  ? "update-none"
        : count < 7   ? "update-low"
        : count < 30  ? "update-medium"
                      : "update-high"

    Plasmoid.icon: statusIcon
    Plasmoid.status: count > 0 ? PlasmaCore.Types.ActiveStatus
                               : PlasmaCore.Types.HiddenStatus

    toolTipMainText: count > 0 ? (summary || (count + " waiting")) : "Up to date"
    toolTipSubText: errText !== "" ? errText : "Click to open the update screen"

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        // DISCONNECT FIRST, ALWAYS. A source left connected is re-run by the
        // engine on its own schedule, and the second run arrives as "new data"
        // for a command nobody asked to repeat.
        onNewData: (source, data) => {
            exec.disconnectSource(source)
            if (source.indexOf(" status") === -1) return
            root.parseStatus((data["stdout"] || "").trim(),
                             (data["stderr"] || "").trim())
        }

        function run(sub) { exec.connectSource("sh -c '" + root.repoCmd + " " + sub + "'") }
    }

    function parseStatus(out, err) {
        if (out === "") {
            root.errText = err !== "" ? err : "no output from updates.py"
            root.count = -1
            return
        }
        try {
            const j = JSON.parse(out)
            root.count   = j.count || 0
            root.summary = j.summary || ""
            root.errText = j.error || ""
        } catch (e) {
            root.errText = "unreadable output from updates.py"
            root.count = -1
        }
    }

    // Ten minutes, and the first one immediately. `status` is a cache read, so
    // this costs nothing; updates.py decides for itself when to go and ask the
    // package manager again.
    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.run("status")
    }

    // The click opens the same terminal screen the Hyprland bar opens. `open`
    // rather than `show`: show expects to already be in a terminal.
    function openScreen() { exec.run("open") }

    compactRepresentation: Item {
        Kirigami.Icon {
            anchors.fill: parent
            source: root.statusIcon
            active: mouse.containsMouse
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openScreen()
        }
    }

    // A full representation has to EXIST even though this applet never wants
    // one. Without it PlasmoidItem has nothing to fall back to when it decides
    // which form to show, and the tray draws neither - the applet loads, polls
    // and reports Active while rendering nothing at all, which is a very quiet
    // way to fail.
    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 6
        PlasmaComponents.Label {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.summary !== "" ? root.summary : "Nothing waiting"
        }
    }

    preferredRepresentation: compactRepresentation
}
