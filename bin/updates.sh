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

# WHAT IS ABOUT TO CHANGE, BEFORE ANYTHING ASKS FOR ROOT. dnf prints its own
# transaction table and waits for a y/N, but only AFTER sudo has taken the
# password - so the first thing on screen is a password prompt for a list you
# have not seen yet. This runs first, needs no privileges, and shows the
# version you have beside the version you would get.
preview_fedora() {
    local out pkg ver repo name cur n=0
    out="$(dnf -q --refresh check-update 2>/dev/null)"
    while read -r pkg ver repo; do
        [[ -n $pkg ]] || continue
        name="${pkg%.*}"
        # The installed version, asked of rpm rather than of dnf: dnf's
        # check-update prints only what is available, and "1.2 -> 1.3" is the
        # sentence anyone actually wants to read.
        # %{EVR}, not version-release: it carries the epoch when there is
        # one, which is how dnf prints it - without it vim read as
        # "9.2.1129-1.fc44 -> 2:9.2.1129-1.fc44", an upgrade to itself.
        cur="$(rpm -q --qf '%{EVR}' "$name" 2>/dev/null)"
        printf '  %-32s %-24s \033[1;32m->\033[0m %s\n' "$name" "${cur:-not installed}" "$ver"
        n=$(( n + 1 ))
    done < <(awk '/^Obsoleting/ {exit} NF==3 && $1 ~ /\./ {print $1, $2, $3}' <<<"$out")
    printf '\n'
    return "$(( n > 0 ? 0 : 1 ))"
}

run_fedora() {
    printf '\033[1;32m==>\033[0m %s\n\n' "Packages waiting"
    if ! preview_fedora; then
        printf '  %s\n\n' "nothing to update"
        return 0
    fi
    printf '\033[1;32m==>\033[0m %s\n\n' "Installing them"
    # NOT -y, even though the list above has already been read: dnf's own
    # table is the authoritative one - it knows about dependencies and
    # obsoletes that a list of updatable packages does not - and its y/N is
    # the last chance to stop once those are visible too.
    sudo dnf --refresh upgrade
}

# --- NixOS ----------------------------------------------------------------

# The nixpkgs revision flake.lock currently pins, short.
locked_rev_of() { # flake.lock
    nix_json "$1" 'builtins.substring 0 7 (j.nodes.nixpkgs.locked.rev or "-")'
}

# COMMIT AND PUSH THE LOCK, BUT ONLY ONCE THE SYSTEM IS RUNNING IT. The lock
# file is the record of what this machine is built from, and a lock that has
# moved on disk while the repository still says otherwise is a machine nobody
# can rebuild from the repository - `git checkout flake.lock` would quietly
# put the old pin back and the next rebuild would undo the update.
#
# After the switch, because that is the point at which the new pin is known to
# work. A lock committed before it is activated could be a build that fails.
#
# ONLY flake.lock, by pathspec: whatever else is being worked on in that
# checkout is not this script's business and must not end up in the commit.
#
# Failing to push is reported and not fatal - the commit is made either way,
# and the update itself already succeeded. Set FD44_UPDATES_NO_PUSH=1 to
# commit without pushing.
record_lock() { # dir before after
    local dir="$1" before="$2" after="$3"
    git -C "$dir" diff --quiet -- flake.lock && {
        printf '\033[1;32m==>\033[0m %s\n' "flake.lock unchanged - nothing to record"
        return 0
    }
    printf '\n\033[1;32m==>\033[0m %s\n' "Recording the new pin in the repository"
    git -C "$dir" commit -q -m "nixpkgs: $before -> $after" -- flake.lock || {
        printf '  %s\n' "could not commit flake.lock - left in the working tree"
        return 0
    }
    printf '  %s\n' "committed: $(git -C "$dir" log --oneline -1)"
    if [[ -n ${FD44_UPDATES_NO_PUSH:-} ]]; then
        printf '  %s\n' "not pushing (FD44_UPDATES_NO_PUSH is set)"
        return 0
    fi
    if GIT_TERMINAL_PROMPT=0 git -C "$dir" push -q origin HEAD 2>/dev/null; then
        printf '  %s\n' "pushed to $(git -C "$dir" remote get-url origin)"
    else
        printf '  %s\n' "PUSH FAILED - the commit is local. Retry with:"
        printf '  %s\n' "    git -C $dir push origin HEAD"
    fi
}

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
    local dir host reply out_link before after
    out_link="$(mktemp)"
    trap 'rm -f "$out_link"' RETURN
    dir="$(nixos_dir)"
    host="$(hostname)"
    [[ -d $dir ]] || die "no NixOS flake at $dir"
    printf '\033[1;32m==>\033[0m %s\n\n' "nixpkgs update for $host"
    cd "$dir" || die "cannot enter $dir"
    # Three steps, and the switch is the only one that needs root.
    #
    # BUILD BEFORE ASKING, because on NixOS there is no list of packages to
    # print until the new system has been evaluated - "what is upgrading" is
    # the difference between two closures and nothing can name it in advance.
    # Building as your own user is also what proves the configuration
    # evaluates at all, so a broken flake fails here rather than halfway
    # through an activation.
    before="$(locked_rev_of "$dir/flake.lock")"
    nix flake update || die "nix flake update failed"
    after="$(locked_rev_of "$dir/flake.lock")"
    git --no-pager diff --stat flake.lock
    printf '\n\033[1;32m==>\033[0m %s\n\n' "Building the new system (no root needed)"
    nix build --no-link --print-out-paths ".#nixosConfigurations.$host.config.system.build.toplevel" \
        > "$out_link" || die "the build failed - nothing has been changed"
    local new
    new="$(tail -1 "$out_link")"
    printf '\n\033[1;32m==>\033[0m %s\n\n' "What would change"
    # The package-by-package answer: names, old version -> new version, and
    # the size it costs. This is the NixOS equivalent of dnf's table.
    nix store diff-closures /run/current-system "$new" || true
    printf '\n'
    read -r -p "Activate this system? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) printf '\n%s\n' "left alone - flake.lock has moved but nothing is activated."
           printf '%s\n' "  to undo that:  git -C $dir checkout flake.lock"
           return 0 ;;
    esac
    sudo nixos-rebuild switch --flake ".#$host" || die "the switch failed - flake.lock is left in the working tree, uncommitted"

    record_lock "$dir" "$before" "$after"
}

# --- the terminal ---------------------------------------------------------

open_terminal() {
    # bin/in-terminal.sh owns the window: which terminal, and staying open
    # afterwards so the transcript can be read. bin/backup.sh opens its own
    # the same way.
    exec "$self/in-terminal.sh" "System update" "$self/updates.sh" run
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
