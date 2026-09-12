# Symbols Nerd Font

`SymbolsNerdFont-Regular.ttf`, Nerd Fonts **v3.4.0**, vendored here rather
than downloaded during installation.

    sha256  71db104aa66567d0efe0b98758f9dfc1895573a453fe85fb53d1c38544a55106
    source  https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.tar.xz

## Why it is committed

Fedora packages no Symbols Nerd Font — the only "nerd" font in the repos is
`texlive-inconsolata-nerd-font`, which is unrelated — so it has to come from
somewhere. Downloading it during the install made it the one step that reached
the public internet and was allowed to fail, and when it failed every glyph in
the bar, launcher, OSD, power menu and lock screen rendered as an empty box.

Committing it also pins the version for real. The repair script used to reuse
whatever copy it found on the machine, which on the development laptop was
3.5.1 while the installer pinned 3.4.0 — the two disagreed silently. One file
in git cannot.

All 27 glyphs this project uses are in the `U+F0xxx` Material Design Icons
range, which Nerd Fonts passes through at MDI's own codepoints.

## Licence

MIT, per the `LICENSE` file beside it — the one shipped in the same directory
as the font in the upstream release. It grants the right to "use, copy,
modify, merge, publish, distribute", on the condition that the notice travels
with the font, which is why `LICENSE` is committed here too rather than only
referenced.
