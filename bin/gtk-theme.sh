#!/usr/bin/env bash
# =========================================================================
# gtk-theme.sh - the GTK, icon and cursor themes Fedora does not package
# =========================================================================
#
# Usage:  bin/gtk-theme.sh            install anything missing (no root)
#         bin/gtk-theme.sh --status   what the palettes want vs what is here
#         bin/gtk-theme.sh --force    fetch again even if present
#         bin/gtk-theme.sh --remove   take them out again
#
# WHY THIS EXISTS, AND WHY IT IS NAMED THIS. bin/theme.sh has referred to
# "bin/gtk-theme.sh" in two comments since the GTK section was written, and the
# script was never there - no commit in this tree has ever contained it, the
# same as the bin/icon-theme.sh the README used to give three commands for.
# theme.sh reads an optional gtk_theme key from each palette, checks it with
# gtk_theme_installed(), and falls back to Adwaita-dark when it is missing. No
# palette set the key, so the fallback was the only path ever taken. This is
# the missing half.
#
# WHAT theme.sh DOES WITH WHAT THIS INSTALLS, so the two stay in step:
#
#   gtk-3.0   gsettings gtk-theme + ~/.config/gtk-3.0/settings.ini, so GTK3
#             apps follow a palette switch immediately.
#   gtk-4.0   theme.sh COPIES ~/.local/share/themes/<theme>/gtk-4.0/gtk.css to
#             ~/.config/gtk-4.0/gtk.css, because libadwaita ignores
#             gtk-theme-name entirely and reads that file once at startup. So a
#             theme is only useful to Nautilus if it SHIPS gtk-4.0/gtk.css -
#             Nordic does, which is why it is the one chosen here.
#   icons     gsettings icon-theme, then bin/icon-bridge.sh republishes the
#             categories where Qt can see them for quickshell.
#
# USER-LOCAL ON PURPOSE - ~/.local/share rather than /usr/share. These are not
# managed by dnf, and putting unmanaged files where a package manager expects to
# own things is how an upgrade removes them without saying so. The cost is that
# they do not survive a reinstall, which is what this script is for.
#
# PINNED AND CHECKSUMMED, the same as bin/install-nerd-font.sh. An icon theme
# that changes under you is a desktop that looks different for no reason you can
# name, and a release that moves is a release that can be replaced.
#
# NEITHER IS PACKAGED AND THE COPRS ARE DEAD. nordic-theme and
# nordzy-icon-theme are in no Fedora repository; of the two Nordzy COPRs,
# alvatip/Nordzy-icon last FAILED to build in January 2023 and
# rubemlrm/nordzy-icon last succeeded in May 2024. Checked, not assumed.

set -euo pipefail

SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

# kind | directory name | destination | url | sha256
#
# The directory name is what a palette's gtk_theme= or icon_theme= must say, and
# it is the top-level directory inside the tarball - verified, not guessed.
ITEMS=(
  "gtk|Nordic|$SHARE/themes|https://github.com/EliverLara/Nordic/releases/download/v2.2.0/Nordic.tar.xz|d162d694e13bec518636b193fbe84ccea44da9a81a89015c6713f6b258ee36d5"
  "icon|Nordzy-dark|$SHARE/icons|https://github.com/MolassesLover/Nordzy-icon/releases/download/1.8.7/Nordzy-dark.tar.gz|ad752b5ce70577408431734fc8004f928a00027a8fce6dd131ae2d0c3dc82069"
  "cursor|Bibata-Modern-Classic|$SHARE/icons|https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic.tar.xz|7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8"
)

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_d=$'\033[2m'; c_0=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_y" "$c_0" "$*" >&2; }
die()  { printf '%sgtk-theme:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

mode=install force=false
for a in "$@"; do
    case "$a" in
        --status) mode=status ;;
        --remove) mode=remove ;;
        --force)  force=true ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) die "unknown argument: $a" ;;
    esac
done

marker() { # kind dir -> the file whose presence means "installed"
    case "$1" in
        gtk)  printf '%s/index.theme' "$2" ;;
        icon) printf '%s/index.theme' "$2" ;;
        # A CURSOR THEME IS PROVED BY ITS cursors/ DIRECTORY, not index.theme.
        # Bibata ships both, but an index.theme alone is what a half-extracted
        # or wrong-variant download leaves behind, and a cursor theme without
        # cursors/ resolves to nothing - the pointer silently stays Adwaita.
        cursor) printf '%s/cursors' "$2" ;;
    esac
}

if [[ $mode == status ]]; then
    printf '  %-20s %-22s %s\n' KIND NAME STATE
    for e in "${ITEMS[@]}"; do
        IFS='|' read -r kind name dest _ _ <<<"$e"
        if [[ -e "$(marker "$kind" "$dest/$name")" ]]; then
            printf '  %-20s %-22s present  %s\n' "$kind" "$name" "$(du -sh "$dest/$name" 2>/dev/null | cut -f1)"
        else
            printf '  %-20s %-22s MISSING  (would go in %s)\n' "$kind" "$name" "${dest/#$HOME/\~}"
        fi
    done
    echo
    echo "  What the palettes ask for:"
    for f in "$(dirname "$0")"/../themes/*.conf; do
        g=$(sed -n 's/^gtk_theme=//p'  "$f" | head -1)
        i=$(sed -n 's/^icon_theme=//p' "$f" | head -1)
        printf '    %-22s gtk=%-18s icons=%s\n' "$(basename "$f" .conf)" "${g:-<Adwaita fallback>}" "${i:-none}"
    done
    exit 0
fi

if [[ $mode == remove ]]; then
    for e in "${ITEMS[@]}"; do
        IFS='|' read -r kind name dest _ _ <<<"$e"
        if [[ -d "$dest/$name" ]]; then
            rm -rf "${dest:?}/$name" && say "removed $name"
            [[ -L "$HOME/.icons/$name" ]] && rm -f "$HOME/.icons/$name" && say "  and its ~/.icons link"
        fi
    done
    echo
    echo "  theme.sh falls back to Adwaita-dark and Adwaita icons from here."
    echo "  Re-apply to make that take effect:  bin/theme.sh set \$(bin/theme.sh current)"
    exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

for e in "${ITEMS[@]}"; do
    IFS='|' read -r kind name dest url sha <<<"$e"

    if [[ -e "$(marker "$kind" "$dest/$name")" ]] && ! $force; then
        printf '    %salready%s  %s\n' "$c_d" "$c_0" "$name"
        continue
    fi

    say "fetching $name"
    ar="$TMP/$name.archive"
    curl -fsSL --retry 2 --max-time 240 "$url" -o "$ar" \
        || { warn "  could not download $name - skipping"; continue; }

    printf '%s  %s\n' "$sha" "$ar" | sha256sum --check --status \
        || { warn "  CHECKSUM MISMATCH for $name - refusing to install it"; continue; }

    # EXTRACTED INTO ITS OWN EMPTY DIRECTORY, and with python rather than tar:
    # tarfile's data filter refuses absolute paths and parent traversal, which a
    # downloaded archive should never contain and occasionally does. It also
    # handles .tar.xz and .tar.gz without caring which this is.
    mkdir -p "$TMP/x-$name" "$dest"
    python3 -I -c '
import sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    t.extractall(sys.argv[2], filter="data")
' "$ar" "$TMP/x-$name" || { warn "  could not extract $name"; continue; }

    [[ -d "$TMP/x-$name/$name" ]] \
        || { warn "  $name's archive does not contain a directory called $name - skipping"; continue; }

    rm -rf "${dest:?}/$name"
    cp -a "$TMP/x-$name/$name" "$dest/"
    printf '    installed %s (%s)\n' "${dest/#$HOME/\~}/$name" "$(du -sh "$dest/$name" | cut -f1)"

    # AND LINKED INTO ~/.icons, FOR CURSORS ONLY, BECAUSE XCURSOR DOES NOT LOOK
    # IN ~/.local/share/icons. The libxcursor search path - which the xcursor
    # crate niri uses follows too - is ~/.icons, /usr/share/icons,
    # /usr/share/pixmaps and a few X11 legacy directories. The XDG data
    # directory is NOT among them, so a cursor theme installed the modern,
    # correct way is invisible to the compositor.
    #
    # The symptom is silence rather than an error anywhere the user looks: the
    # pointer simply stays Adwaita. niri says so in its own log and nowhere
    # else:
    #
    #   WARN niri::cursor: error loading xcursor default@64: no default icon
    #
    # GTK and the icon spec want ~/.local/share/icons, so the theme stays there
    # and ~/.icons gets a symlink: one copy on disk, both lookups satisfied.
    if [[ $kind == cursor ]]; then
        mkdir -p "$HOME/.icons"
        ln -sfn "$dest/$name" "$HOME/.icons/$name"
        printf '    linked    ~/.icons/%s  (xcursor does not search ~/.local/share/icons)\n' "$name"
    fi

    # GTK4 WITHOUT THIS IS THE WHOLE POINT FOR NAUTILUS, so say so when a theme
    # cannot do it rather than leaving it to be noticed later.
    if [[ $kind == gtk && ! -f "$dest/$name/gtk-4.0/gtk.css" ]]; then
        warn "  $name ships no gtk-4.0/gtk.css - GTK4 apps (Nautilus) will stay Adwaita"
    fi
done

# ----------------------------------------------------------------------------
# Nordzy's Pictures and Videos folders are the wrong colour, and it is a typo
# ----------------------------------------------------------------------------
#
# Every folder icon in this theme draws its emblem - the page, the arrow, the
# note, the "A" - as  fill="#81a1c1", Nord frost blue. Two do not:
# folder-images.svg and folder-videos.svg draw theirs as
#
#     <path class="ColorScheme-Text" color="#363636" opacity=".15" .../>
#
# `color` in SVG only sets what `currentColor` resolves to; IT PAINTS NOTHING
# BY ITSELF. There is no fill on the path and no .ColorScheme-Text rule
# anywhere in the file, so it falls back to the default fill, which is black.
# Those two emblems render as a black wash at 15% while every other folder gets
# a clear blue symbol - which is exactly how it was noticed: Pictures and Videos
# looked heavier and darker than everything beside them in Nautilus.
#
# folder-pictures.svg is a symlink to folder-images.svg, so patching one fixes
# both names.
#
# PATCHED HERE RATHER THAN REPORTED AND WAITED FOR, because the theme is pinned:
# the version installed above is the version that will be installed for ever
# until someone changes the checksum, so an upstream fix would never arrive on
# its own anyway.
#
# IT CHECKS BEFORE IT WRITES. If the pattern is not there - a different version,
# or upstream fixed it - nothing is touched and nothing is said. The patch must
# never be the reason a future update appears to install and then look wrong.
fix_nordzy_emblems() {
    local dir="$SHARE/icons/Nordzy-dark/places/scalable"
    [[ -d $dir ]] || return 0
    python3 -I - "$dir" <<'PY'
import pathlib, re, sys

d = pathlib.Path(sys.argv[1])
FOLDER_BASE = "#2e3440"          # the dark shading every folder shares
fixed = []

for f in sorted(d.glob("*.svg")):
    if f.is_symlink():           # folder-pictures -> folder-images, one file
        continue
    t = f.read_text(errors="replace")

    # The broken element: names a class, carries no fill, and the file defines
    # no rule for that class - so it paints with the default, which is black.
    m = re.search(r'<path class="(ColorScheme-[\w-]+)"(?![^>]*fill=)', t)
    if not m:
        continue
    cls = m.group(1)
    if re.search(r"\." + re.escape(cls) + r"\s*\{[^}]*(color|fill)\s*:", t):
        continue

    # THE SHADING COLOUR, NOT THE ACCENT, AND THE OPACITY STAYS.
    #
    # Every folder in this theme is built the same way: six paths, where the
    # emblem - the page, the people, the "A" - is drawn as FOLDER_BASE at .15,
    # a dark tint over the light folder face. Pictures and Videos carry a
    # SEVENTH path for their extra detail, and it is that one upstream left
    # unpainted.
    #
    # An earlier attempt gave it the accent at full opacity. That is the colour
    # of the folder face itself, so the emblem washed out into the folder and
    # came out hollow and pale next to Public and Templates - which is what the
    # screenshot of it showed. The fix is the shading the other five paths
    # already use.

    # THE WHOLE ELEMENT IS REWRITTEN, not just its opening attribute. The
    # attributes sit AFTER the d="..." path data:
    #
    #   <path class="ColorScheme-Text" d="…" color="#363636" opacity=".15" .../>
    #
    # so a substitution anchored between fill and d silently strips nothing -
    # which left opacity=".15" in place and the emblem at 15%, the same faint
    # result the first attempt at this produced. `color` paints nothing on its
    # own and the .15 was shading for a wash, not for the emblem itself; both go.
    elem = re.search(r"<path class=\"" + re.escape(cls) + r"\"[^>]*>", t)
    if not elem:
        continue
    new_elem = elem.group(0)
    new_elem = new_elem.replace(f'class="{cls}"', f'fill="{FOLDER_BASE}"', 1)
    # `color` paints nothing on its own and is what upstream meant to be a
    # fill; it goes. opacity STAYS - .15 is the tint every other emblem uses.
    new_elem = re.sub(r'\s+color="[^"]*"', "", new_elem)
    if 'opacity=' not in new_elem:
        new_elem = new_elem.replace("/>", ' opacity=".15"/>')
    t = t[:elem.start()] + new_elem + t[elem.end():]
    f.write_text(t)
    fixed.append(f.name)

for n in fixed:
    print(f"    recoloured {n}")
if fixed:
    print(f"    {len(fixed)} folder icons were painting their emblem black")
PY
    command -v gtk-update-icon-cache >/dev/null 2>&1 \
        && gtk-update-icon-cache -qf "$SHARE/icons/Nordzy-dark" 2>/dev/null || true
}

fix_nordzy_emblems

cat <<'NEXT'

  Installed under ~/.local/share and unmanaged by dnf, so a reinstall loses
  them and this script puts them back.

  Nothing is themed until a palette names them and the theme is re-applied:
    bin/theme.sh set nord

  GTK3 apps follow immediately. GTK4 and libadwaita apps - Nautilus among them -
  read their stylesheet once at startup, so they change when next started.
NEXT
