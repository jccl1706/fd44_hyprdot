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
#         bin/backup.sh readme       write RESTORE.md onto the disk
#         bin/backup.sh escrow       what has to be kept OFF this machine
#         bin/backup.sh disks        the disks it knows, and which is here
#         bin/backup.sh add-disk U   also back up to the disk with UUID U
#         bin/backup.sh remove-disk U  stop backing up to it (nothing is erased)
#
# MORE THAN ONE DISK, FOR ROTATION. BACKUP_UUID is a LIST: whichever of them is
# plugged in gets the backup, first listed wins when several are. That is what
# makes "one disk in use, one in a drawer or at another address" work without
# re-running setup every time they swap - re-running setup would also move the
# indicator in the bar, which would then go red whenever the "wrong" disk was
# attached.
#
# Each disk holds a complete repository of its own rather than half of one,
# so either can restore this machine alone. They are independent: a snapshot
# taken while disk A was attached is not on disk B until B is attached and a
# run happens.
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

# NOT FOR `json`, which has to answer on a machine that has never had restic:
# the bar asks every machine, and the gaming desktop - ext4, no backup set up -
# would otherwise get an error where it needs a plain "nothing configured
# here". Everything that actually touches a repository still refuses early.
if [[ ${1-} != json ]]; then
    command -v restic >/dev/null 2>&1 || die "restic is not installed (on Fedora: sudo dnf install restic)"
fi

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
    # A LIST, SPLIT ON WHITESPACE - which is why a config written before this
    # existed still works: one UUID is a list of one, and nothing about
    # BACKUP_UUID=8C26-3AF6 has to change.
    read -r -a UUIDS <<<"$BACKUP_UUID"
    (( ${#UUIDS[@]} )) || die "$CONFIG has an empty BACKUP_UUID"
    # Until select_disk finds one attached, the first is what messages name.
    ACTIVE_UUID="${UUIDS[0]}"

    # THE ONE DISK THAT EXISTED BEFORE PER-DISK DATES DID. Without this, the
    # first `status` after this change says "never" about the disk that was
    # backed up an hour ago, because only the global file had the date. With
    # one disk configured the global date IS that disk's date, and this is the
    # only moment that can be said safely: once a second disk is added, which
    # of them the old date belonged to is no longer knowable.
    if (( ${#UUIDS[@]} == 1 )) && [[ -f $LAST_RUN && ! -f $(last_run_file "${UUIDS[0]}") ]]; then
        cp -p "$LAST_RUN" "$(last_run_file "${UUIDS[0]}")" 2>/dev/null || true
    fi
}

# The first configured disk that is actually attached. Sets ACTIVE_UUID, which
# every other disk function reads, and returns 1 when none of them is here.
select_disk() {
    local u
    for u in "${UUIDS[@]}"; do
        if lsblk -rno UUID 2>/dev/null | grep -qx "$u"; then
            ACTIVE_UUID="$u"
            return 0
        fi
    done
    return 1
}

# WHEN EACH DISK WAS LAST WRITTEN, which one global file cannot say once there
# is more than one: with a disk in a drawer, "the last backup was today" is
# true of the pair and says nothing about the copy that is off-site. The
# global LAST_RUN stays as the newest of any disk - that is what the bar's
# staleness means, and it is what tells you whether A copy exists - and
# `disks` prints the per-disk dates beside it.
last_run_file() { printf '%s/backup-last-%s' "$STATE_DIR" "${1//\//_}"; }

days_since_file() {
    local f="$1" then now
    [[ -f $f ]] || { echo 99999; return; }
    then=$(cat "$f" 2>/dev/null || echo 0)
    now=$(date +%s)
    echo $(( (now - then) / 86400 ))
}

# A label a person recognises, since a UUID is not one.
disk_label() {
    local u="$1" label
    label="$(lsblk -rno UUID,LABEL 2>/dev/null | awk -v u="$u" '$1 == u { $1=""; sub(/^ /,""); print; exit }')"
    printf '%s' "${label:-$u}"
}

#: Where the disk with that UUID is mounted, or nothing.
mount_point() {
    lsblk -rno UUID,MOUNTPOINT 2>/dev/null |
        awk -v uuid="$ACTIVE_UUID" '$1 == uuid && $2 != "" { print $2; exit }' |
        sed 's/\\x20/ /g'
}

disk_present() {
    select_disk
}

# Mount through udisks, as the user, so this needs no root and no fstab entry
# for a disk that is usually not here.
# IT SETS MOUNT_WHERE RATHER THAN ECHOING IT, and that is not a style
# preference. Every caller wrote `where="$(ensure_mounted)"`, which runs it in
# a SUBSHELL - so the two variables it sets were set in a process that then
# exited:
#
#   ACTIVE_UUID     the disk it picked. The parent kept the FIRST configured
#                   disk, so with the T5 in a drawer and the LaCie attached,
#                   the repository was correctly created on the LaCie - from
#                   $where, which did survive - while every later call went
#                   looking for the T5 and died with "the backup disk is not
#                   mounted". Invisible until there was a second disk.
#
#   MOUNTED_BY_US   whether to unmount afterwards. It was never true in the
#                   parent, so a disk this script mounted was always left
#                   mounted. That one was invisible with one disk too: it just
#                   looked like the disk staying put.
ensure_mounted() {
    MOUNT_WHERE=""
    local where
    where="$(mount_point)"
    [[ -n $where ]] && { MOUNT_WHERE="$where"; return 0; }
    disk_present || return 1
    # disk_present ran select_disk, so ACTIVE_UUID is now the disk that is
    # actually here - and in THIS shell, where the rest of the run can see it.
    local device
    device="$(lsblk -rno UUID,PATH 2>/dev/null | awk -v u="$ACTIVE_UUID" '$1==u{print $2; exit}')"
    # ONLY OURS IF WE ACTUALLY MOUNTED IT. This flag decides whether the disk
    # is unmounted when the run finishes, and it used to be set whenever the
    # disk ended up mounted - including when udisksctl failed because somebody
    # had already mounted it by hand. The run then ejected a disk it did not
    # mount, out from under whoever was looking at it. (Harmless until the
    # subshell bug above was fixed, because the flag never reached the parent
    # shell at all.)
    local mounted_now=0
    udisksctl mount -b "$device" >/dev/null 2>&1 && mounted_now=1
    where="$(mount_point)"
    [[ -n $where ]] || return 1
    (( mounted_now )) && MOUNTED_BY_US=1
    MOUNT_WHERE="$where"
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

    printf 'BACKUP_UUID="%s"\n' "$uuid" > "$CONFIG"
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
    ensure_mounted || die "could not mount the disk"; where="$MOUNT_WHERE"
    repo="$(repo_path "$where")"
    restic_env "$repo"
    if restic cat config >/dev/null 2>&1; then
        note "repository already exists at $repo"
    else
        mkdir -p "$repo"
        restic init
        note "created the repository at $repo"
    fi
    cmd_readme
    echo
    cmd_escrow
}

cmd_run() {
    load_config
    local where repo
    if ! ensure_mounted; then
        local age; age="$(days_since_last)"
        if (( age > STALE_DAYS )); then
            notify "Backup disk not connected" "No backup for $age days" critical
            die "the backup disk is not here, and the last backup was $age days ago"
        fi
        if (( ${#UUIDS[@]} > 1 )); then
            note "none of the ${#UUIDS[@]} backup disks is connected - nothing to do (last backup ${age}d ago)"
        else
            note "the backup disk is not connected - nothing to do (last backup ${age}d ago)"
        fi
        return 0
    fi
    where="$MOUNT_WHERE"
    repo="$(repo_path "$where")"
    restic_env "$repo"

    local args=(backup --tag fd44 --exclude-caches)
    local path
    while IFS= read -r path; do [[ -e $path ]] && args+=("$path"); done < <(includes)
    while IFS= read -r path; do args+=(--exclude "$path"); done < <(excludes)
    [[ ${1-} == --dry-run ]] && args+=(--dry-run --verbose)

    # A DISK'S FIRST RUN CREATES ITS REPOSITORY. `setup` does this for the
    # first disk, but the second one is added by `add-disk` and may not even be
    # plugged in at the time - so the run that first sees it is what has to
    # initialise it, or rotation would need a setup step per disk.
    if ! restic cat config >/dev/null 2>&1; then
        mkdir -p "$repo"
        note "first backup to $(disk_label "$ACTIVE_UUID") - creating the repository"
        restic init || die "could not create a repository on $repo"
        cmd_readme >/dev/null
    fi

    note "backing up to $repo"
    if restic "${args[@]}"; then
        [[ ${1-} == --dry-run ]] || { date +%s > "$LAST_RUN"; date +%s > "$(last_run_file "$ACTIVE_UUID")"; }
        # A LOCK LEFT BY AN INTERRUPTED RUN WOULD BLOCK THIS FOREVER, and it
        # did: a run killed on 24 September left its lock behind, and the
        # first prune afterwards died with "repository is already locked by
        # PID 19262 ... 91h34m ago". `unlock` removes only STALE locks - one
        # whose process is gone - and never a live one, so this cannot
        # interfere with a backup running on another machine.
        [[ ${1-} == --dry-run ]] || restic unlock >/dev/null 2>&1 || true

        # KEEP A YEAR, THINNING OUT. Daily for a week catches "I deleted it
        # yesterday"; monthly for a year catches "that file existed in March".
        #
        # AND ITS FAILURE IS NOT THE BACKUP'S FAILURE. Under `set -e` a prune
        # that could not get the lock took the whole run down with it - exit
        # 11, no README refresh, no notification, the disk left mounted - for
        # a backup that had ALREADY SUCCEEDED and been recorded. Thinning old
        # snapshots is housekeeping; it can wait for tomorrow's run.
        if [[ ${1-} != --dry-run ]]; then
            restic forget --tag fd44 \
                --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune \
                || warn "the backup succeeded; thinning old snapshots did not - it will be retried on the next run"
        fi
        cmd_readme >/dev/null
        notify "Backup complete" "$(restic snapshots --tag fd44 --json 2>/dev/null | grep -c '"time"') snapshots on the disk"
    else
        notify "Backup failed" "see: journalctl --user -u backup.service" critical
        die "restic failed"
    fi

    [[ ${MOUNTED_BY_US:-0} == 1 ]] && udisksctl unmount -b "$(lsblk -rno UUID,PATH | awk -v u="$ACTIVE_UUID" '$1==u{print $2; exit}')" >/dev/null 2>&1 || true
    return 0
}

with_repo() {
    load_config
    local where repo
    ensure_mounted || die "the backup disk is not connected"; where="$MOUNT_WHERE"
    repo="$(repo_path "$where")"
    restic_env "$repo"
}

# The same answer as `status`, in one line a program can read: the bar's
# backup indicator (quickshell/Backups.qml) polls this.
#
# IT MUST NOT DIE, whatever the state of the machine. `status` calls
# load_config, which exits when the machine has never been set up - correct
# for a person at a terminal, useless for a caller that needs an answer either
# way. A machine with no backup configured is not an error here, it is
# "configured": false, and the bar draws nothing.
#
# NOTHING IS MOUNTED AND NO PASSWORD IS READ. This runs on a timer in the
# background; it answers from the state file and from whether the disk is
# present, so it costs nothing and cannot prompt for anything.
# The terminal the bar's backup icon opens: `run` with its output on screen.
# A backup talks - what it is reading, what it sent, how long it took - and
# that is worth a window rather than a notification saying "done".
cmd_disks() {
    load_config
    local u mark age_u here
    printf '  %-38s %-10s %s\n' "UUID" "state" "last backup to it"
    for u in "${UUIDS[@]}"; do
        if lsblk -rno UUID 2>/dev/null | grep -qx "$u"; then
            here="$(lsblk -rno UUID,MOUNTPOINT 2>/dev/null | awk -v x="$u" '$1==x && $2!="" {print $2; exit}')"
            mark="attached"
        else
            here=""
            mark="absent"
        fi
        age_u="$(days_since_file "$(last_run_file "$u")")"
        if (( age_u > 99998 )); then age_u="never"; else age_u="${age_u} days ago"; fi
        printf '  %-38s %-10s %s%s\n' "$u" "$mark" "$age_u" "${here:+  ($here)}"
    done
    echo
    printf '    %sthe first attached disk in this list gets the backup%s\n' "$dim" "$reset"
}

cmd_add_disk() {
    local uuid="${1-}"
    [[ -n $uuid ]] || die "usage: $0 add-disk UUID   (see: lsblk -o NAME,SIZE,LABEL,UUID)"
    load_config
    local u
    for u in "${UUIDS[@]}"; do
        [[ $u == "$uuid" ]] && { note "$uuid is already in the list"; return 0; }
    done
    # NOT REQUIRED TO BE ATTACHED. The point of a second disk is that it
    # spends most of its life somewhere else, and a rule that it must be
    # plugged in to be added would mean adding it from the machine you are
    # trying to protect against losing. It is only warned about.
    lsblk -rno UUID 2>/dev/null | grep -qx "$uuid" \
        || warn "no filesystem with UUID $uuid is attached right now - added anyway"
    # QUOTED, because the config is SOURCED: BACKUP_UUID=a b parses as an
    # assignment followed by the command `b`, which is how the first version of
    # this printed "1234-ABCD: command not found" and then read no disks at
    # all. A single UUID needs no quotes and a list does, so everything that
    # writes this file quotes.
    printf 'BACKUP_UUID="%s"\n' "${BACKUP_UUID} $uuid" > "$CONFIG"
    chmod 600 "$CONFIG"
    note "added $uuid - $(( ${#UUIDS[@]} + 1 )) disks configured"
    note "its repository is created by the first run that finds it attached"
}

cmd_remove_disk() {
    local uuid="${1-}"
    [[ -n $uuid ]] || die "usage: $0 remove-disk UUID"
    load_config
    local u kept=()
    for u in "${UUIDS[@]}"; do [[ $u == "$uuid" ]] || kept+=("$u"); done
    (( ${#kept[@]} == ${#UUIDS[@]} )) && die "$uuid is not in the list"
    (( ${#kept[@]} )) || die 'that is the only disk configured - use `setup` to point at another one instead'
    printf 'BACKUP_UUID="%s"\n' "${kept[*]}" > "$CONFIG"
    chmod 600 "$CONFIG"
    # NOTHING ON THE DISK IS TOUCHED. Its repository is complete and still
    # restores this machine on its own; it simply stops being written to.
    note "removed $uuid - nothing on that disk was changed, and it can still restore"
}

cmd_open() {
    local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "$here/in-terminal.sh" "Backup" "$here/backup.sh" run
}

cmd_json() {
    local configured=false uuid="" connected=false days=-1 never=true disks=0
    if [[ -f $CONFIG ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG" 2>/dev/null || true
        if [[ -n ${BACKUP_UUID:-} ]]; then
            configured=true
            read -r -a UUIDS <<<"$BACKUP_UUID"
            disks=${#UUIDS[@]}
            ACTIVE_UUID="${UUIDS[0]}"
        fi
    fi
    if [[ $configured == true ]]; then
        # select_disk sets ACTIVE_UUID to whichever is here, so "uuid" names
        # the disk being used rather than the first one ever configured.
        disk_present && connected=true
        uuid="$ACTIVE_UUID"
        if [[ -f $LAST_RUN ]]; then
            never=false
            days="$(days_since_last)"
        fi
    fi
    printf '{"configured":%s,"uuid":"%s","disks":%s,"connected":%s,"never":%s,"days":%s,"stale_days":%s}\n' \
        "$configured" "$uuid" "$disks" "$connected" "$never" "$days" "$STALE_DAYS"
}

cmd_status() {
    load_config
    local age; age="$(days_since_last)"
    local u mark age_u
    for u in "${UUIDS[@]}"; do
        if lsblk -rno UUID 2>/dev/null | grep -qx "$u"; then mark="attached"; else mark="absent"; fi
        age_u="$(days_since_file "$(last_run_file "$u")")"
        if (( age_u > 99998 )); then age_u="never"; else age_u="${age_u}d ago"; fi
        printf '  %-22s %s  %s  %s\n' "disk" "$u" "$(printf '%-8s' "$mark")" "$age_u"
    done
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

# A README ON THE DISK ITSELF, because the disk is the one thing that survives
# this machine, and a restore is exactly the moment when nothing else is to
# hand: no checkout, no notes, possibly no laptop. Written by `setup` and
# rewritten after every successful backup, so it cannot describe a repository
# that has moved.
#
# IT CONTAINS NO PASSWORD and must not. Anyone holding the disk can read it;
# the password is what stops them reading the backup.
cmd_readme() {
    load_config
    local where repo target
    # ensure_mounted, NOT mount_point: load_config resets ACTIVE_UUID to the
    # first configured disk every time it runs, so asking for "the mount point
    # of ACTIVE_UUID" here found the disk in the drawer and died with "the
    # backup disk is not mounted" - immediately after writing a snapshot to
    # the one that was actually attached.
    ensure_mounted || die "the backup disk is not connected"
    where="$MOUNT_WHERE"
    repo="$(repo_path "$where")"
    target="$repo/RESTORE.md"
    cat > "$target" <<TEXT
# How to get this back

This directory is a [restic](https://restic.net) repository holding the home
directory of **$(whoami)@$(hostname 2>/dev/null || cat /etc/hostname)**.
Written by \`bin/backup.sh\` from the fd44_hyprdot repository.

Last written: $(date '+%Y-%m-%d %H:%M %Z')

## You need two things

1. **restic.** \`sudo dnf install restic\`, \`apt install restic\`,
   \`brew install restic\`, or the single binary from restic.net - it needs no
   configuration and no daemon.
2. **The repository password.** It is *not* on this disk, by design. Without it
   everything here is noise; there is no recovery and no back door.

## Point restic at this folder

\`\`\`sh
export RESTIC_REPOSITORY=/path/to/this/folder   # the folder holding this file
\`\`\`

On the machine it was written from that path was
\`$where/$REPO_SUBDIR\`, but a disk mounts wherever the machine
you plug it into decides, so use the path you actually see.

Every command below reads that variable and will ask for the password.

## Look before you restore

\`\`\`sh
restic snapshots      # what is here, and from when
restic ls latest      # every file in the newest one
\`\`\`

## Get one file back

\`\`\`sh
restic restore latest --target /tmp/out --include '/home/*/.ssh'
\`\`\`

Paths are absolute, as they were on the machine that was backed up, and
\`--target\` is a prefix - the line above puts the keys in
\`/tmp/out/home/<user>/.ssh\`. **Restore somewhere empty and copy across by
hand**; restoring straight over a live home directory is how a good backup
ruins a working machine.

## Get everything back

\`\`\`sh
restic restore latest --target /tmp/out
\`\`\`

Then copy what you want.

**Permissions come back on their own.** restic keeps mode and ownership inside
the repository rather than on the disk, so \`~/.ssh\` restores as 0700 with its
keys at 0600 even though the disk itself is exfat and has no idea what a Unix
permission is - checked, not assumed. Ownership is only restored when restic
runs as root; as an ordinary user everything comes back owned by you, which is
what you want when moving to a new machine anyway.

## Browse it like a filesystem

\`\`\`sh
mkdir /tmp/browse && restic mount /tmp/browse
\`\`\`

Every snapshot appears under \`/tmp/browse/snapshots/\`, read-only. Ctrl-C to
unmount. Needs FUSE.

## What is in here

| | |
| --- | --- |
| \`~/.ssh\` | private keys - the only thing that cannot be regenerated |
| \`~/.config/gh\`, \`~/.config/copr\` | API tokens |
| \`~/.claude\`, \`~/.claude.json\` | sessions, memory, settings |
| \`~/.config/chromium\` | logins, cookies, bookmarks, history |
| \`~/Work\` | git checkouts - also on GitHub, but not the uncommitted parts |
| shell config, desktop state | small, and what makes the machine yours |

The system itself is not here and does not need to be: it is rebuilt from
<https://github.com/jccl1706/fd44_hyprdot>, which is what put this file here.

## If something looks wrong

\`\`\`sh
restic check              # verify the repository
restic check --read-data  # slower, reads every byte
\`\`\`

TEXT
    note "wrote $target"
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
    json)       cmd_json ;;
    open)       cmd_open ;;
    disks)      cmd_disks ;;
    add-disk)   cmd_add_disk "${2-}" ;;
    remove-disk) cmd_remove_disk "${2-}" ;;
    snapshots)  with_repo; restic snapshots --tag fd44 ;;
    check)      with_repo; restic check ;;
    verify)     cmd_verify ;;
    restore)    [[ -n ${2-} ]] || die "usage: $0 restore DIR"; with_repo; restic restore latest --target "$2" ;;
    mount)      [[ -n ${2-} ]] || die "usage: $0 mount DIR"; with_repo; mkdir -p "$2"; restic mount "$2" ;;
    readme)     cmd_readme ;;
    escrow)     cmd_escrow ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
