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
top.height = 36;
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
clock.writeConfig("fontWeight", 500);

top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.kde.plasma.systemtray");

// --- the dock ----------------------------------------------------------------
//
// Floating, centred, and only as wide as its icons: a dock rather than a second
// panel. lengthMode "fit" is what stops it stretching across the screen.
var dock = new Panel;
dock.location = "bottom";
// 64 RATHER THAN 56: icontasks sizes its icons from the panel height, and at
// 56 they sat in the middle of a band of empty background. A dock is mostly
// icon, which is the whole visual difference between it and a panel.
dock.height = 64;
dock.hiding = "none";
try { dock.alignment = "center"; } catch (e) {}
try { dock.lengthMode = "fit"; } catch (e) {}
try { dock.floating = true; } catch (e) {}

// ICON TASKS, NOT THE TEXT ONE. A dock shows what is running as icons and keeps
// the launchers in the same row, so a pinned application and its window are the
// same object rather than two.
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:brave-browser.desktop",
    "applications:steam.desktop",
    "applications:virt-manager.desktop",
    "applications:org.kde.spectacle.desktop",
    "applications:systemsettings.desktop"
].join(","));
tasks.writeConfig("showOnlyCurrentDesktop", false);
tasks.writeConfig("indicateAudioStreams", true);
tasks.writeConfig("iconSpacing", 2);
tasks.writeConfig("maxStripes", 1);

print("removed " + removed + " panel(s); top bar at " + top.height +
      "px, dock at " + dock.height + "px");
