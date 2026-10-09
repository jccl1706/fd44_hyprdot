# SSH_AUTH_SOCK, when the shell started before the agent did.
#
# THE AGENT IS FINE AND THE VARIABLE IS MISSING. Both gcr-ssh-agent (NixOS,
# GNOME keyring) and Fedora's own agent publish SSH_AUTH_SOCK into the SYSTEMD
# USER ENVIRONMENT when their socket unit activates. A process that was already
# running never sees a variable added afterwards - and on a machine with a
# getty autologin the compositor starts very early, so every terminal it spawns
# is one of those processes. `ssh-add` then answers:
#
#     Error connecting to agent: No such file or directory
#
# while `systemctl --user show-environment` has the socket right there.
#
# ASKED OF SYSTEMD RATHER THAN HARDCODED, because the path differs by agent and
# by version - /run/user/N/gcr/ssh here, /run/user/N/keyring/ssh under a plain
# gnome-keyring, /tmp/ssh-XXXX/agent.N for a hand-started ssh-agent. Whatever
# published it is what this reads.
#
# Only when unset: a shell that inherited a good value, or one where ssh-agent
# was started by hand, is left alone.
if [ -z "${SSH_AUTH_SOCK:-}" ] && command -v systemctl >/dev/null 2>&1; then
    __fd44_sock="$(systemctl --user show-environment 2>/dev/null \
                   | sed -n 's/^SSH_AUTH_SOCK=//p')"
    [ -n "$__fd44_sock" ] && [ -S "$__fd44_sock" ] && export SSH_AUTH_SOCK="$__fd44_sock"
    unset __fd44_sock
fi
