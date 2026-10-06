#!/usr/bin/env bash
# =========================================================================
# font-setup.sh - Inter, and type that renders the way macOS renders it
# =========================================================================
#
# Usage:  sudo bin/font-setup.sh [--go]
#         sudo bin/font-setup.sh --remove
#
# Two halves. The package is a system install and needs root; the settings
# belong to the account and are written as $SUDO_USER.
#
# WHAT "LIKE macOS" MEANS HERE, since it is a look rather than a setting:
#
#   HINTING ALMOST OFF. This is the whole difference. Windows and the
#   default Linux configuration snap glyph stems onto the pixel grid, which
#   is crisp and changes the letterforms. macOS does nearly none of it and
#   lets the shapes be what the designer drew, which reads as softer and
#   rounder. hintslight keeps the vertical snapping that stops text
#   swimming between sizes and drops the rest.
#
#   SUBPIXEL RENDERING ON, with the default LCD filter. macOS dropped
#   subpixel antialiasing in Mojave, but it did so for Retina panels where
#   the pixels are too small to matter. This is a 1440p 27" desktop, where
#   greyscale-only antialiasing looks thin and fuzzy rather than Apple-like.
#
#   NO AUTOHINTER. FreeType's autohinter overrides a font's own hints and
#   is the opposite of what is wanted here.
#
# INTER rather than Helvetica or SF: those are not redistributable, and
# Inter was drawn for user interfaces at small sizes, which is the job.
set -euo pipefail

green=$'\033[1;32m'; red=$'\033[1;31m'; bold=$'\033[1m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sfonts:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

(( EUID == 0 )) || die "run this with sudo - the font package is a system install"
U="${SUDO_USER:-jc}"
U_HOME="$(getent passwd "$U" | cut -d: -f6)"
FC_DIR="$U_HOME/.config/fontconfig/conf.d"
FC="$FC_DIR/99-fd44-rendering.conf"

as_user() { sudo -u "$U" env HOME="$U_HOME" XDG_RUNTIME_DIR="/run/user/$(id -u "$U")" "$@"; }

if [[ ${1-} == --remove ]]; then
    rm -f "$FC"
    as_user fc-cache -f >/dev/null
    note "removed $FC - KDE's own font settings are left alone"
    exit 0
fi

if [[ ${1-} != --go ]]; then
    note "would install rsms-inter-fonts"
    note "would write $FC (hintslight, subpixel rgb, no autohinter)"
    note "would set the interface fonts to Inter for $U"
    warn "DRY RUN. Re-run with --go."
    exit 0
fi

note "installing Inter"
dnf -y install rsms-inter-fonts >/dev/null
printf '  rsms-inter-fonts %s\n' "$(rpm -q --qf '%{VERSION}' rsms-inter-fonts)"

note "font rendering"
install -d -o "$U" -g "$U" -m 0755 "$FC_DIR"
cat > "$FC" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- Written by fd44_hyprdot bin/font-setup.sh. See that script for why. -->
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <!-- The one that matters: nearly no hinting, so letterforms keep their
         drawn shape instead of being snapped onto the pixel grid. -->
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
    <!-- FreeType's autohinter replaces the font's own hints, which undoes
         the line above. -->
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
    <!-- Bitmap strikes inside scalable fonts ignore all of this. -->
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>
</fontconfig>
XML
chown "$U:$U" "$FC"
as_user fc-cache -f >/dev/null
printf '  %s\n' "$FC"

# QT'S FONT STRING, WHICH IS POSITIONAL AND UNFORGIVING:
#   family,pointSize,pixelSize,styleHint,weight,italic,underline,strikeOut,
#   fixedPitch,rawMode,...  A wrong field count is accepted and then ignored,
#   which looks exactly like the setting not having been written.
note "interface fonts for $U"
set_font() { as_user kwriteconfig6 --file kdeglobals --group General --key "$1" "$2"; }
set_font font              "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
set_font menuFont          "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
set_font toolBarFont       "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
set_font smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
as_user kwriteconfig6 --file kdeglobals --group WM --key activeFont \
    "Inter,10,-1,5,500,0,0,0,0,0,0,0,0,0,0,1"

# AND THE SAME RENDERING FOR QT, which reads these rather than fontconfig.
as_user kwriteconfig6 --file kdeglobals --group General --key XftAntialias true
as_user kwriteconfig6 --file kdeglobals --group General --key XftHintStyle hintslight
as_user kwriteconfig6 --file kdeglobals --group General --key XftSubPixel rgb

printf '\n'
note "done"
printf '  %-10s %s\n' "font"      "$(as_user kreadconfig6 --file kdeglobals --group General --key font)"
printf '  %-10s %s\n' "hinting"   "$(as_user kreadconfig6 --file kdeglobals --group General --key XftHintStyle)"
printf '  %-10s %s\n' "subpixel"  "$(as_user kreadconfig6 --file kdeglobals --group General --key XftSubPixel)"
printf '\n'
warn "LOG OUT AND BACK IN. Applications read their font at startup, so a"
warn "running session shows the change only in what it restarts."
