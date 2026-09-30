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
#   Gentoo   `emerge -p @world` has a real list, but asking costs SECONDS -
#            it resolves the whole dependency graph and talks to the binhost -
#            so it cannot run on the bar's timer. The answer is cached and the
#            check is done in the background; see check_gentoo.
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
# The pending list, normalised for the screen below:
#   name <TAB> installed <TAB> available <TAB> tag
#
# ONE rpm CALL, NOT ONE PER PACKAGE. The installed version has to come from rpm
# because dnf's check-update prints only what is AVAILABLE, and "1.2 -> 1.3" is
# the sentence anyone actually wants to read. Asking rpm per package was fine
# for a preview of four and is 193 forks on a morning like this one, so the whole
# database is read once into an awk map instead.
#
# %{EVR}, not version-release: it carries the epoch when there is one, which is
# how dnf prints it - without it vim read as "9.2.1129-1.fc44 -> 2:9.2.1129-1.fc44",
# an upgrade to itself.
#
# Counting stops at "Obsoleting Packages", because what follows is the same
# transaction described a second way - the obsoleting package is already in the
# list above, and counting both made four updates read as five.
list_fedora() {
    local out installed
    out="$(dnf -q --refresh check-update 2>/dev/null)"
    installed="$(rpm -qa --qf '%{NAME}=%{EVR}\n' 2>/dev/null)"
    awk -v inst="$installed" '
        BEGIN {
            n = split(inst, rows, "\n")
            for (i = 1; i <= n; i++) {
                p = index(rows[i], "=")
                if (p) cur[substr(rows[i], 1, p - 1)] = substr(rows[i], p + 1)
            }
        }
        /^Obsoleting/ { exit }
        NF == 3 && $1 ~ /\./ {
            name = $1; sub(/\.[^.]*$/, "", name)
            printf "%s\t%s\t%s\t-\n", name, (name in cur ? cur[name] : "-"), $2
        }
    ' <<<"$out"
}

# NOT -y, even though the list has already been read on screen: dnf's own table
# is the authoritative one - it knows about dependencies and obsoletes that a
# list of upgradable packages does not - and its y/N is the last chance to stop
# once those are visible too.
upgrade_fedora() { sudo dnf --refresh upgrade; }
upgrade_cmd_fedora() { printf 'sudo dnf upgrade --refresh'; }

# --- Gentoo ---------------------------------------------------------------

# WHY THIS ONE IS CACHED AND THE OTHERS ARE NOT. `dnf check-update` answers in
# under a second and the NixOS check is one HTTP request. `emerge -puDN @world`
# resolves the entire dependency graph and asks the binhost about every package
# in it: measured at tens of seconds on this machine. The bar asks every few
# minutes, so asking directly would mean a portage process running most of the
# time, and a click arriving mid-resolve would wait.
#
# So `check` answers from a file and refreshes behind itself. The first check
# after a boot reports -1, which the bar reads as "unknown" and draws as
# nothing - an icon that appears only once there is a real number is the same
# behaviour as being offline on the other machines.
gentoo_cache() { printf '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/fd44-hyprdot/updates-gentoo.json"; }

# An hour. Long enough that the check is not constantly running, short enough
# that a tree synced while the machine was up is noticed the same morning.
GENTOO_MAX_AGE=3600

# WHEN THE TREE ITSELF LAST MOVED. emerge-sync.timer runs daily, and the moment
# it finishes every cached answer is potentially wrong - so a tree newer than
# the cache is stale regardless of age. This is the file portage itself writes.
repo_synced() { stat -c %Y /var/db/repos/gentoo/metadata/timestamp.chk 2>/dev/null || echo 0; }

# The pending list, one package per line:  name<TAB>old<TAB>new<TAB>binary|source
#
# FLAGS DECIDE WHAT COUNTS. U is an upgrade, D a downgrade and N a new
# dependency; R is a rebuild - same version, changed USE flags or a revdep - and
# is deliberately NOT counted. A bar that lit up for rebuilds would be lit
# permanently on a source distribution, which is the same as being off.
#
# The version is split at the FIRST hyphen followed by a digit, which is where
# Gentoo says a package name ends: a name may contain hyphens, but never one
# followed by a digit.
gentoo_pending() {
    emerge -puDN --with-bdeps=y --getbinpkg --color=n --quiet --nospinner @world 2>/dev/null |
    awk '
        /^\[(binary|ebuild)/ {
            close_i = index($0, "]")
            hdr  = substr($0, 1, close_i)
            rest = substr($0, close_i + 1)
            if (hdr !~ /[UDN]/) next                    # R and friends are not news
            kind = (hdr ~ /binary/) ? "binary" : "source"
            split(rest, f, " ")
            atom = f[1]
            sub(/::.*$/, "", atom)
            name = atom; ver = ""
            if (match(atom, /-[0-9]/)) {
                name = substr(atom, 1, RSTART - 1)
                ver  = substr(atom, RSTART + 1)
                sub(/:.*$/, "", ver)                    # a SLOT is not part of the version
            }
            old = ""
            if (match(rest, /\[[^]]*\]/)) {             # [259.8::gentoo] - what is installed
                old = substr(rest, RSTART + 1, RLENGTH - 2)
                sub(/::.*$/, "", old)
                sub(/ .*$/, "", old)
            }
            # "-" RATHER THAN EMPTY for a package with no installed version. TAB
            # is IFS whitespace, so `read -r a b c d` collapses two tabs into one
            # delimiter and every field after the gap shifts left - which printed
            # new packages as "libfoo 1.2.3 -> source".
            if (old == "") old = "-"
            printf "%s\t%s\t%s\t%s\n", name, old, ver, kind
        }
    '
}

# Run the real check and write the cache. Called in the background by `check`,
# and directly by `bin/updates.sh gentoo-refresh`.
refresh_gentoo() {
    local list count names cache dir
    cache="$(gentoo_cache)"; dir="$(dirname "$cache")"
    mkdir -p "$dir"
    list="$(gentoo_pending)"
    count="$(grep -c . <<<"$list")"
    [[ -z $list ]] && count=0
    # First three names, then "and N more" - the same sentence as Fedora's.
    names="$(cut -f1 <<<"$list" | head -3 | paste -sd, - | sed 's/,/, /g')"
    (( count > 3 )) && names="$names and $((count - 3)) more"
    (( count == 0 )) && names=""
    # Atomically, so a check reading the file never sees half of it.
    emit emerge "$count" "$names" "" > "$cache.new" && mv -f "$cache.new" "$cache"
    # The list beside it, for `preview` - regenerating it there would mean
    # waiting through the whole resolve again at the moment of the click.
    printf '%s\n' "$list" > "$dir/updates-gentoo.list"
}

check_gentoo() {
    local cache age now stale=0
    cache="$(gentoo_cache)"
    now="$(date +%s)"
    if [[ -r $cache ]]; then
        age=$(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        (( age > GENTOO_MAX_AGE )) && stale=1
        # A tree synced since the cache was written invalidates it whatever its age.
        (( $(repo_synced) > $(stat -c %Y "$cache" 2>/dev/null || echo 0) )) && stale=1
        cat "$cache"
    else
        stale=1
        emit emerge -1 "" "first check has not finished yet"
    fi
    if (( stale )) && ! pgrep -f "updates\.sh gentoo-refresh" >/dev/null 2>&1; then
        # setsid, so it survives the shell quickshell spawned this in.
        setsid "$self/updates.sh" gentoo-refresh >/dev/null 2>&1 &
    fi
    return 0
}

# The pending list for the screen below, from the cache the check already wrote.
# Resolving again at the moment of a click would mean staring at nothing for the
# eleven seconds portage takes.
list_gentoo() {
    local list
    list="$(dirname "$(gentoo_cache)")/updates-gentoo.list"
    if [[ -r $list && -s $list ]]; then
        cat "$list"
    else
        gentoo_pending
    fi
}

# --ask for the same reason Fedora's is not -y: portage's own table knows about
# blockers, slot conflicts and USE changes that a list of upgradable packages
# does not. --keep-going because one package failing to build on a source system
# should not abandon the other forty that would have succeeded.
upgrade_gentoo() {
    sudo emerge -avuDN --with-bdeps=y --getbinpkg --keep-going @world
    refresh_gentoo            # the cache now describes a system that is gone
}
upgrade_cmd_gentoo() { printf 'sudo emerge -avuDN --getbinpkg @world'; }

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

# --- the pending-upgrades screen ------------------------------------------
#
# WHAT THIS REPLACED, AND WHY. The first version printed the list and handed
# straight over to the package manager. That is fine for four packages and wrong
# for 193: the list scrolls off, the only choice offered is "now or never", and
# re-checking meant closing the window and clicking the bar again. This is the
# same information as a SCREEN - it stays up, it says how old it is, and the
# three things anyone actually does next are one key each.
#
# ONE SCREEN, BOTH DISTRIBUTIONS. Everything above reduces a distribution to the
# same four columns, so this draws Fedora and Gentoo identically and the only
# visible difference is Gentoo's bin/src mark, which exists because on a source
# distribution it is the difference between a minute and an hour.
#
# COLOURS ARE ANSI INDICES ONLY, never hex: the terminal's own palette draws it,
# so it follows bin/theme.sh between dark and cream with nothing to regenerate -
# the same rule as starship/starship.toml.

# nf-md-package_variant_closed, the glyph on the bar's own button - so the window
# a click opens is recognisably the thing that was clicked.
UPD_GLYPH="$(printf '\U000F03D7')"
UPD_ARROW="$(printf '\u2192')"

rel_time() { # epoch -> "just now" / "7 min ago" / "3 h ago"
    local d=$(( $(date +%s) - ${1:-0} ))
    if   (( d < 90   )); then printf 'just now'
    elif (( d < 5400 )); then printf '%d min ago' $(( (d + 30) / 60 ))
    else                      printf '%d h ago'   $(( (d + 1800) / 3600 ))
    fi
}

list_for()        { case "$(distro)" in fedora) list_fedora ;; gentoo) list_gentoo ;; esac; }
upgrade_for()     { case "$(distro)" in fedora) upgrade_fedora ;; gentoo) upgrade_gentoo ;; esac; }
upgrade_cmd_for() { case "$(distro)" in fedora) upgrade_cmd_fedora ;; gentoo) upgrade_cmd_gentoo ;; esac; }

# The list, and when it was taken. Gentoo answers from a cache, so "checked N min
# ago" is the cache's age there and the moment of asking on Fedora - saying "just
# now" over an hour-old answer would be the one lie this screen could tell.
upd_when=0
upd_fill() { # file
    list_for > "$1.new" 2>/dev/null && mv -f "$1.new" "$1"
    if [[ $(distro) == gentoo ]]; then
        local cached; cached="$(dirname "$(gentoo_cache)")/updates-gentoo.list"
        upd_when="$(stat -c %Y "$cached" 2>/dev/null || date +%s)"
    else
        upd_when="$(date +%s)"
    fi
}

# COLUMN WIDTHS COME FROM THE DATA, not from a number picked here. Versions vary
# wildly - "7.1-1.fc44" beside "2025.2.80_v9.0.304-6.fc44" - and a fixed width
# either wastes half the screen or silently cuts the end off a version, which on
# a screen whose whole job is "what am I about to install" is the worst of the
# two. The new version is never padded or cut at all; it is the last thing on the
# line and has nowhere to overflow into.
upd_row() { # name old new tag namew oldw
    local tag=""
    # Only Gentoo sets one; on Fedora every package arrives built.
    case "$4" in
        binary) tag="$(printf ' \033[2mbin\033[0m')" ;;
        source) tag="$(printf ' \033[1;33msrc\033[0m')" ;;
    esac
    printf '  \033[1m%-*s\033[0m \033[2m%*s\033[0m \033[1;32m%s\033[0m \033[32m%s\033[0m%s\n' \
        "$5" "$1" "$6" "$2" "$UPD_ARROW" "$3" "$tag"
}

upd_draw() { # file
    local total rows cols shown=0 name old new tag
    # grep -c PRINTS 0 and EXITS 1 when nothing matches, so `|| echo 0` appended
    # a second zero and every (( )) below saw "0\n0" - an arithmetic syntax error
    # on an empty list, which is the one case that has to be calm.
    total="$(grep -c . "$1" 2>/dev/null)" || true
    total="${total:-0}"
    cols="$(tput cols 2>/dev/null || echo 80)"
    # Everything that is not the list: three header lines, the rule, two key
    # lines and the breathing room around them.
    rows=$(( $(tput lines 2>/dev/null || echo 24) - 9 ))
    (( rows < 3 )) && rows=3

    printf '\033[2J\033[H\n'
    if (( total == 0 )); then
        printf '  \033[1;34m%s  %s\033[0m  \033[2mchecked %s\033[0m\n\n' \
            "$UPD_GLYPH" "Nothing pending" "$(rel_time "$upd_when")"
        printf '  \033[2m%s\033[0m\n\n' "everything installed is the newest this machine knows about"
    else
        printf '  \033[1;34m%s  %s\033[0m  \033[2m%s package(s) · checked %s\033[0m\n\n' \
            "$UPD_GLYPH" "Pending upgrades" "$total" "$(rel_time "$upd_when")"
        # Measured over the rows that will actually be drawn, so one enormous
        # version further down the list cannot stretch the visible ones.
        local namew=0 oldw=0 i=0
        while IFS=$'\t' read -r name old new tag; do
            [[ -n $name ]] || continue
            (( i >= rows )) && break
            [[ $old == - ]] && old="new"
            (( ${#name} > namew )) && namew=${#name}
            (( ${#old}  > oldw  )) && oldw=${#old}
            i=$(( i + 1 ))
        done < "$1"
        while IFS=$'\t' read -r name old new tag; do
            [[ -n $name ]] || continue
            (( shown >= rows )) && break
            [[ $old == - ]] && old="new"
            upd_row "$name" "$old" "$new" "$tag" "$namew" "$oldw"
            shown=$(( shown + 1 ))
        done < "$1"
        (( total > shown )) && printf '  \033[2m%s and %d more - press l for the full list\033[0m\n' \
            "$(printf '\u2026')" "$(( total - shown ))"
    fi

    printf '\n  \033[2m'; printf '%.0s\u2500' $(seq 1 $(( cols > 76 ? 72 : cols - 6 ))); printf '\033[0m\n\n'
    if (( total > 0 )); then
        printf '  \033[1;32mu\033[0m upgrade now  \033[2m(%s)\033[0m\n' "$(upgrade_cmd_for)"
        printf '  \033[1;32ml\033[0m full list    \033[1;32mr\033[0m check again    \033[1;32mq\033[0m / \033[1;32mEsc\033[0m close\n'
    else
        printf '  \033[1;32mr\033[0m check again    \033[1;32mq\033[0m / \033[1;32mEsc\033[0m close\n'
    fi
}

upd_full() { # file - every row, through a pager so it can be scrolled back
    local name old new tag pager
    pager="${PAGER:-less}"
    command -v "${pager%% *}" >/dev/null 2>&1 || pager=cat
    {
        printf '\n  \033[1;34m%s  %s\033[0m\n\n' "$UPD_GLYPH" "Pending upgrades, all of them"
        local namew=0 oldw=0
        while IFS=$'\t' read -r name old new tag; do
            [[ -n $name ]] || continue
            [[ $old == - ]] && old="new"
            (( ${#name} > namew )) && namew=${#name}
            (( ${#old}  > oldw  )) && oldw=${#old}
        done < "$1"
        while IFS=$'\t' read -r name old new tag; do
            [[ -n $name ]] || continue
            [[ $old == - ]] && old="new"
            upd_row "$name" "$old" "$new" "$tag" "$namew" "$oldw"
        done < "$1"
        printf '\n'
    # -R and -X BELONG TO less, so they cannot be handed to whatever $PAGER
    # happens to be: `cat -R -X` is an invalid option and the list vanished
    # silently, which is how this was found. They go in $LESS instead, which any
    # other pager ignores, and a $PAGER that is not installed falls back to cat
    # rather than dropping the output on the floor.
    #   -R  keep the colours   -X  leave the list on screen after quitting
    } | LESS="-R -X" $pager
}

# upd_file is NOT local: the EXIT trap runs after this function has returned, by
# which time a local would be out of scope - and with `set -u` that is an
# "unbound variable" error as the screen closes.
upd_file=""
run_tui() {
    local key
    upd_file="$(mktemp -t fd44-updates.XXXXXX)"
    # The file is this process's; remove it however the screen is left.
    trap 'rm -f "$upd_file" "$upd_file.new"; printf "\033[?25h"' EXIT INT TERM

    printf '\033[2J\033[H\n  \033[2m%s\033[0m\n' "asking $(distro) what is pending..."
    upd_fill "$upd_file"

    while :; do
        printf '\033[?25l'                       # the cursor is noise on a screen of text
        upd_draw "$upd_file"
        printf '\033[?25h'
        IFS= read -rsn1 key || break
        case "$key" in
            u|U)
                printf '\033[2J\033[H\n'
                upgrade_for
                printf '\n  \033[2m%s\033[0m ' "done - any key for the list again"
                IFS= read -rsn1
                upd_fill "$upd_file"
                ;;
            l|L) upd_full "$upd_file" ;;
            r|R)
                printf '\n  \033[2m%s\033[0m\n' "checking..."
                upd_fill "$upd_file"
                ;;
            q|Q|$'\e') break ;;
        esac
    done
    printf '\033[?25h\n'
}

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
            gentoo) check_gentoo ;;
            *)      emit unknown -1 "" "unsupported distro: $(distro)" ;;
        esac
        ;;
    run)
        case "$(distro)" in
            fedora) run_tui ;;
            nixos)  run_nixos ;;
            gentoo) run_tui ;;
            *)      die "unsupported distro: $(distro)" ;;
        esac
        ;;
    open) open_terminal ;;
    # The background worker `check` spawns on Gentoo. Not documented in --help:
    # it is an implementation detail of the cache, not something to run by hand.
    gentoo-refresh) refresh_gentoo ;;
    -h|--help|help)
        sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        ;;
    *) die "unknown command: $1 (check, open, run)" ;;
esac
