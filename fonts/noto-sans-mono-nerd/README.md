# NotoSansM Nerd Font

`NotoSansMNerdFont-Regular.ttf` and `-Bold.ttf`, Nerd Fonts **v3.4.0**, vendored
here rather than downloaded during installation — the same reasoning as
`../nerd-fonts-symbols/`.

    sha256  b0ff50dd584ccabb3eb3f2c2e41a082cd3ac47d25bd32f20aa78aa15c0987b71  Regular
    sha256  39fbc1abcb4529087b156fe031afa03ea41243273a0ebd05ca1c8849231018ee  Bold
    source  https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Noto.tar.xz
    sha256  e28b31609d17fc50bdf9e6730c947a61b0e474af726c2c044c39bc78fcd9bfde  (the archive)

Two faces out of a 68 MB family archive. Noto Sans Mono has no italic face;
both terminals synthesise one, which is what they did before this font arrived.

## Why a patched font, when Symbols Nerd Font is already here

Because a symbols-only fallback cannot draw a separator that fits the cell.

The tmux status bar builds its pills out of half-circle caps at U+E0B6 and
U+E0B4. Measured at 11pt on fedora-gaming00:

    terminal cell                    13.2 px wide x 31 px tall
    cap from Symbols Nerd Font       advance 11.8, ink height 23
    cap from NotoSansM Nerd Font     advance 13.2, ink height 31

Symbols Nerd Font draws those glyphs inside its own em box — it is a
symbols-only face and was never scaled to any particular text font — so the cap
came out 1.4 px narrow and 8 px short and the pill ended in a step instead of a
curve. A patched font is the same glyphs rescaled to the host font's metrics,
which is the entire point of patching.

kitty hid this for a long time by rescaling fallback symbols to the cell
itself. alacritty does not, and draws what the font hands it, which is how a
fault that had always been there became visible the day a second terminal was
configured.

## What still needs Symbols Nerd Font

Everything that is not a terminal: waybar, quickshell, fuzzel, the OSD and the
lock screen all ask for a UI font and pick up the icons through the fontconfig
fallback in `../../fontconfig/99-nerd-fallback.conf`. That file and this font
solve different halves of the same problem and neither replaces the other.
