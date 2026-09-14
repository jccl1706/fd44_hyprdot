#!/usr/bin/env bash
# =========================================================================
# ssh-keys-only.sh - make sshd accept ssh keys and nothing else
# =========================================================================
#
# Usage:  sudo bin/ssh-keys-only.sh           lock sshd down to keys
#         sudo bin/ssh-keys-only.sh --undo    remove the drop-in again
#
# For machines where sshd was switched on by hand - the laptop and the
# desktop reach each other over ssh with keys (README, "Rebuilding the
# desktop"). The installer itself never installs sshd.
#
# WHY. Fedora's sshd accepts passwords by default. On a laptop that joins other
# people's Wi-Fi, that is a login prompt anyone on the network can guess at.
# Once both machines log in with keys, passwords over ssh are pure exposure.
#
# WHAT IT WRITES: /etc/ssh/sshd_config.d/10-fd44-keys-only.conf
#
#   PasswordAuthentication no        no password prompts
#   KbdInteractiveAuthentication no  ...including through PAM's conversation
#   AuthenticationMethods publickey  a key is the only way in
#   PermitRootLogin no               root is locked anyway; say so here too
#   AllowUsers <you>                 no other account, even with a key
#
# FILE NAME MATTERS. Fedora's sshd_config includes sshd_config.d/*.conf before
# its own settings, in name order, and for each setting the FIRST value sshd
# reads wins. "10-" sorts ahead of Fedora's 40-redhat-crypto-policies.conf and
# 50-redhat.conf, so nothing shipped can override it.
#
# IT WILL NOT LOCK YOU OUT: it refuses to run unless your authorized_keys
# holds at least one key, checks the result with `sshd -t` before touching the
# running server (and removes the drop-in if the check fails), and reloads
# rather than restarts, so an ssh session already open stays open.

set -euo pipefail

die() { printf '\033[1;31mssh-keys-only:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

(( EUID == 0 )) || die "must run as root - try: sudo $0"
user="${SUDO_USER:-}"
[[ -n $user && $user != root ]] || die "run it with sudo from your own account"
home="$(getent passwd "$user" | cut -d: -f6)"

conf=/etc/ssh/sshd_config.d/10-fd44-keys-only.conf

command -v sshd >/dev/null 2>&1 || die "openssh-server is not installed - there is no sshd to lock down"

reload_if_running() {
    if systemctl is-active --quiet sshd; then
        systemctl reload sshd
        log "sshd reloaded (open sessions are not affected)"
    else
        log "sshd is not running - the settings apply when it starts"
    fi
}

if [[ ${1:-} == --undo ]]; then
    rm -f "$conf"
    sshd -t || die "sshd -t fails even without the drop-in - fix /etc/ssh first"
    reload_if_running
    log "removed $conf - sshd is back to Fedora's defaults"
    exit 0
fi
[[ -z ${1:-} ]] || die "usage: sudo $0 [--undo]"

# --- lockout guard -----------------------------------------------------------
ak="$home/.ssh/authorized_keys"
keys="$(grep -cE '^[[:space:]]*(ssh-(ed25519|rsa|dss)|ecdsa-sha2-|sk-)' "$ak" 2>/dev/null || true)"
(( ${keys:-0} > 0 )) || die "$ak has no keys - add the other machine's public key first, or this would lock you out of ssh"
log "$ak holds $keys key(s):"
ssh-keygen -lf "$ak" 2>/dev/null | sed 's/^/    /'

# --- the drop-in ---------------------------------------------------------------
log "writing $conf"
install -d -m 755 "$(dirname "$conf")"
tmp="$(mktemp "$conf.XXXXXX")"
cat > "$tmp" <<EOF
# Written by bin/ssh-keys-only.sh (fd44_hyprdot). Keys only; see that script.
# Remove with:  sudo bin/ssh-keys-only.sh --undo
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitRootLogin no
AllowUsers $user
EOF
chmod 600 "$tmp"
mv -f "$tmp" "$conf"

if ! sshd -t; then
    rm -f "$conf"
    die "sshd -t rejected the configuration - drop-in removed, nothing changed"
fi
reload_if_running

# --- verify ----------------------------------------------------------------------
log "verification"
fail=0
effective="$(sshd -T 2>/dev/null)"
expect() {
    if grep -qix "$1" <<<"$effective"; then
        printf '    ok   %s\n' "$1"
    else
        printf '    FAIL %s (sshd uses: %s)\n' "$1" "$(grep -i "^${1%% *} " <<<"$effective" || echo unset)"
        fail=1
    fi
}
expect "passwordauthentication no"
expect "kbdinteractiveauthentication no"
expect "authenticationmethods publickey"
expect "permitrootlogin no"
expect "allowusers $user"

# The real test: ask the running server which methods it offers someone who
# has no key. Only "publickey" may come back.
if systemctl is-active --quiet sshd; then
    port="$(awk '/^port /{print $2; exit}' <<<"$effective")"
    offered="$(runuser -u "$user" -- ssh -v -p "${port:-22}" \
        -o BatchMode=yes -o PubkeyAuthentication=no \
        -o PreferredAuthentications=password,keyboard-interactive \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 "$user@127.0.0.1" true 2>&1 \
        | tr -d '\r' \
        | sed -n 's/.*Authentications that can continue: //p' | head -1 || true)"
    # ssh -v ends its debug lines with "\r\n", so without the tr above the
    # captured value was "publickey\r" - printed as "publickey", compared as
    # a mismatch. Trailing whitespace is trimmed for the same reason.
    offered="${offered%"${offered##*[![:space:]]}"}"
    if [[ $offered == publickey ]]; then
        printf '    ok   a login without a key is offered only: publickey\n'
    else
        printf '    FAIL a login without a key is offered: %s\n' "${offered:-(no answer)}"
        fail=1
    fi
fi

(( fail )) && die "verification failed - check the lines above ($conf is still in place)"
log "done - ssh on this machine accepts keys only"
