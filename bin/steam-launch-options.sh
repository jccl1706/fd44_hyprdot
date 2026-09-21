#!/usr/bin/env bash
# =========================================================================
# steam-launch-options.sh - put the fd44 launch options on every game
# =========================================================================
#
# Usage:
#   bin/steam-launch-options.sh --status    what each installed game has
#   bin/steam-launch-options.sh --dry-run   what would change, changing nothing
#   bin/steam-launch-options.sh             set them on games that have none
#   bin/steam-launch-options.sh --force     replace options that differ too
#
# WHY THIS IS NOT DECLARATIVE. Steam has no global launch options - the setting
# is per game, stored in a per-user localconfig.vdf, and there is no supported
# file or flag that applies one to everything. So every newly installed game
# starts without MangoHud and without GameMode until somebody opens Properties
# and types the same line again. This does that typing.
#
# WHAT IT SETS, and why each half matters:
#
#   mangohud fd44-gamemode-hold %command%
#
#   mangohud              the overlay, as a Vulkan layer
#   fd44-gamemode-hold    GameMode across the pressure-vessel boundary. NOT
#                         `gamemoderun`, which silently does nothing under
#                         Proton: the container empties LD_PRELOAD, so
#                         GameMode's library unloads and deregisters before
#                         the game has started. See bin/gaming-setup.sh.
#
# STEAM MUST BE CLOSED. It holds localconfig.vdf in memory and writes it out on
# exit, so an edit made while it is running is discarded without a word - the
# same trap as CoolerControl's config.toml. This refuses to run rather than
# letting that happen quietly.
#
# ONLY GAMES THAT HAVE NONE, unless --force. A launch option someone set
# deliberately - a resolution flag, a Proton override - is not ours to
# overwrite, and finding it silently replaced is a bad afternoon.

set -euo pipefail

OPTS='mangohud fd44-gamemode-hold %command%'

mode=apply
force=0
for a in "$@"; do
    case "$a" in
        --status)  mode=status ;;
        --dry-run) mode=dry ;;
        --force)   force=1 ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'steam-launch-options: unknown argument %s\n' "$a" >&2; exit 1 ;;
    esac
done

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

here="$(cd "$(dirname "$0")" && pwd)"

# The games, from the scanner that already knows how to tell one from a tool.
mapfile -t games < <("$here/steam-games.sh" --pretty)
(( ${#games[@]} )) || die "no Steam games found - is Steam installed and are any games installed?"

# localconfig.vdf lives under the numeric Steam user id. More than one account
# on a machine is possible; take the one that has been written most recently.
cfg="$(ls -t "$HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf 2>/dev/null | head -1 || true)"
[[ -n $cfg ]] || die "no localconfig.vdf under ~/.local/share/Steam/userdata"

appid_of() { sed -n 's/.*"appid":"\([0-9]*\)".*/\1/p' <<<"$1"; }
name_of()  { sed -n 's/.*"name":"\(.*\)"}.*/\1/p'      <<<"$1"; }

# What a game's block currently holds, if anything: prints the existing
# LaunchOptions value, or nothing when the key or the block is absent.
current_opts() {
    awk -v want="$1" '
        $0 ~ "^\t+\"" want "\"$" { pend = 1; next }
        pend && $0 ~ /^\t+\{$/   { inb = 1; pend = 0; d = 1; next }
        pend { pend = 0 }
        inb {
            if ($0 ~ /\{[[:space:]]*$/) d++
            else if ($0 ~ /^\t+\}$/) { d--; if (d == 0) inb = 0 }
            if (match($0, /"LaunchOptions"[ \t]+"[^"]*"/)) {
                s = substr($0, RSTART, RLENGTH)
                sub(/^"LaunchOptions"[ \t]+"/, "", s); sub(/"$/, "", s)
                print s; exit
            }
        }
    ' "$cfg"
}

has_block() {
    awk -v want="$1" '
        $0 ~ "^\t+\"" want "\"$" { pend = 1; next }
        pend && $0 ~ /^\t+\{$/ { print "yes"; exit }
        pend { pend = 0 }
    ' "$cfg"
}

# --- status ---------------------------------------------------------------

if [[ $mode == status ]]; then
    printf 'config: %s\n\n' "$cfg"
    for g in "${games[@]}"; do
        id="$(appid_of "$g")"; nm="$(name_of "$g")"
        cur="$(current_opts "$id")"
        if [[ -z $(has_block "$id") ]]; then
            printf '  %-28s %s\n' "$nm" "no config block yet"
        elif [[ -z $cur ]]; then
            printf '  %-28s %s\n' "$nm" "MISSING"
        elif [[ $cur == "$OPTS" ]]; then
            printf '  %-28s %s\n' "$nm" "ok"
        else
            printf '  %-28s %s\n' "$nm" "differs: $cur"
        fi
    done
    exit 0
fi

# --- apply ----------------------------------------------------------------

if [[ $mode == apply ]] && pgrep -x steam >/dev/null 2>&1; then
    die "Steam is running. It writes localconfig.vdf on exit and would discard
       this edit without saying so. Close Steam (steam -shutdown) and re-run."
fi

changed=0
for g in "${games[@]}"; do
    id="$(appid_of "$g")"; nm="$(name_of "$g")"
    cur="$(current_opts "$id")"

    if [[ -z $(has_block "$id") ]]; then
        printf '  %-28s skipped - no config block; launch it once from Steam\n' "$nm"
        continue
    fi
    if [[ $cur == "$OPTS" ]]; then
        printf '  %-28s already set\n' "$nm"; continue
    fi
    if [[ -n $cur && $force -eq 0 ]]; then
        printf '  %-28s has its own options, left alone: %s\n' "$nm" "$cur"
        printf '  %-28s (use --force to replace)\n' ""
        continue
    fi

    if [[ $mode == dry ]]; then
        printf '  %-28s would %s\n' "$nm" "${cur:+replace \"$cur\" with}${cur:+ }set"
        continue
    fi

    [[ -f "$cfg.fd44-bak" ]] || { cp "$cfg" "$cfg.fd44-bak"; log "backup: $cfg.fd44-bak"; }

    tmp="$(mktemp "${cfg}.XXXXXX")"
    awk -v want="$id" -v opts="$OPTS" '
        BEGIN { done = 0 }
        {
            line = $0
            if (!done && !inb && line ~ "^\t+\"" want "\"$") { pend = 1; print line; next }
            if (pend) {
                if (line ~ /^\t+\{$/) { inb = 1; d = 1; pend = 0; indent = line; sub(/\{$/, "", indent) }
                else pend = 0
                print line; next
            }
            if (inb) {
                # Replace an existing key rather than adding a second one.
                if (line ~ /"LaunchOptions"[ \t]+"/) {
                    printf "%s\t\"LaunchOptions\"\t\t\"%s\"\n", indent, opts
                    done = 1; next
                }
                if (line ~ /\{[[:space:]]*$/) d++
                else if (line ~ /^\t+\}$/) {
                    d--
                    if (d == 0) {
                        if (!done) { printf "%s\t\"LaunchOptions\"\t\t\"%s\"\n", indent, opts; done = 1 }
                        inb = 0
                    }
                }
            }
            print line
        }
        END { if (!done) exit 3 }
    ' "$cfg" > "$tmp" || { rm -f "$tmp"; die "could not place the option for $nm ($id)"; }

    # Braces must still balance, or Steam will reject the file and lose every
    # per-game setting in it.
    bal="$(awk '{d += gsub(/\{/,"{"); d -= gsub(/\}/,"}")} END{print d}' "$tmp")"
    [[ $bal == 0 ]] || { rm -f "$tmp"; die "edit unbalanced the file for $nm - nothing written"; }

    mv "$tmp" "$cfg"
    printf '  %-28s set\n' "$nm"
    changed=$((changed + 1))
done

if [[ $mode == dry ]]; then
    log "dry run - nothing written"
elif (( changed )); then
    log "$changed game(s) updated - start Steam and check Properties > Launch Options"
else
    log "nothing to do"
fi
