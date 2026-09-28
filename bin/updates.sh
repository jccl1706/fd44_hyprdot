#!/usr/bin/env bash
# =========================================================================
# updates.sh - are there packages waiting, and the terminal that installs them
# =========================================================================
#
# Usage:  bin/updates.sh check     what is pending, as JSON on stdout
#         bin/updates.sh open      a terminal that performs the update
#         bin/updates.sh run       the update itself (what `open` runs inside)
#
# The bar's update icon (quickshell/Updates.qml) calls `check` on a timer and
# `open` when clicked. Everything distro-specific lives here rather than in
# QML, so the shell asks one question and gets one answer on both machines.
#
# WHAT "PENDING" MEANS IS NOT THE SAME ON BOTH, and pretending otherwise
# would make the icon lie on one of them:
#
#   Fedora   dnf has a real list of newer packages. The count is that list.
#
#   NixOS    nothing is "pending" in that sense - the system is whatever the
#            flake evaluates to. What can be behind is the nixpkgs revision
#            pinned in flake.lock, so the question asked is whether upstream
#            has moved past the pin, and the count is how many days behind it
#            is. One network call, no evaluation and no building: this runs on
#            a timer and must not pull down store paths to answer.
#
# METADATA IS REFRESHED ON EVERY CHECK, which matters more than it sounds. A
# `dnf upgrade` run against a cache from earlier in the day silently skips a
# package built since - watched exactly that happen with quickshell, where
# root's cache was 13 minutes older than the build and the upgrade left it
# behind without a word. An icon fed by a stale cache would be worse: it would
# say "nothing to do" while something waited.
#
# EXIT CODES: 0 always for `check`, even offline - the JSON carries the error
# and a count of -1, which the bar reads as "unknown" and draws as nothing.
# An icon that appears because the network dropped is a false alarm.

set -uo pipefail

# Piped in (`ssh host bash -s`) there is no BASH_SOURCE and dirname of an
# empty string is ".", so this falls back to where the repo lives rather than
# to whatever directory the caller happened to be in.
src="${BASH_SOURCE[0]:-}"
if [[ -n $src && -e $src ]]; then
    self="$(cd "$(dirname "$src")" && pwd)"
else
    self="${FD44_HYPRDOT_DIR:-$HOME/Work/fd44_hyprdot}/bin"
fi

die() { printf '\033[1;31mupdates:\033[0m %s\n' "$*" >&2; exit 1; }

distro() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
        like="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}")"
    fi
    if [[ $id == nixos ]]; then echo nixos
    elif [[ $id == fedora || " $like " == *" fedora "* ]]; then echo fedora
    else echo "$id"
    fi
}

# The NixOS flake this machine is built from. Overridable for a checkout
# somewhere else; the default is where both machines keep it.
nixos_dir() { printf '%s' "${FD44_NIXOS_DIR:-$HOME/Work/fd44_nixos}"; }

# JSON, assembled by hand because the fields are three strings and a number
# and neither machine is guaranteed to have jq.
emit() { # kind count summary error
    printf '{"kind":"%s","count":%s,"summary":"%s","error":"%s","checked":%s}\n' \
        "$1" "$2" "${3//\"/\'}" "${4//\"/\'}" "$(date +%s)"
}

# --- Fedora ---------------------------------------------------------------

check_fedora() {
    local out rc names count
    # --refresh: see the note at the top. -q so the progress bars stay out of
    # the output being counted.
    out="$(dnf -q --refresh check-update 2>/dev/null)"; rc=$?
    # 100 is dnf's "there are updates", 0 is "none", anything else is a
    # failure - no network, a broken repo - and must not read as zero.
    if (( rc != 100 && rc != 0 )); then
        emit dnf -1 "" "dnf check-update failed (exit $rc)"
        return 0
    fi
    # Three fields is a package line: name.arch, version, repo. Counting
    # stops at the "Obsoleting Packages" heading, because what follows it is
    # the same transaction described a second way - the obsoleting package is
    # already up in the list, and counting both made four updates read as
    # five.
    local pkgs
    pkgs="$(awk '/^Obsoleting/ {exit} NF==3 && $1 ~ /\./ {sub(/\..*/, "", $1); print $1}' <<<"$out")"
    count="$(grep -c . <<<"$pkgs")"
    (( count == 0 )) && pkgs=""
    # paste -sd', ' would alternate the two characters as separators, one per
    # join, and write "a,b c" - the delimiter is a LIST. One character, then
    # the space added after.
    names="$(head -3 <<<"$pkgs" | paste -sd, - | sed 's/,/, /g')"
    (( count > 3 )) && names="$names and $((count - 3)) more"
    emit dnf "$count" "$names" ""
}

run_fedora() {
    printf '\033[1;32m==>\033[0m %s\n\n' "Fedora packages"
    # NOT -y. The list is worth a look before it is applied, and the password
    # prompt is already a stop - one more keypress costs nothing.
    sudo dnf --refresh upgrade
}

# --- NixOS ----------------------------------------------------------------

# Read a JSON file with nix and print the fields an expression selects. `j` is
# the parsed document; the expression must evaluate to a string, which is read
# back as whitespace-separated fields.
nix_json() { # file expr
    nix eval --raw --impure --expr \
        "let j = builtins.fromJSON (builtins.readFile \"$1\"); in $2" 2>/dev/null
}

# The locked nixpkgs and what upstream's tip of the same branch is now.
check_nixos() {
    local dir lock locked_rev locked_when owner repo ref upstream up_rev up_when days tmp
    dir="$(nixos_dir)"
    tmp="$(mktemp)" || { emit nix -1 "" "no temp file"; return 0; }
    trap 'rm -f "$tmp"' RETURN
    lock="$dir/flake.lock"
    [[ -r $lock ]] || { emit nix -1 "" "no flake.lock at $lock"; return 0; }

    # PARSED WITH NIX, NOT PYTHON. There is no python3 on the NixOS desktop
    # at all - bin/qs-restart.sh learned the same thing the hard way - and
    # nix is the one interpreter a NixOS machine is guaranteed to have.
    # builtins.fromJSON is exactly the parser needed and costs nothing.
    read -r locked_rev locked_when owner repo ref < <(nix_json "$lock" '
        let n = j.nodes.nixpkgs; l = n.locked; o = n.original or {}; in
        "${builtins.substring 0 7 (l.rev or "-")} ${toString (l.lastModified or 0)}"
        + " ${o.owner or "NixOS"} ${o.repo or "nixpkgs"} ${o.ref or "nixos-unstable"}"
    ')
    # `read` RETURNS NON-ZERO HERE EVEN WHEN IT WORKED: nix eval --raw prints
    # no trailing newline, so read hits EOF, assigns every variable and still
    # reports failure. Testing the value is the honest check; testing read's
    # exit status reported "could not read flake.lock" for a file it had just
    # read correctly.
    [[ -n $locked_rev && $locked_rev != "-" ]] \
        || { emit nix -1 "" "no nixpkgs node in $lock"; return 0; }

    # --refresh so the answer is today's tip and not a cached one; --json
    # because the human format is not parseable. No evaluation happens here.
    upstream="$(nix flake metadata --refresh --json "github:$owner/$repo/$ref" 2>/dev/null)"
    [[ -n $upstream ]] || { emit nix -1 "" "could not reach github:$owner/$repo/$ref"; return 0; }

    printf '%s' "$upstream" > "$tmp"
    read -r up_rev up_when < <(nix_json "$tmp" '
        let rev = j.revision or (j.locked.rev or "-");
            when = j.lastModified or (j.locked.lastModified or 0); in
        "${builtins.substring 0 7 rev} ${toString when}"
    ')
    [[ -n $up_rev && $up_rev != "-" ]] \
        || { emit nix -1 "" "could not read flake metadata"; return 0; }

    if [[ $up_rev == "$locked_rev" ]]; then
        emit nix 0 "nixpkgs $locked_rev is current" ""
        return 0
    fi
    days=$(( (up_when - locked_when) / 86400 ))
    (( days < 1 )) && days=1
    emit nix "$days" "nixpkgs $days day$( (( days == 1 )) || echo s ) behind ($locked_rev -> $up_rev)" ""
}

run_nixos() {
    local dir host
    dir="$(nixos_dir)"
    host="$(hostname)"
    [[ -d $dir ]] || die "no NixOS flake at $dir"
    printf '\033[1;32m==>\033[0m %s\n\n' "nixpkgs update for $host"
    cd "$dir" || die "cannot enter $dir"
    # Two steps, shown separately: the lock file moving is a change worth
    # seeing on its own, and it is the thing to revert if the rebuild breaks.
    nix flake update || die "nix flake update failed"
    git --no-pager diff --stat flake.lock
    printf '\n'
    sudo nixos-rebuild switch --flake ".#$host"
}

# --- the terminal ---------------------------------------------------------

open_terminal() {
    local term
    # kitty is the terminal on both machines; the others are there so this
    # still works on a machine that has something else.
    for term in kitty alacritty foot xterm; do
        command -v "$term" >/dev/null 2>&1 && break
        term=""
    done
    [[ -n $term ]] || die "no terminal found (tried kitty, alacritty, foot, xterm)"
    # The window stays open after the update so its output can be read - a
    # terminal that vanishes on success tells you nothing about what it did.
    exec "$term" --title "System update" -e bash -c \
        "'$self/updates.sh' run; printf '\n\033[1;32m==>\033[0m %s' 'done - press enter to close'; read -r"
}

# --- entry point ----------------------------------------------------------

case "${1:-check}" in
    check)
        case "$(distro)" in
            fedora) check_fedora ;;
            nixos)  check_nixos ;;
            *)      emit unknown -1 "" "unsupported distro: $(distro)" ;;
        esac
        ;;
    run)
        case "$(distro)" in
            fedora) run_fedora ;;
            nixos)  run_nixos ;;
            *)      die "unsupported distro: $(distro)" ;;
        esac
        ;;
    open) open_terminal ;;
    -h|--help|help)
        sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        ;;
    *) die "unknown command: $1 (check, open, run)" ;;
esac
