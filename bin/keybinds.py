#!/usr/bin/env python3
"""
keybinds.py - the keybindings of whichever compositor is running, as JSON

Usage:  bin/keybinds.py

Written for quickshell/Keybinds.qml, which draws them. The point of reading them
rather than keeping a list is that a cheatsheet which drifts from the config is
worse than none: it teaches keys that do not work.

NIRI HAS NO IPC FOR THIS. `niri msg` can list outputs, workspaces, windows and
layers, and cannot list binds - so the source is this repository's own niri/*.kdl
files, which are the config niri loaded. Hyprland does have one, `hyprctl binds
-j`, so that is used there and nothing is parsed.

GROUPS COME FROM THE SECTION COMMENTS already in those files - the `// --- name
---` lines - so the panel's grouping and the config's own organisation cannot
disagree. A bind before any section comment is grouped by its file.
"""

import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Files in the order their binds should be shown.
NIRI_FILES = ("binds.kdl", "apps.kdl")

FILE_GROUPS = {"binds.kdl": "Bar", "apps.kdl": "Windows"}

SECTION = re.compile(r"^\s*//\s*-{2,}\s*(.+?)\s*-{2,}\s*$")
# A bind line: the key combo, optional flags, then the action up to the brace.
BIND = re.compile(
    r"""^\s*
        (?P<key>[A-Za-z0-9+_]+)          # Mod+Shift+Comma, XF86AudioPlay
        # QUOTED VALUES MUST BE ALLOWED HERE. With \S+ the pattern stopped at the
        # first space inside hotkey-overlay-title="Brightness up", the brace then
        # failed to match, and every titled bind was dropped - which is most of
        # the interesting ones.
        (?P<flags>(?:\s+[a-z-]+=(?:"[^"]*"|\S+))*)
        \s*\{\s*
        (?P<action>[^}]*?)
        \s*;?\s*\}\s*$""",
    re.VERBOSE,
)
TITLE = re.compile(r'hotkey-overlay-title="([^"]*)"')


def pretty(action: str) -> str:
    """Turn a niri action into something worth reading on a cheatsheet."""
    action = action.strip().rstrip(";").strip()

    # The bar's own panels, reached over IPC: `spawn "qs" "ipc" "call" "x" "y"`.
    ipc = re.match(r'spawn(?:-sh)?\s+"qs"\s+"ipc"\s+"call"\s+"([^"]+)"\s+"([^"]+)"', action)
    if ipc:
        target, fn = ipc.groups()
        return target.capitalize() if fn == "toggle" else f"{target.capitalize()} {fn}"

    # A command, named by the command rather than by its whole line.
    m = re.match(r'spawn-sh\s+"(.+)"$', action) or re.match(r'spawn\s+"([^"]+)"', action)
    if m:
        cmd = m.group(1)
        # the interesting part of a path, and nothing after the first flag
        first = cmd.split("&&")[0].strip().split()[0]
        name = os.path.basename(first)
        if name == "qs":
            return cmd
        return name

    # focus-workspace "3" -> Workspace 3; focus-column-left -> Focus column left
    ws = re.match(r'(focus|move-column-to)-workspace\s+"(\d+)"', action)
    if ws:
        verb = "Workspace" if ws.group(1) == "focus" else "Move to workspace"
        return f"{verb} {ws.group(2)}"

    return action.replace("-", " ").strip().capitalize()


def from_niri() -> list:
    """Read the binds out of this repository's niri config files.

    INSIDE THE `binds {}` BLOCK ONLY, tracked by brace depth. Two earlier
    versions got this wrong in opposite directions: the first matched one line at
    a time and silently dropped every bind whose body spans lines - which lost
    brightness and volume entirely - and the second treated any line ending in an
    open brace as a bind, so `binds {` itself started a bind and swallowed the
    section comments and the first few entries after it.
    """
    out = []
    for fname in NIRI_FILES:
        path = os.path.join(REPO, "niri", fname)
        if not os.path.exists(path):
            continue
        group = FILE_GROUPS.get(fname, fname)
        in_binds = False
        depth = 0           # brace depth inside the binds block
        pending = ""
        with open(path) as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                stripped = line.strip()

                if not in_binds:
                    if re.match(r"^binds\s*\{", stripped):
                        in_binds = True
                    continue

                if pending:
                    pending += " " + stripped
                    depth += stripped.count("{") - stripped.count("}")
                    if depth > 0:
                        continue
                    line, pending = pending, ""
                else:
                    sec = SECTION.match(line)
                    if sec:
                        group = sec.group(1).split(",")[0].strip()
                        group = group[0].upper() + group[1:]
                        continue
                    if stripped.startswith("//") or not stripped:
                        continue
                    if stripped == "}":
                        in_binds = False      # end of the binds block
                        continue
                    opens = stripped.count("{") - stripped.count("}")
                    if opens > 0:
                        pending, depth = stripped, opens
                        continue

                m = BIND.match(line)
                if not m:
                    continue
                action = m.group("action")
                title = TITLE.search(m.group("flags") or "")
                out.append({
                    "group": group,
                    "key": m.group("key"),
                    "label": title.group(1) if title else pretty(action),
                })
    return out


MODS = [(1, "Shift"), (8, "Mod"), (64, "Super"), (4, "Ctrl"), (16, "Alt")]


def from_hyprland() -> list:
    try:
        raw = subprocess.run(["hyprctl", "binds", "-j"], capture_output=True,
                             text=True, timeout=5, check=True).stdout
        binds = json.loads(raw)
    except Exception:
        return []
    out = []
    for b in binds:
        mask = b.get("modmask", 0)
        parts = [name for bit, name in MODS if mask & bit]
        key = "+".join(parts + [b.get("key") or ""])
        arg = (b.get("arg") or "").strip()
        label = pretty(arg) if arg else (b.get("dispatcher") or "")
        out.append({"group": "Hyprland", "key": key, "label": label})
    return out


def collapse(binds: list) -> list:
    """Fold a run of numbered binds into one line.

    Nine lines reading "Super+1  Workspace 1" down to "Super+9  Workspace 9"
    teach nothing the first line does not, and on a cheatsheet they are most of
    the page: eighteen of fifty-nine entries, enough to set the height of a whole
    column and leave the next one empty.

    A run is collapsed when consecutive binds differ ONLY by a trailing digit, in
    both the key and the label. Anything else is left exactly as it is - this must
    not quietly merge two binds that happen to look similar.
    """
    out = []
    run = []

    def flush():
        if not run:
            return
        if len(run) < 3:
            out.extend(run)
        else:
            first, last = run[0], run[-1]
            kf, kl = first["key"][:-1], first["key"][-1]
            out.append({
                "group": first["group"],
                "key": f"{kf}{kl}\u2026{last['key'][-1]}",
                "label": re.sub(r"\s*\d+$", "", first["label"])
                         + f" {first['label'].split()[-1]}\u2013{last['label'].split()[-1]}",
            })
        run.clear()

    for b in binds:
        if run:
            prev = run[-1]
            same_shape = (
                b["group"] == prev["group"]
                and b["key"][:-1] == prev["key"][:-1]
                and b["key"][-1:].isdigit() and prev["key"][-1:].isdigit()
                and int(b["key"][-1]) == int(prev["key"][-1]) + 1
                and re.sub(r"\d+$", "", b["label"]) == re.sub(r"\d+$", "", prev["label"])
            )
            if same_shape:
                run.append(b)
                continue
            flush()
        if b["key"][-1:].isdigit() and b["label"][-1:].isdigit():
            run.append(b)
        else:
            out.append(b)
    flush()
    return out


def from_tmux() -> list:
    """tmux's own keys, and the shell helpers that get you into a session.

    READ, NOT LISTED. The binds come from tmux/tmux.conf in this repository -
    the same file tmux itself reads - so a key renamed there is renamed here.
    The shell helpers come from the usage block at the top of
    bashrc.d/tmux.sh, which is the text their own file already carries:

        #   tls          what is running, and which session you are in

    A cheatsheet written by hand drifts from what it describes, and one that
    names keys which do not exist is worse than having none. That rule is why
    this file parses niri's config rather than enumerating it, and it applies
    no less to tmux.

    tmux's ~200 DEFAULT bindings are deliberately not included. They are not
    what anyone needs reminding of, and they would bury the handful that this
    configuration actually changes.
    """
    binds = []

    conf = os.path.join(REPO, "tmux", "tmux.conf")
    if os.path.isfile(conf):
        prefix = "Ctrl+B"
        for line in open(conf, encoding="utf-8", errors="replace"):
            m = re.match(r"^\s*bind\s+(-n\s+)?(-r\s+)?(\S+)\s+(.+?)\s*$", line)
            if not m:
                continue
            no_prefix, _repeat, key, action = m.groups()
            # -n means "no prefix": the key works on its own. Anything else
            # needs the prefix first, and saying so is most of the value.
            shown = tmux_key(key) if no_prefix else f"{prefix} {tmux_key(key)}"
            binds.append({"group": "tmux", "key": shown, "label": pretty_tmux(action)})

    helpers = os.path.join(REPO, "bashrc.d", "tmux.sh")
    if os.path.isfile(helpers):
        for line in open(helpers, encoding="utf-8", errors="replace"):
            if not line.startswith("#"):
                break                      # the usage block is the header only
            m = re.match(r"^#\s{3}(\S+)(?:\s+(\[[^\]]+\]))?\s{2,}(.+?)\s*$", line)
            if m:
                name, arg, label = m.groups()
                binds.append({
                    "group": "tmux in the shell",
                    "key": f"{name} {arg}" if arg else name,
                    "label": label,
                })
    return binds


def tmux_key(key: str) -> str:
    """M-Left -> Alt+Left, C-x -> Ctrl+X, the way the rest of the panel reads."""
    out = key
    for short, long in (("M-", "Alt+"), ("C-", "Ctrl+"), ("S-", "Shift+")):
        out = out.replace(short, long)
    head, _, tail = out.rpartition("+")
    return f"{head}+{tail.capitalize()}" if head and len(tail) == 1 else out


def pretty_tmux(action: str) -> str:
    """`select-window -t :=3` -> "Window 3". Same job as pretty() for niri."""
    action = action.strip()
    m = re.match(r"select-window\s+-t\s+:=(\d+)", action)
    if m:
        return f"Window {m.group(1)}"
    words = action.split()[0].replace("-", " ")
    return words[:1].upper() + words[1:]


def main() -> int:
    if os.environ.get("NIRI_SOCKET"):
        binds = from_niri()
    elif os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        binds = from_hyprland()
    else:
        binds = from_niri() or from_hyprland()
    # tmux is not a compositor bind, so it is appended rather than collapsed
    # with them - collapse() merges keys that run the same action, which is
    # meaningless across two different programs.
    binds = collapse(binds) + from_tmux()
    json.dump(binds, sys.stdout, indent=1)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
