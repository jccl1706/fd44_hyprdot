#!/bin/sh
# =========================================================================
# freebsd-installer-ssh.sh - reach a running FreeBSD installer over ssh
# =========================================================================
#
# Run it from the installer's shell, in one line:
#
#   fetch -o - https://raw.githubusercontent.com/jccl1706/fd44_hyprdot/master/bin/freebsd-installer-ssh.sh | sh
#
# WHY. bsdinstall's disk list shows model and size and nothing else, and the
# T480 carries two 512 GB NVMe drives - one holding Fedora, LUKS and every
# byte on the machine. Picking the wrong line there is unrecoverable and the
# sizes are identical. Over ssh the disk can be chosen by SERIAL instead,
# which is the only thing that tells them apart without ambiguity.
#
# NOTHING IS TYPED BY HAND THAT SHOULD NOT BE. It authorises the public keys
# GitHub publishes for the account - https://github.com/<user>.keys - so no
# password is set, shared or transcribed. Those keys are already public; this
# only says which of them may log in.
#
# EVERYTHING LIVES IN /tmp, on purpose: the installer's root filesystem is
# mounted read-only, so ssh-keygen -A and edits to /etc/ssh would fail. A host
# key, an authorized_keys and a config under /tmp avoid /etc entirely.
#
# It is deliberately NOT persistent. This configures the RAM-disk installer
# environment for the length of one session; the installed system gets its own
# sshd, configured separately and properly.

set -u
GH_USER="${GH_USER:-jccl1706}"
D=/tmp/ssh

say() { echo "==> $*"; }
die() { echo "!!! $*" >&2; exit 1; }

# ---- network -------------------------------------------------------------
# The wired port, because the installer has no wifi configured and this is a
# laptop sitting on a desk next to its cable. On a ThinkPad T480 the Intel
# I219-V comes up as em0; ifconfig -l is asked rather than assumed, since the
# name follows the driver and not the socket.
say "interfaces: $(ifconfig -l)"
IF="${IF:-}"
if [ -z "$IF" ]; then
    for i in $(ifconfig -l); do
        case "$i" in lo0|pflog*|pfsync*) continue;; esac
        # a wired interface that has a carrier
        if ifconfig "$i" 2>/dev/null | grep -q 'status: active'; then IF="$i"; break; fi
    done
fi
[ -n "$IF" ] || die "no active interface - plug the ethernet cable in, or set IF=xxx"
say "using interface $IF"

ifconfig "$IF" up 2>/dev/null
if ! ifconfig "$IF" | grep -q 'inet '; then
    say "asking for a DHCP lease on $IF"
    dhclient "$IF" >/dev/null 2>&1 || die "dhclient failed on $IF"
fi
IP=$(ifconfig "$IF" | awk '/inet /{print $2; exit}')
[ -n "$IP" ] || die "no address on $IF"
say "address: $IP"

# ---- keys ----------------------------------------------------------------
mkdir -p "$D" || die "cannot write $D"
say "fetching public keys for github user $GH_USER"
fetch -q -o "$D/authorized_keys" "https://github.com/${GH_USER}.keys" \
    || die "could not fetch https://github.com/${GH_USER}.keys"
N=$(grep -c . "$D/authorized_keys" 2>/dev/null || echo 0)
[ "$N" -gt 0 ] || die "no keys published for $GH_USER"
chmod 600 "$D/authorized_keys"
say "authorised $N key(s)"

# ---- sshd ----------------------------------------------------------------
say "generating a throwaway host key"
ssh-keygen -q -t ed25519 -N '' -f "$D/host_ed25519" </dev/null || die "ssh-keygen failed"

cat > "$D/sshd_config" <<EOF
Port 22
HostKey $D/host_ed25519
PermitRootLogin prohibit-password
AuthorizedKeysFile $D/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PidFile $D/sshd.pid
EOF

/usr/sbin/sshd -f "$D/sshd_config" || die "sshd would not start"
sleep 1
if sockstat -4 -l 2>/dev/null | grep -q ':22'; then
    say "sshd listening on port 22"
else
    say "sshd started but nothing is listening on 22 - check: /usr/sbin/sshd -d -f $D/sshd_config"
fi

# ---- what the other end needs to know ------------------------------------
echo
echo "  ssh root@$IP"
echo
echo "  host key fingerprint, to compare on first connect:"
ssh-keygen -lf "$D/host_ed25519.pub" | sed 's/^/    /'
echo
echo "  disks seen by this installer:"
for d in $(sysctl -n kern.disks); do
    case "$d" in cd*|md*) continue;; esac
    ident=$(geom disk list "$d" 2>/dev/null | awk -F': ' '/ident:/{print $2}')
    descr=$(geom disk list "$d" 2>/dev/null | awk -F': ' '/descr:/{print $2}')
    printf '    %-6s %-28s serial=%s\n' "$d" "$descr" "$ident"
done
echo
