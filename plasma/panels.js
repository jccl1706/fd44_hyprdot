// A top bar and a floating dock, for Plasma 6.
//
// Run through bin/plasma-panels.sh, which hands this to plasmashell's own
// scripting interface. IT REPLACES EVERY PANEL on every screen: the point is a
// layout that can be rebuilt identically after a reinstall, not one that
// accumulates whatever was there before.
//
// WHY A SCRIPT AND NOT A SAVED appletsrc. plasma-org.kde.plasma.desktop-appletsrc
// is rewritten by plasmashell whenever anything moves, carries applet ids that
// are generated per machine, and is not something to hand-edit or diff. The
// scripting API is the supported way to describe a layout, and it reads as a
// description rather than a dump.

var removed = 0;
var old = panels();
for (var i = 0; i < old.length; i++) { old[i].remove(); removed++; }

// --- the top bar -------------------------------------------------------------
//
// Full width and slim: this is the bar that is always there, so it gets the
// things you read rather than the things you click - what window has focus and
// its menus, the time, and the tray.
var top = new Panel;
top.location = "top";
// A NUMBER, BECAUSE theme IS NOT IN THIS API. Plasma 5's scripting interface
// exposed theme.defaultFont; Plasma 6's does not, and reading it throws
// "Cannot read property 'pixelSize' of undefined" before anything is created.
top.height = 42;   // room for a 15px bold clock with the date under it
top.hiding = "none";
try { top.lengthMode = "fill"; } catch (e) {}
try { top.floating = false; } catch (e) {}

top.addWidget("org.kde.plasma.kickoff");
// THE GLOBAL MENU, which is what makes a top bar worth having rather than just
// a second place to put a clock. Applications that export their menus - every
// KDE one, and GTK apps through the portal - show them here instead of in their
// own title bars.
var menu = top.addWidget("org.kde.plasma.appmenu");
top.addWidget("org.kde.plasma.panelspacer");

var clock = top.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd d MMM");
// BIG AND BOLD, AND THEREFORE NOT AUTOMATIC. The clock sizes itself to the
// panel unless autoFontAndSize is off; with it off these three take over.
// Weight 700 is Bold - Inter has a real bold, so nothing is synthesised.
clock.writeConfig("autoFontAndSize", false);
clock.writeConfig("fontFamily", "Inter");
clock.writeConfig("fontWeight", 700);
clock.writeConfig("fontSize", 15);

top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.kde.plasma.systemtray");

// --- the dock ----------------------------------------------------------------
//
// Floating, centred, and only as wide as its icons: a dock rather than a second
// panel. lengthMode "fit" is what stops it stretching across the screen.
var dock = new Panel;
dock.location = "bottom";
// SMALL ENOUGH TO READ AS A DOCK, AND NARROW BECAUSE OF IT. icontasks sizes
// its icons from the panel height and gives each one a cell about that wide, so
// this number sets the dock's width as much as its height: seven icons at 64
// was a bar, four at 44 is a dock.
dock.height = 44;
// DODGE WINDOWS: in plain sight on an empty desktop, out of the way the moment
// a window would overlap it - which is what "hide when something is maximised
// or fullscreen" means. Not "autohide", which keeps it hidden always and wants
// a deliberate shove at the screen edge even when nothing is in the way.
//
// It also stops the dock reserving 64px forever: with "none" every window
// maximises to just above it, which is a strut, not a dock.
//
// THE ACCEPTED VALUES ARE NOT WHAT THE PLASMA 5 DOCUMENTATION SAYS, and a
// wrong one is taken silently - the property simply reads back "none"
// afterwards, with no error anywhere. Measured against plasmashell 6.7.5:
//
//   autohide       accepted      windowscover    REJECTED
//   dodgewindows   accepted      windowsgobelow  REJECTED
//
// So read it back after setting it, as bin/plasma-panels.sh does.
dock.hiding = "dodgewindows";
try { dock.alignment = "center"; } catch (e) {}
try { dock.lengthMode = "fit"; } catch (e) {}
try { dock.floating = true; } catch (e) {}

// ICON TASKS, NOT THE TEXT ONE. A dock shows what is running as icons and keeps
// the launchers in the same row, so a pinned application and its window are the
// same object rather than two.
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
// FOUR, NOT SEVEN. A dock is for what you reach for without thinking; the
// launcher is two keystrokes away for everything else. virt-manager, Spectacle
// and System Settings came out because each one was costing a cell's width to
// save a keystroke nobody minds typing. Anything running still appears here
// whether it is pinned or not.
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:brave-browser.desktop",
    "applications:steam.desktop"
].join(","));
tasks.writeConfig("showOnlyCurrentDesktop", false);
tasks.writeConfig("indicateAudioStreams", true);
// SPACE BETWEEN THE TILES. A running application gets a filled tile behind its
// icon, and at spacing 2 those tiles touch - so seven running applications read
// as one striped block rather than seven icons in a dock.
tasks.writeConfig("iconSpacing", 4);
tasks.writeConfig("maxStripes", 1);

print("removed " + removed + " panel(s); top bar at " + top.height +
      "px, dock at " + dock.height + "px");
