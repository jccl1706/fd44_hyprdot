# SSH_AUTH_SOCK, when the shell started before the agent did - or when nothing
# published the variable at all.
#
# THE AGENT IS FINE AND THE VARIABLE IS MISSING, in two different ways.
#
# FIRST: a shell that started before the agent's socket unit activates never
# sees a variable added afterwards. On a machine with a getty autologin the
# compositor starts very early, so every terminal it spawns is one of those.
#
# SECOND, AND NOT EVERY AGENT PUBLISHES IT AT ALL:
#
#   NixOS / gcr-ssh-agent      publishes SSH_AUTH_SOCK into the systemd user
#                              environment, at /run/user/N/gcr/ssh
#   Fedora / ssh-agent.service does NOT - the unit starts an agent on a socket
#                              and sets nothing in the environment, so only the
#                              shell can know where to look
#
# Found on 2026-10-10 on a freshly installed Fedora: agent running, socket on
# disk, SSH_AUTH_SOCK empty, and `ssh-add` answering "Could not open a
# connection to your authentication agent" with the agent right there. The
# machine's own ~/.bashrc used to hardcode Fedora's path and had been removed
# in favour of asking systemd - which is right on NixOS and answers nothing
# here.
#
# Only when unset: a shell that inherited a good value, or one where ssh-agent
# was started by hand, is left alone.
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    __fd44_sock=""

    # 1. whatever published it, if anything did
    if command -v systemctl >/dev/null 2>&1; then
        __fd44_sock="$(systemctl --user show-environment 2>/dev/null \
                       | sed -n 's/^SSH_AUTH_SOCK=//p')"
    fi

    # 2. the conventional places. Each is tested as a SOCKET rather than merely
    #    existing - a stale regular file at one of these paths would otherwise
    #    be exported and fail on every use.
    if [ -z "$__fd44_sock" ] || [ ! -S "$__fd44_sock" ]; then
        for __fd44_try in \
            "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket" \
            "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh" \
            "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring/ssh"
        do
            [ -S "$__fd44_try" ] && { __fd44_sock="$__fd44_try"; break; }
        done
        unset __fd44_try
    fi

    [ -n "$__fd44_sock" ] && [ -S "$__fd44_sock" ] && export SSH_AUTH_SOCK="$__fd44_sock"
    unset __fd44_sock
fi
