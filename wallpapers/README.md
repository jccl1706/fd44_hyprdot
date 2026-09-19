# wallpapers

Drop image files here - `.png`, `.jpg`, `.jpeg` or `.webp`. The picker
(Super+W, `quickshell/WallpaperPicker.qml`) lists whatever is in this
directory; there is nothing to register.

A NOTE ON PUTTING THEM IN GIT: this repository is public, so anything added
here is redistributed to anyone who clones it. Fine for your own work or
something CC0; check the licence before committing a wallpaper you merely
downloaded. They are also binary and never diff, so each revision is stored
whole - a handful of 4K images will outweigh every line of code in the repo.
If that becomes a problem, move them to ~/Pictures/wallpapers and point
Theme.wallpaperDir at that instead.

## Where these came from

Most of them are from Omarchy (github.com/omacom/omarchy, MIT), whose
`themes/*/backgrounds/` directories are where this set was picked from. They
are renamed `<theme>-<name>.webp` here, the numeric ordering prefix dropped,
and re-encoded to 2560px wide webp to match the rest - Omarchy ships
originals up to 6000px, and copying them untouched would have been 46 MB
against the 20 MB they take now.

Omarchy's repository carries one MIT licence covering its code and no
attribution for the images themselves, so the provenance of individual
wallpapers is not documented there and is not documented here either. That
is worth knowing before reusing one of these somewhere it matters. Omarchy's
own branded wallpapers - the ones carrying its logo - are deliberately not
included.
