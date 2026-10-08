# tmux, from any shell.  Sourced from ~/.bashrc.d/.
#
# Two things that are tedious to type and easy to get wrong: finding out what
# sessions exist, and getting back into one.
#
#   tls          what is running, and which session you are in
#   ta [name]    attach to it - or switch, if you are already inside tmux
#   tk [name]    kill one, with the name required if you are inside it
#
# WHY ta IS A FUNCTION AND NOT AN ALIAS. `tmux attach` fails from inside tmux:
# nesting a client in its own session is almost never meant, and tmux says so
# ("sessions should be nested with care") rather than doing it. The right
# command from inside is `switch-client`. One name that does the right thing
# from either place is the whole point.

# What is running. tmux exits 1 with "no server running on ..." when there is
# none, which is noise rather than an error worth seeing.
tls() {
    if ! tmux list-sessions 2>/dev/null; then
        echo "no tmux sessions"
        return 0
    fi
    [ -n "${TMUX:-}" ] && printf 'you are in: %s\n' "$(tmux display-message -p '#S')"
    return 0
}

ta() {
    local target="${1:-}"

    # With no name: one session means there is no choice to make, so take it.
    # More than one and guessing would be worse than asking.
    if [ -z "$target" ]; then
        local sessions count
        sessions="$(tmux list-sessions -F '#S' 2>/dev/null)" || { echo "no tmux sessions"; return 1; }
        count="$(printf '%s\n' "$sessions" | grep -c .)"
        if [ "$count" -eq 1 ]; then
            target="$sessions"
        else
            echo "which one?"
            tmux list-sessions 2>/dev/null | sed 's/^/  /'
            return 1
        fi
    fi

    # INSIDE tmux, SWITCH; OUTSIDE, ATTACH. Same name, right command.
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "$target"
    else
        tmux attach-session -t "$target"
    fi
}

# tk - kill a session.
#
# THE NAME IS REQUIRED WHEN YOU ARE INSIDE THE SESSION YOU WOULD BE KILLING.
# `tmux kill-session` with no target kills the current one, which from inside
# means the shell you typed it in disappears mid-command. That is occasionally
# what someone wants and never what they expected, so it has to be said out
# loud here.
tk() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        if [ -n "${TMUX:-}" ]; then
            printf 'name the session: tk %s would kill the one you are in\n' \
                "$(tmux display-message -p '#S')" >&2
            return 1
        fi
        echo "which one?" >&2
        tmux list-sessions 2>/dev/null | sed 's/^/  /' >&2
        return 1
    fi
    tmux kill-session -t "$target" && echo "killed $target"
}

# Completing on session names makes `ta <tab>` worth having at all.
_ta_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local names
    names="$(tmux list-sessions -F '#S' 2>/dev/null)"
    mapfile -t COMPREPLY < <(compgen -W "$names" -- "$cur")
}
complete -F _ta_complete ta
complete -F _ta_complete tk
