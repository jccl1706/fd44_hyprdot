#!/usr/bin/env bash
# Throwaway diagnostic for the installer test VM. Reads only.
line(){ printf '\n== %s\n' "$*"; }
line "compositor state file"
cat ~/.local/state/fd44-compositor 2>&1 | sed 's/^/  /'
line "bash_profile: which one, and the start line"
printf '  symlink: %s\n' "$(readlink -f ~/.bash_profile)"
grep -nE 'uwsm start|__UWSM|fd44-compositor' ~/.bash_profile 2>/dev/null | head -6 | sed 's/^/  /'
line "uwsm check may-start"
uwsm check may-start; printf '  rc=%s\n' "$?"
line "uwsm start log (last 12)"
tail -12 ~/.local/state/uwsm-start.log 2>&1 | sed 's/^/  /'
line "wayland sessions"
ls /usr/share/wayland-sessions/ /usr/local/share/wayland-sessions/ 2>/dev/null | sed 's/^/  /'
line "niri config"
printf '  ~/.config/niri -> %s\n' "$(readlink ~/.config/niri || echo 'REAL DIRECTORY (link was skipped)')"
ls ~/.config/niri/ 2>/dev/null | head -4 | sed 's/^/    /'
line "dotfiles checkout"
ls -d ~/Work/* 2>/dev/null | sed 's/^/  /'
line "packages"
rpm -q niri quickshell uwsm xwayland-satellite python3-pyxdg 2>&1 | sed 's/^/  /'
line "tty / session"
printf '  tty=%s  XDG_VTNR=%s  XDG_SESSION_TYPE=%s\n' "$(tty)" "${XDG_VTNR:-unset}" "${XDG_SESSION_TYPE:-unset}"
line "password state"
printf '  marker: %s\n' "$([ -e ~/.local/state/password-changed ] && echo present || echo absent)"
sudo -n passwd -S "$USER" 2>/dev/null | sed 's/^/  /' || printf '  (needs sudo to read passwd -S)\n'
line "fonts: what the configs name vs what resolves"
for f in "NotoSansM Nerd Font" "Symbols Nerd Font" "Inter Variable" "Noto Sans Mono"; do
    printf '  %-22s -> %s\n' "$f" "$(fc-match "$f" 2>/dev/null)"
done
line "font files installed"
ls /usr/local/share/fonts/*/ 2>/dev/null | sed 's/^/  /'
