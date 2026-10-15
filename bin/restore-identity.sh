#!/usr/bin/env bash
# =========================================================================
# restore-identity.sh - put the irreplaceable half of a home back
# =========================================================================
#
# Usage:  bin/restore-identity.sh stage     restore into ~/restore, change nothing
#         bin/restore-identity.sh install   move the staged copy into place
#
# The keys, the tokens, the shell and the Claude state - everything that is not
# a checkout, a cache or a file the marketplace will hand back. Chromium,
# Pictures and the repositories are deliberately not here: they are large, and
# the first two are the only ones that cannot be fetched again.
#
# TWO STEPS ON PURPOSE. `restic restore --target /` writes straight over a live
# home, and the first thing it would overwrite is ~/.ssh - including the
# authorized_keys written an hour ago to let another machine in. Staging first
# means looking at what came back before any of it counts.
#
# THE PASSWORD IS TYPED BY THE PERSON RUNNING THIS, every time. It is never an
# argument, never an environment variable this script sets, and never written
# down: the repository password IS the backup.

set -euo pipefail

name="${0##*/}"
die()  { printf '%s: %s\n' "$name" "$*" >&2; exit 1; }
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

stage_dir="$HOME/restore"
me="$(id -un)"

paths=(
    "$HOME/.ssh"
    "$HOME/.config/gh"
    "$HOME/.claude"
    "$HOME/.claude.json"
    "$HOME/.bashrc"
    "$HOME/.bashrc.d"
    "$HOME/.bash_profile"
    "$HOME/.gitconfig"
)

[[ $EUID -ne 0 ]] || die "do not run this as root - these files belong to $me"
command -v restic >/dev/null || die "restic is not installed"
# FIND THE REPOSITORY RATHER THAN BE TOLD IT. The backup disk mounts under a
# name udisks chooses - the label on one machine, the UUID on another - so the
# path is not something worth remembering or typing. Anything already exported
# wins; otherwise look where a mounted disk would put it.
if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    for candidate in /run/media/"$me"/*/fd44-backup /media/"$me"/*/fd44-backup \
                     /run/media/"$me"/*/*/fd44-backup; do
        [[ -d $candidate ]] || continue
        export RESTIC_REPOSITORY="$candidate"
        say "found the repository at $candidate"
        break
    done
fi
if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    printf '%s: no backup repository found.\n' "$name" >&2
    printf '  The disk is probably not mounted. At the machine itself:\n' >&2
    printf '    udisksctl mount -b /dev/sda1\n' >&2
    printf '  or click it in the file manager. Over ssh this fails: polkit has\n' >&2
    printf '  no seat session to ask.\n' >&2
    printf '  Then re-run, or set RESTIC_REPOSITORY by hand.\n' >&2
    exit 1
fi

case "${1:-}" in
stage)
    local_args=()
    for p in "${paths[@]}"; do local_args+=(--include "$p"); done
    say "restoring into $stage_dir - nothing in your home is touched"
    printf '  you will be asked for the repository password\n\n'
    mkdir -p "$stage_dir"
    restic restore latest --target "$stage_dir" "${local_args[@]}"
    printf '\n'
    say "what came back"
    for p in "${paths[@]}"; do
        if [[ -e "$stage_dir$p" ]]; then
            printf '  %-28s %s\n' "${p#$HOME/}" "$(du -sh "$stage_dir$p" 2>/dev/null | cut -f1)"
        else
            printf '  %-28s \033[1;33mNOT IN THE SNAPSHOT\033[0m\n' "${p#$HOME/}"
        fi
    done
    printf '\n  Look at it, then:  %s install\n' "$name"
    ;;

install)
    [[ -d $stage_dir ]] || die "nothing staged - run: $name stage"

    # THE KEY THAT LETS THIS MACHINE BE REACHED IS NOT THE BACKUP'S TO DECIDE.
    # A restored authorized_keys is whatever was authorised on the old install,
    # which may not include the machine being used to run this. Both lists are
    # kept, de-duplicated, so a restore can only ever add access.
    live_auth="$HOME/.ssh/authorized_keys"
    staged_auth="$stage_dir$HOME/.ssh/authorized_keys"
    merged=""
    if [[ -f $live_auth || -f $staged_auth ]]; then
        merged="$(mktemp)"
        cat "$live_auth" "$staged_auth" 2>/dev/null | grep -vE '^\s*(#|$)' | sort -u > "$merged"
    fi

    for p in "${paths[@]}"; do
        src="$stage_dir$p"
        [[ -e $src ]] || { warn "skipping $p - not staged"; continue; }
        if [[ -e $p ]]; then
            cp -a "$p" "$p.before-restore" 2>/dev/null || true
        fi
        rm -rf "$p"
        cp -a "$src" "$p"
        say "restored ${p#$HOME/}"
    done

    if [[ -n $merged ]]; then
        cp "$merged" "$live_auth"
        rm -f "$merged"
        chmod 600 "$live_auth"
        say "authorized_keys: both lists kept, $(wc -l < "$live_auth") keys"
    fi

    chmod 700 "$HOME/.ssh" 2>/dev/null || true
    chmod go-w "$HOME" 2>/dev/null || true
    find "$HOME/.ssh" -type f ! -name '*.pub' ! -name 'known_hosts*' \
         -exec chmod 600 {} \; 2>/dev/null || true

    # restic carries extended attributes, but a label that was right on the old
    # install is not automatically right here. sshd is the one that cares.
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -R "$HOME/.ssh" "$HOME/.config" 2>/dev/null || true
        say "selinux labels restored"
    fi

    printf '\n'
    say "done - the previous versions are beside them as *.before-restore"
    printf '  Check ssh still works from the other machine BEFORE deleting those.\n'
    ;;
*)
    die "usage: $name [stage|install]"
    ;;
esac
