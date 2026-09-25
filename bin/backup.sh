#!/usr/bin/env bash
# =========================================================================
# backup.sh - the copy that is not on this disk
# =========================================================================
#
# Usage:  bin/backup.sh setup        point it at a disk, create the repository
#         bin/backup.sh run          take a snapshot (what the timer runs)
#         bin/backup.sh status       when the last one was, and how big
#         bin/backup.sh snapshots    list them
#         bin/backup.sh check        verify the repository
#         bin/backup.sh verify       restore the latest into a temp dir and diff it
#         bin/backup.sh restore DIR  restore the latest snapshot into DIR
#         bin/backup.sh mount DIR    browse the snapshots as a filesystem
#         bin/backup.sh escrow       what has to be kept OFF this machine
#
# WHAT THIS IS FOR. A snapshot (btrfs-patrol) and a scrub (btrfs-scrub.sh)
# both live on the disk they protect: they answer "I broke it" and "the disk
# is rotting", and neither answers "the disk is gone". This is the third one,
# and until 2026-09-24 this repository had no answer to it at all.
#
# WHAT IT COPIES, and why it is so little. Measured rather than guessed: this
# home directory is 933 MB, of which ~/Work is four git checkouts that are all
# pushed, ~/.local/share/claude is a program that reinstalls itself, and
# Documents, Pictures, Videos, Music and Downloads are empty. What is left is
# about 400 MB, and the part that would really hurt is 80 KB of keys.
#
# RESTIC, AND WHY THE DISK IS NOT ENCRYPTED. restic encrypts the repository
# itself - contents, metadata and filenames - so the disk holding it needs no
# LUKS of its own. That is a deliberate trade: one less passphrase, and a disk
# that can be read on any machine with the repository password.
#
# BY UUID, NEVER BY /dev/sdX. Which letter a USB disk gets depends on what
# else is plugged in and in what order, so the name is not a name. The same
# rule the rest of this repository follows for disks.
#
# THE HARD PART OF A DISK YOU PLUG IN is remembering to plug it in, and this
# cannot fix that. What it can do is refuse to be quiet about it: a run with
# no disk present is not an error - that is a laptop on a train - but once the
# last successful backup is older than STALE_DAYS, the unit FAILS, which puts
# it in `systemctl --failed` where a sweep of the machine looks first.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fd44-backup"
CONFIG="$CONFIG_DIR/config"
PASSWORD_FILE="$CONFIG_DIR/password"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fd44-hyprdot"
LAST_RUN="$STATE_DIR/backup-last"

#: After this many days with no successful backup, `run` fails even when the
#: disk is simply absent. A fortnight is long enough not to nag about a
#: holiday and short enough that "I forgot for three months" cannot happen
#: quietly.
STALE_DAYS=14

#: Where the repository sits on the disk, under its mount point.
REPO_SUBDIR="fd44-backup"

green=$'\033[1;32m'; dim=$'\033[2m'; bold=$'\033[1m'; red=$'\033[1;31m'; reset=$'\033[0m'
note() { printf '%s==>%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$bold" "$reset" "$*" >&2; }
die()  { printf '%sbackup:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

command -v restic >/dev/null 2>&1 || die "restic is not installed (sudo dnf install restic)"

# --- what gets copied ---------------------------------------------------
#
# Listed rather than "everything minus exclusions", because an include list
# fails by missing a file - which `verify` and a restore will show - while an
# exclude list fails by quietly copying a 50 GB cache, and nobody notices
# until the disk is full.
includes() {
    local paths=(
        # The one that cannot be regenerated at all: four private keys, and
        # the config that says which key belongs to which machine.
        "$HOME/.ssh"

        # Tokens that act as this account: gh talks to GitHub, copr uploads
        # builds. Regenerable, but only from a machine that still has them.
        "$HOME/.config/gh"
        "$HOME/.config/copr"

        # Sessions, memory and settings. The largest thing here that is worth
        # having and exists nowhere else.
        "$HOME/.claude"
        "$HOME/.claude.json"

        # Logins, cookies, bookmarks and history. Not secret-recoverable: a
        # password manager would be, and this profile is what stands in for
        # one right now.
        "$HOME/.config/chromium"

        # Shell and identity. Small, and the difference between a machine
        # that feels like yours and one that does not.
        "$HOME/.bashrc"
        "$HOME/.bashrc.d"
        "$HOME/.bash_profile"
        "$HOME/.gitconfig"

        # THE CHECKOUTS, although all four are pushed to GitHub. What is not
        # pushed is whatever was being written when the disk died, and that is
        # exactly the work worth keeping. 56 MB is not worth reasoning about.
        "$HOME/Work"

        # Which theme is current, and the rest of this desktop's own state.
        "$STATE_DIR"
    )
    printf '%s\n' "${paths[@]}"
}

excludes() {
    # Caches inside the trees above. Chromium's are the large ones and are
    # rebuilt on first launch; restic would otherwise copy a few hundred
    # megabytes that mean nothing.
    printf '%s\n' \
        "$HOME/.config/chromium/*/Cache" \
        "$HOME/.config/chromium/*/Code Cache" \
        "$HOME/.config/chromium/*/GPUCache" \
        "$HOME/.config/chromium/*/Service Worker/CacheStorage" \
        "$HOME/.config/chromium/ShaderCache" \
        "$HOME/.config/chromium/GrShaderCache" \
        "$HOME/.claude/**/node_modules" \
        "**/.venv" \
        "**/__pycache__"
}

# --- the disk -----------------------------------------------------------

load_config() {
    [[ -f $CONFIG ]] || die "not set up yet - run: bin/backup.sh setup"
    # shellcheck source=/dev/null
    source "$CONFIG"
    [[ -n ${BACKUP_UUID:-} ]] || die "$CONFIG has no BACKUP_UUID"
    [[ -s $PASSWORD_FILE ]] || die "no repository password at $PASSWORD_FILE"
}

#: Where the disk with that UUID is mounted, or nothing.
mount_point() {
    lsblk -rno UUID,MOUNTPOINT 2>/dev/null |
        awk -v uuid="$BACKUP_UUID" '$1 == uuid && $2 != "" { print $2; exit }' |
        sed 's/\\x20/ /g'
}

disk_present() {
    lsblk -rno UUID 2>/dev/null | grep -qx "$BACKUP_UUID"
}

# Mount through udisks, as the user, so this needs no root and no fstab entry
# for a disk that is usually not here.
ensure_mounted() {
    local where
    where="$(mount_point)"
    [[ -n $where ]] && { echo "$where"; return 0; }
    disk_present || return 1
    local device
    device="$(lsblk -rno UUID,PATH 2>/dev/null | awk -v u="$BACKUP_UUID" '$1==u{print $2; exit}')"
    udisksctl mount -b "$device" >/dev/null 2>&1 || true
    where="$(mount_point)"
    [[ -n $where ]] || return 1
    MOUNTED_BY_US=1
    echo "$where"
}

repo_path() {
    local where="$1"
    echo "$where/$REPO_SUBDIR"
}

restic_env() {
    export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"
    export RESTIC_REPOSITORY="$1"
    # A backup that cannot be read on another machine is not a backup, and a
    # cache left on THIS disk is no loss if this disk is the one that died.
    export RESTIC_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/restic"
}

days_since_last() {
    [[ -f $LAST_RUN ]] || { echo 99999; return; }
    local then now
    then=$(cat "$LAST_RUN" 2>/dev/null || echo 0)
    now=$(date +%s)
    echo $(( (now - then) / 86400 ))
}

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Backup" "$1" "${2-}" ${3:+-u "$3"} 2>/dev/null || true
}

# --- commands -----------------------------------------------------------

cmd_setup() {
    mkdir -p "$CONFIG_DIR" "$STATE_DIR"
    chmod 700 "$CONFIG_DIR"

    # EVERY FILESYSTEM WITH A UUID, which is what the question below asks for.
    # This filtered rows matching /part/ while asking lsblk for columns that do
    # not include TYPE, so nothing matched and the only row printed was the
    # whole-disk one - which has no UUID, so the list answered nothing.
    note "filesystems that could hold the repository"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT,TRAN |
        awk 'NR == 1 || ($4 != "" && $4 != "swap")' | sed 's/^/    /'
    echo
    printf '    %sthis machine boots from %s; anything else is removable%s\n' \
        "$dim" "$(findmnt -no SOURCE / 2>/dev/null || echo unknown)" "$reset"
    echo
    local uuid
    read -rp "UUID of the backup disk: " uuid
    [[ -n $uuid ]] || die "no UUID given"
    lsblk -rno UUID | grep -qx "$uuid" || die "no filesystem with UUID $uuid is attached"

    printf 'BACKUP_UUID=%s\n' "$uuid" > "$CONFIG"
    chmod 600 "$CONFIG"
    note "wrote $CONFIG"

    if [[ ! -s $PASSWORD_FILE ]]; then
        echo
        warn "THE REPOSITORY PASSWORD IS THE BACKUP. Lose it and every snapshot"
        warn "on that disk is unreadable - there is no recovery, by design."
        warn "Write it down somewhere that is not this laptop BEFORE continuing."
        echo
        local p1 p2
        read -rsp "new repository password: " p1; echo
        read -rsp "again: " p2; echo
        [[ -n $p1 ]] || die "an empty password is not a password"
        [[ $p1 == "$p2" ]] || die "they do not match"
        umask 077
        printf '%s' "$p1" > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        unset p1 p2
        note "wrote $PASSWORD_FILE (0600)"
    fi

    load_config
    local where repo
    where="$(ensure_mounted)" || die "could not mount the disk"
    repo="$(repo_path "$where")"
    restic_env "$repo"
    if restic cat config >/dev/null 2>&1; then
        note "repository already exists at $repo"
    else
        mkdir -p "$repo"
        restic init
        note "created the repository at $repo"
    fi
    echo
    cmd_escrow
}

cmd_run() {
    load_config
    local where repo
    if ! where="$(ensure_mounted)"; then
        local age; age="$(days_since_last)"
        if (( age > STALE_DAYS )); then
            notify "Backup disk not connected" "No backup for $age days" critical
            die "the backup disk is not here, and the last backup was $age days ago"
        fi
        note "the backup disk is not connected - nothing to do (last backup ${age}d ago)"
        return 0
    fi
    repo="$(repo_path "$where")"
    restic_env "$repo"

    local args=(backup --tag fd44 --exclude-caches)
    local path
    while IFS= read -r path; do [[ -e $path ]] && args+=("$path"); done < <(includes)
    while IFS= read -r path; do args+=(--exclude "$path"); done < <(excludes)
    [[ ${1-} == --dry-run ]] && args+=(--dry-run --verbose)

    note "backing up to $repo"
    if restic "${args[@]}"; then
        [[ ${1-} == --dry-run ]] || date +%s > "$LAST_RUN"
        # KEEP A YEAR, THINNING OUT. Daily for a week catches "I deleted it
        # yesterday"; monthly for a year catches "that file existed in March".
        [[ ${1-} == --dry-run ]] || restic forget --tag fd44 \
            --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
        notify "Backup complete" "$(restic snapshots --tag fd44 --json 2>/dev/null | grep -c '"time"') snapshots on the disk"
    else
        notify "Backup failed" "see: journalctl --user -u backup.service" critical
        die "restic failed"
    fi

    [[ ${MOUNTED_BY_US:-0} == 1 ]] && udisksctl unmount -b "$(lsblk -rno UUID,PATH | awk -v u="$BACKUP_UUID" '$1==u{print $2; exit}')" >/dev/null 2>&1 || true
    return 0
}

with_repo() {
    load_config
    local where repo
    where="$(ensure_mounted)" || die "the backup disk is not connected"
    repo="$(repo_path "$where")"
    restic_env "$repo"
}

cmd_status() {
    load_config
    local age; age="$(days_since_last)"
    printf '  %-22s %s\n' "disk UUID" "$BACKUP_UUID"
    printf '  %-22s %s\n' "connected" "$(disk_present && mount_point || echo no)"
    if [[ -f $LAST_RUN ]]; then
        printf '  %-22s %s (%s days ago)\n' "last backup" "$(date -d "@$(cat "$LAST_RUN")" '+%Y-%m-%d %H:%M')" "$age"
    else
        printf '  %-22s %s\n' "last backup" "never"
    fi
    if [[ ! -f $LAST_RUN ]]; then
        warn "nothing has been backed up yet - run: bin/backup.sh run"
    elif (( age > STALE_DAYS )); then
        warn "older than $STALE_DAYS days - the timer fails until this succeeds"
    fi
    disk_present || return 0
    with_repo
    restic snapshots --tag fd44 --latest 3 2>/dev/null | tail -5 | sed 's/^/  /'
}

#: NOT a local. The EXIT trap runs after cmd_verify has returned, by which
#: point a local of its is gone - and under `set -u` the trap then died with
#: "temp: unbound variable" and removed nothing, leaving a restored copy of
#: ~/.ssh in /tmp. Private keys, left behind by the command whose whole job is
#: to prove the backup works.
VERIFY_TMP=""
cleanup_verify() { [[ -n ${VERIFY_TMP:-} ]] && rm -rf "$VERIFY_TMP"; return 0; }

cmd_verify() {
    with_repo
    VERIFY_TMP="$(mktemp -d)"
    chmod 700 "$VERIFY_TMP"
    trap cleanup_verify EXIT INT TERM
    local temp="$VERIFY_TMP"
    note "restoring the latest snapshot into $temp"
    restic restore latest --target "$temp" --include "$HOME/.ssh" >/dev/null
    local restored="$temp$HOME/.ssh"
    [[ -d $restored ]] || die "the restore produced nothing at $restored"
    local differences=0
    diff -r "$HOME/.ssh" "$restored" >/dev/null 2>&1 || differences=1
    if (( differences == 0 )); then
        note "restored ~/.ssh matches what is on this machine"
    else
        warn "the restored copy differs from ~/.ssh - which is expected if it changed since the last backup"
        diff -rq "$HOME/.ssh" "$restored" 2>&1 | head -5 | sed 's/^/    /'
    fi
    note "a restore works. THIS is what makes it a backup rather than a hope."
}

cmd_escrow() {
    load_config 2>/dev/null || true
    cat <<TEXT
${bold}Keep these two things somewhere that is not this laptop${reset}
${dim}A safe, a paper note, a password manager on your phone - anywhere that
survives the machine. Without them the disk is 400 MB of noise.${reset}

  1. The repository password      (you typed it; it is at $PASSWORD_FILE)
  2. The disk                     UUID ${BACKUP_UUID:-<not set up>}

To restore onto a machine that has nothing but restic and the disk:

  restic -r /run/media/<you>/<disk>/$REPO_SUBDIR restore latest --target /

TEXT
}

case "${1-}" in
    setup)      cmd_setup ;;
    run)        shift; cmd_run "${1-}" ;;
    status)     cmd_status ;;
    snapshots)  with_repo; restic snapshots --tag fd44 ;;
    check)      with_repo; restic check ;;
    verify)     cmd_verify ;;
    restore)    [[ -n ${2-} ]] || die "usage: $0 restore DIR"; with_repo; restic restore latest --target "$2" ;;
    mount)      [[ -n ${2-} ]] || die "usage: $0 mount DIR"; with_repo; mkdir -p "$2"; restic mount "$2" ;;
    escrow)     cmd_escrow ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
