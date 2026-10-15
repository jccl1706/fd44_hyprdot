#!/usr/bin/env bash
# =========================================================================
# ssh-trust.sh - let another machine in, without typing a key by hand
# =========================================================================
#
# Usage:  bin/ssh-trust.sh <name>    authorise keys/<name>.pub
#         bin/ssh-trust.sh           list the names available
#
# A PUBLIC KEY IS PUBLIC, so the ones used between these machines live in
# keys/ rather than being pasted through a terminal. Pasting is how the file
# ends up with a line break in the middle of the key, or owned by root because
# the command was run with sudo, or missing its SELinux label - three failures
# that all present as "Permission denied (publickey)" and none of which say so.
#
# NEVER RUN THIS WITH sudo. The file has to belong to the user logging in;
# sshd ignores an authorized_keys it does not trust the ownership of, and says
# nothing about why on the client side.

set -euo pipefail

name="${0##*/}"
die() { printf '%s: %s\n' "$name" "$*" >&2; exit 1; }
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

repo="$(cd "$(dirname "$0")/.." && pwd)"
keydir="$repo/keys"

[[ $EUID -ne 0 ]] || die "do not run this as root - the key must belong to the user logging in"
[[ -d $keydir ]] || die "no keys/ directory in $repo"

if [[ $# -eq 0 ]]; then
    printf 'Available keys:\n'
    for k in "$keydir"/*.pub; do
        [[ -f $k ]] || continue
        printf '  %-14s %s\n' "$(basename "$k" .pub)" "$(cut -d' ' -f3- "$k")"
    done
    exit 0
fi

key="$keydir/$1.pub"
[[ -f $key ]] || die "no such key: keys/$1.pub"

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# IDEMPOTENT ON THE KEY ITSELF, not on the whole line: the comment at the end
# is free text and two copies of one key with different comments are still two
# copies of one key.
material="$(cut -d' ' -f1,2 "$key")"
if grep -qF "$material" ~/.ssh/authorized_keys 2>/dev/null; then
    say "already authorised: $1"
else
    cat "$key" >> ~/.ssh/authorized_keys
    say "authorised: $1"
fi

# The home directory counts too. sshd refuses a key when the home is writable
# by anyone but its owner, and that refusal looks identical to a missing key.
chmod go-w ~ 2>/dev/null || true

if command -v restorecon >/dev/null 2>&1; then
    restorecon -R ~/.ssh 2>/dev/null || true
    say "selinux labels restored"
fi

printf '\n'
ls -la ~/.ssh/authorized_keys
printf '\n  owner must be you, and the mode must be -rw-------\n'
