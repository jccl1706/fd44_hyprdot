# JetBrains Mono

`JetBrainsMono-Bold.otf`, JetBrains Mono **2.304**, vendored here for
MangoHud.

    sha256  aeb06620f935cd8c75769154228943ca1051962727eb07213a8bb7f31dbb9c36
    source  Fedora's jetbrains-mono-fonts-2.304-10.fc44, which packages
            https://github.com/JetBrains/JetBrainsMono
    licence SIL Open Font License 1.1 — see LICENSE

## Why it is committed

**MangoHud wants a FILE PATH, not a font name.** Everything else in this repo
asks fontconfig for "JetBrains Mono" and gets whatever the system has;
`mangohud/presets.conf` cannot, so it has to name a path — and a path that is
correct on one of these machines is wrong on the other:

| | |
| --- | --- |
| Fedora | `/usr/share/fonts/jetbrains-mono-fonts/JetBrainsMono-Bold.otf` |
| NixOS  | there is no `/usr/share` at all; the font is at a `/nix/store` path that changes on every update |

The presets used to name the Fedora path. On nixos-gaming00 that file does not
exist, so MangoHud fell back to its built-in font — silently, which is the worst
part: the overlay looked fine and was simply not the font the presets asked for,
so the two machines rendered differently with nothing to indicate why.

Committing it gives one absolute path that resolves on both, because both check
the repository out to the same place. It is the same reasoning as
`../nerd-fonts-symbols`, which is vendored because Fedora packages no Symbols
Nerd Font at all.

2.304 is also the version nixpkgs ships, so this is not a second font competing
with the system one — it is the same font, reachable by a path that does not
move.

## If you would rather not carry a font

Delete the `font_file` lines from `mangohud/presets.conf`. MangoHud falls back
to its built-in font, which is legible and identical on both machines. What you
lose is the overlay matching the terminal and the bar.
