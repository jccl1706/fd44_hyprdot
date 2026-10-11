#!/usr/bin/env bash
# One-time setup so the test VM can be driven over ssh instead of its console.
# Run INSIDE the VM:   curl -s http://10.0.2.2:8000/vm-ssh.sh | sudo bash
set -euo pipefail
u="${SUDO_USER:-jc}"
h="$(getent passwd "$u" | cut -d: -f6)"
rpm -q openssh-server >/dev/null 2>&1 || dnf install -y -q openssh-server
systemctl enable --now sshd
install -d -m 0700 -o "$u" -g "$u" "$h/.ssh"
key="$(curl -fsS http://10.0.2.2:8000/vm-ssh-key.pub)"
touch "$h/.ssh/authorized_keys"
grep -qxF "$key" "$h/.ssh/authorized_keys" || printf '%s\n' "$key" >> "$h/.ssh/authorized_keys"
chown "$u:$u" "$h/.ssh/authorized_keys"; chmod 0600 "$h/.ssh/authorized_keys"
printf 'READY - sshd up, key installed for %s\n' "$u"
