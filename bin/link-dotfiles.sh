#!/usr/bin/env bash
#
# Point ~/.config at this checkout, so a reinstalled machine is two steps:
# clone, then run this.
#
# WHY A SCRIPT AND NOT A LIST IN THE README. The list was in four places and
# none of them was complete: the README linked four directories in one block
# and tmux in another 176 lines later, fd44_nixos/modules/desktop.nix named
# three, and starship and MangoHud were made by their own setup scripts. A
# machine rebuilt from any one of those came back missing things, and the two
# machines had already drifted apart without anyone noticing.
#
# NOTHING HERE IS DECLARATIVE, deliberately. These are files edited daily; a
# symlink means an edit is live, while putting them in the Nix store means a
# rebuild to change a colour. home-manager would only cover the NixOS machine
# anyway, and every time this configuration has differed between machines it has
# produced a bug.
#
# Safe to run as often as you like: a link that is already right is left alone,
# one pointing somewhere else is repointed, and a REAL file or directory in the
# way is reported rather than replaced - that is somebody's configuration, and a
# fresh install writes several of these itself.
#
# Usage:
#   bin/link-dotfiles.sh              # make the links
#   bin/link-dotfiles.sh --dry-run    # say what it would do
#   bin/link-dotfiles.sh --all        # include the ones this machine skips

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

dry_run=false
force_all=false
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) dry_run=true ;;
        -a|--all)     force_all=true ;;
        -h|--help)    sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed 's/^#//; s/^ //'; exit 0 ;;
        *) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

made=0 already=0 fixed=0 skipped=0 blocked=0

note()    { printf '  %s\n' "$*"; }
ok()      { printf '  \033[32m%-9s\033[0m %s\n' "$1" "$2"; }
warn()    { printf '  \033[33m%-9s\033[0m %s\n' "$1" "$2"; }
blocked() { printf '  \033[31m%-9s\033[0m %s\n' "$1" "$2"; }

# link <source relative to the repo> <destination>
link() {
    local src="$REPO/$1" dst="$2" shown="${2/#$HOME/\~}"
    if [ ! -e "$src" ]; then
        warn "missing" "$shown - $1 is not in the checkout"
        skipped=$((skipped + 1))
        return
    fi
    if [ -L "$dst" ]; then
        local current
        current="$(readlink -f "$dst" 2>/dev/null)"
        if [ "$current" = "$(readlink -f "$src")" ]; then
            ok "ok" "$shown"
            already=$((already + 1))
            return
        fi
        # A link somewhere else is ours to correct; a real file is not.
        if $dry_run; then
            warn "would fix" "$shown (points at ${current:-nothing})"
        else
            ln -sfn "$src" "$dst" && warn "repointed" "$shown (was ${current:-nothing})"
        fi
        fixed=$((fixed + 1))
        return
    fi
    if [ -e "$dst" ]; then
        blocked "in the way" "$shown is a real $( [ -d "$dst" ] && echo directory || echo file ) - move it aside first"
        blocked=$((blocked + 1))
        return
    fi
    if $dry_run; then
        note "would link $shown -> ${src/#$HOME/\~}"
    else
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst" && ok "linked" "$shown"
    fi
    made=$((made + 1))
}

# --- what this machine has ------------------------------------------------
#
# Two of these are not wanted everywhere, and linking them regardless would put
# configuration on machines that have nothing to read it.

has_battery() { compgen -G "/sys/class/power_supply/BAT*" >/dev/null; }
has_mangohud() { command -v mangohud >/dev/null 2>&1; }

printf '\nlinking into %s\n\n' "${REPO/#$HOME/\~}"

link hypr                   "$CONFIG/hypr"
link quickshell             "$CONFIG/quickshell"
link kitty                  "$CONFIG/kitty"
link tmux                   "$CONFIG/tmux"
link starship/starship.toml "$CONFIG/starship.toml"
link wireplumber            "$CONFIG/wireplumber"

# MangoHud, where there is a MangoHud. Linked file by file rather than as a
# directory: other things write into ~/.config/MangoHud, so it is not ours to own.
if has_mangohud || $force_all; then
    link mangohud/MangoHud.conf "$CONFIG/MangoHud/MangoHud.conf"
    link mangohud/presets.conf  "$CONFIG/MangoHud/presets.conf"
else
    note "skipped   MangoHud - not installed here (--all to link anyway)"
    skipped=$((skipped + 2))
fi

# The power-mode unit switches the CPU governor on AC and battery, so it has
# nothing to do on a machine that is always on mains.
if has_battery || $force_all; then
    link systemd/power-mode.service "$CONFIG/systemd/user/power-mode.service"
else
    note "skipped   power-mode.service - no battery here (--all to link anyway)"
    skipped=$((skipped + 1))
fi

printf '\n  %d linked, %d already right, %d repointed, %d skipped, %d in the way\n' \
    "$made" "$already" "$fixed" "$skipped" "$blocked"

if [ "$blocked" -gt 0 ]; then
    printf '\n  Something real is where a link should go. Look at it, move it aside,\n'
    printf '  and run this again - it was not overwritten.\n'
fi

if [ "$made" -gt 0 ] || [ "$fixed" -gt 0 ]; then
    $dry_run || cat <<'NEXT'

  Two of these need telling:
    systemctl --user restart wireplumber
    systemctl --user daemon-reload && systemctl --user enable --now power-mode.service

  And the rest of a fresh machine, each opt-in and each explaining itself:
    bin/starship-setup.sh    the two-line prompt
    bin/icon-theme.sh        the Reversal icons the palettes ask for
    bin/gaming-setup.sh      MangoHud, gamemode and the Steam pieces
NEXT
fi

exit $(( blocked > 0 ? 1 : 0 ))
