#!/usr/bin/env python3
# =========================================================================
# updates.py - what is waiting to be installed, and the screen that installs it
# =========================================================================
#
# Usage:  bin/updates.py status    the cached answer as JSON, for the bar
#         bin/updates.py check     ask the package manager now, rewrite the cache
#         bin/updates.py show      the pending-upgrades screen
#         bin/updates.py open      that screen, in its own terminal window
#
# The bar's update box (quickshell/Updates.qml) calls `status` on a timer and
# `open` when clicked. Everything distro-specific lives here rather than in QML,
# so the shell asks one question and gets one answer on all three machines.
#
# WHAT "PENDING" MEANS IS NOT THE SAME EVERYWHERE, and pretending otherwise
# would make the icon lie on two of them:
#
#   Fedora   dnf has a real list of newer packages. The count is that list.
#
#   Gentoo   emerge has one too, but asking costs SECONDS - it resolves the whole
#            dependency graph and asks the binhost about every package in it.
#
#   NixOS    nothing is "pending" in that sense: the system is whatever the flake
#            evaluates to. What can be behind is the nixpkgs revision pinned in
#            flake.lock, so the question asked is whether upstream has moved past
#            the pin, and the count is how many DAYS behind it is. One network
#            call, no evaluation and no building - this runs on a timer and must
#            not pull down store paths to answer.
#
# SO EVERY ANSWER IS CACHED, not only Gentoo's. `status` reads the cache and
# refreshes behind itself when it is stale; the bar therefore never waits on a
# package manager, and a click never lands mid-resolve.
#
# PYTHON, WHICH THE NIXOS MACHINE DOES NOT HAVE BY DEFAULT. The bash version this
# replaces parsed JSON with `nix eval` precisely because of that. If the box reads
# "unknown" there, python3 is missing from that system's configuration - see
# fd44_nixos, which now carries it.

import json
import os
import re
import shutil
import subprocess
import sys
import time

CACHE = os.path.expanduser("~/.cache/updates/list.json")
MAX_AGE = 3600                      # an hour; the tree rarely moves faster

# The terminal's own palette draws this - ANSI indices only, never hex - so it
# follows bin/theme.sh between dark and cream with nothing to regenerate. The
# same rule as starship/starship.toml.
B, DIM, ACC, OK, WARN, R = "\033[1m", "\033[2m", "\033[1;34m", "\033[32m", "\033[1;33m", "\033[0m"

GLYPH = "\U000F03D7"                # nf-md-package_variant_closed, the bar's own
ARROW = "→"
ELLIPSIS = "…"
RULE = "─"

HERE = os.path.dirname(os.path.abspath(__file__))


def run(cmd, **kw):
    """A command, its output, and never an exception for a non-zero exit."""
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def distro():
    try:
        with open("/etc/os-release") as f:
            # ID may be bare, double-quoted or single-quoted: Fedora writes
            # ID=fedora, NixOS ID="nixos" and Gentoo ID='gentoo'. Logo.qml was
            # caught by exactly this.
            for line in f:
                if line.startswith("ID="):
                    return line[3:].strip().strip("\"'").lower()
    except OSError:
        pass
    return ""


# --- Fedora ---------------------------------------------------------------

def check_dnf():
    # --refresh matters more than it sounds. A `dnf upgrade` run against a cache
    # from earlier in the day silently skips a package built since - watched that
    # happen with quickshell, where root's cache was 13 minutes older than the
    # build. An icon fed by a stale cache would be worse: it would say "nothing
    # to do" while something waited.
    r = run(["dnf", "-q", "--refresh", "check-update"])
    # 100 is dnf's "there are updates", 0 is "none". Anything else is a failure -
    # no network, a broken repo - and must not read as zero.
    if r.returncode not in (0, 100):
        raise RuntimeError((r.stderr or r.stdout).strip().splitlines()[-1:] or ["dnf failed"])

    # ONE rpm CALL, NOT ONE PER PACKAGE: the installed version has to come from
    # rpm because check-update prints only what is available, and 193 packages
    # meant 193 forks. %{EVR} carries the epoch, without which vim read as
    # "9.2.1129-1.fc44 -> 2:9.2.1129-1.fc44", an upgrade to itself.
    installed = {}
    for line in run(["rpm", "-qa", "--qf", "%{NAME}=%{EVR}\n"]).stdout.splitlines():
        name, _, ver = line.partition("=")
        if name:
            installed[name] = ver

    out = []
    for line in r.stdout.splitlines():
        # Counting stops at "Obsoleting Packages": what follows is the same
        # transaction described a second way, and counting both made four
        # updates read as five.
        if line.startswith("Obsoleting"):
            break
        f = line.split()
        if len(f) != 3 or "." not in f[0]:
            continue
        name = f[0].rsplit(".", 1)[0]
        out.append({"name": name, "old": installed.get(name, ""), "new": f[1], "arch": ""})
    return out


# --- Gentoo ---------------------------------------------------------------

EMERGE_LINE = re.compile(r"^\[(?:binary|ebuild)\s+([^\]]*)\]\s+(\S+?)-(\d[^\s:]*)(?:::\S+)?(?:\s+\[([^\]]+)\])?")


def check_emerge():
    r = run(["emerge", "-puDN", "--with-bdeps=y", "--getbinpkg", "--color=n",
             "--quiet", "--nospinner", "@world"])
    out = []
    for line in r.stdout.splitlines():
        m = EMERGE_LINE.match(line)   # "[binary  U  ] sys-apps/systemd-259.9::gentoo [259.8::gentoo]"
        if not m:
            continue
        flags, atom, ver, old = m.groups()
        # U upgrade, D downgrade, N new dependency. R rebuilds are skipped: same
        # version, changed USE or a revdep - a bar that lit up for those would be
        # lit permanently on a source distribution, which is the same as off.
        if "U" not in flags and "D" not in flags and "N" not in flags:
            continue
        out.append({"name": atom,
                    # Which ones will COMPILE is the question this distribution
                    # raises and the others do not: ten binary packages are a
                    # minute, one source package can be an hour.
                    "arch": "binary" if line.startswith("[binary") else "source",
                    "old": (old or "").split("::")[0].split()[0] if old else "",
                    "new": ver})
    if r.returncode != 0 and not out:
        raise RuntimeError((r.stderr or r.stdout).strip().splitlines()[-1:] or ["emerge failed"])
    return out


def repo_synced():
    """Gentoo: when the Portage tree was last synced."""
    try:
        return os.path.getmtime("/var/db/repos/gentoo/metadata/timestamp.chk")
    except OSError:
        return 0


# --- NixOS ----------------------------------------------------------------

def nixos_dir():
    return os.environ.get("FD44_NIXOS_DIR", os.path.expanduser("~/Work/fd44_nixos"))


def check_nixos():
    """Not a list of packages - how far the pinned nixpkgs is behind its branch."""
    lock = os.path.join(nixos_dir(), "flake.lock")
    try:
        with open(lock) as f:
            j = json.load(f)
    except (OSError, ValueError):
        raise RuntimeError(f"no readable flake.lock at {lock}")

    node = j.get("nodes", {}).get("nixpkgs", {})
    locked = node.get("locked", {})
    orig = node.get("original", {})
    rev, when = locked.get("rev", ""), locked.get("lastModified", 0)
    if not rev:
        raise RuntimeError(f"no nixpkgs node in {lock}")
    owner = orig.get("owner", "NixOS")
    repo = orig.get("repo", "nixpkgs")
    ref = orig.get("ref", "nixos-unstable")

    # --refresh so the answer is today's tip and not a cached one. No evaluation
    # happens here and nothing is downloaded into the store.
    r = run(["nix", "flake", "metadata", "--refresh", "--json", f"github:{owner}/{repo}/{ref}"])
    if r.returncode != 0 or not r.stdout.strip():
        raise RuntimeError(f"could not reach github:{owner}/{repo}/{ref}")
    m = json.loads(r.stdout)
    up_rev = m.get("revision") or m.get("locked", {}).get("rev", "")
    up_when = m.get("lastModified") or m.get("locked", {}).get("lastModified", 0)
    if not up_rev:
        raise RuntimeError("could not read flake metadata")
    if up_rev == rev:
        return []
    days = max(1, int((up_when - when) // 86400))
    # One row, and the count is days rather than packages - see the header.
    return [{"name": f"nixpkgs ({ref})", "old": rev[:7], "new": up_rev[:7],
             "arch": "", "days": days}]


# --- the cache ------------------------------------------------------------

def load():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(data):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".new"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, CACHE)          # never half a file for a reader


CHECKERS = {"fedora": ("dnf", check_dnf), "gentoo": ("emerge", check_emerge),
            "nixos": ("nix", check_nixos)}


def check():
    """Ask the package manager and write the cache. Returns the cache document."""
    d = distro()
    if d not in CHECKERS:
        data = {"time": time.time(), "distro": d, "kind": "unknown",
                "items": [], "error": f"unsupported distro: {d or 'unknown'}"}
        save(data)
        return data
    kind, fn = CHECKERS[d]
    try:
        items = fn()
        data = {"time": time.time(), "distro": d, "kind": kind, "items": items, "error": ""}
    except Exception as e:                      # offline, broken repo, missing tool
        msg = e.args[0] if e.args else str(e)
        data = {"time": time.time(), "distro": d, "kind": kind, "items": [],
                "error": msg if isinstance(msg, str) else " ".join(map(str, msg))}
    save(data)
    return data


def count_of(data):
    items = data.get("items", [])
    # NixOS counts days behind, not packages.
    if items and "days" in items[0]:
        return items[0]["days"]
    return len(items)


def status():
    """What the bar reads. Answers from the cache; refreshes behind itself."""
    data = load()
    stale = time.time() - data.get("time", 0) > MAX_AGE
    if distro() == "gentoo" and repo_synced() > data.get("time", 0):
        stale = True                            # a tree synced since the last check
    if stale:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "check"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    if not data:
        # Nothing cached yet: -1 is "unknown", which the bar draws as nothing. An
        # icon that appears because a first check has not finished would be a
        # false alarm, the same as one that appears because the network dropped.
        print(json.dumps({"kind": "", "count": -1, "summary": "",
                          "error": "first check has not finished yet", "checked": 0}))
        return
    n = count_of(data)
    items = data.get("items", [])
    if items and "days" in items[0]:
        summary = f"nixpkgs {n} day{'' if n == 1 else 's'} behind " \
                  f"({items[0]['old']} {ARROW} {items[0]['new']})"
    else:
        names = [i["name"] for i in items[:3]]
        summary = ", ".join(names)
        if len(items) > 3:
            summary += f" and {len(items) - 3} more"
    print(json.dumps({"kind": data.get("kind", ""), "count": -1 if data.get("error") else n,
                      "summary": summary, "error": data.get("error", ""),
                      "checked": int(data.get("time", 0))}))


# --- the screen -----------------------------------------------------------

def rel_time(when):
    d = time.time() - (when or 0)
    if d < 90:
        return "just now"
    if d < 5400:
        return f"{int((d + 30) // 60)} min ago"
    return f"{int((d + 1800) // 3600)} h ago"


def rows(items, limit):
    """name  old version -> new version, in columns measured from what is shown."""
    shown = items[:limit]
    if not shown:
        return []
    namew = max(len(i["name"]) for i in shown)
    oldw = max(len(i["old"] or "new") for i in shown)
    out = []
    for i in shown:
        # Only Gentoo sets arch; on Fedora every package arrives built.
        tag = {"binary": f" {DIM}bin{R}", "source": f" {WARN}src{R}"}.get(i.get("arch", ""), "")
        out.append(f"  {B}{i['name']:<{namew}}{R} {DIM}{(i['old'] or 'new'):>{oldw}}{R} "
                   f"{OK}{ARROW}{R} {OK}{i['new']}{R}{tag}")
    return out


def getkey():
    """One key press, without waiting for Enter."""
    import termios
    import tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def upgrade_cmd(d):
    return {"fedora": "sudo dnf upgrade --refresh",
            "gentoo": "sudo emerge -avuDN --getbinpkg @world",
            "nixos": "nix flake update && nixos-rebuild switch"}.get(d, "")


def show():
    d = distro()
    data = load()
    if not data:
        print(f"\n  {DIM}asking {d or 'this machine'} what is pending...{R}")
        data = check()

    while True:
        items = data.get("items", [])
        n = count_of(data)
        cols = shutil.get_terminal_size((80, 24)).columns
        lines = shutil.get_terminal_size((80, 24)).lines
        body = max(3, lines - 9)     # header, rule, two key lines and the spacing

        print("\033[2J\033[H")
        if data.get("error"):
            print(f"  {ACC}{GLYPH}  Cannot say{R}  {DIM}checked {rel_time(data.get('time'))}{R}\n")
            print(f"  {WARN}{data['error']}{R}\n")
        elif not items:
            print(f"  {ACC}{GLYPH}  Nothing pending{R}  {DIM}checked {rel_time(data.get('time'))}{R}\n")
            print(f"  {DIM}everything installed is the newest this machine knows about{R}\n")
        else:
            unit = "day" if "days" in items[0] else "package"
            print(f"  {ACC}{GLYPH}  Pending upgrades{R}  "
                  f"{DIM}{n} {unit}(s) · checked {rel_time(data.get('time'))}{R}\n")
            for line in rows(items, body):
                print(line)
            if len(items) > body:
                print(f"  {DIM}{ELLIPSIS} and {len(items) - body} more - press l for the full list{R}")

        print(f"\n  {DIM}{RULE * min(72, max(20, cols - 6))}{R}\n")
        if items and not data.get("error"):
            print(f"  {OK}u{R} upgrade now  {DIM}({upgrade_cmd(d)}){R}")
            print(f"  {OK}l{R} full list    {OK}r{R} check again    {OK}q{R} / {OK}Esc{R} close")
        else:
            print(f"  {OK}r{R} check again    {OK}q{R} / {OK}Esc{R} close")

        # NOT JUST OSError: termios.error is its own class, so a `show` run
        # where stdin is not a terminal - a script, a pipe - printed a traceback
        # instead of simply not being interactive. And a read at EOF returns "",
        # which matched no key below and spun this loop at full tilt.
        try:
            key = getkey()
        except Exception:
            return
        if not key or key in ("q", "Q", "\x1b", "\x03", "\x04"):
            return
        if key in ("r", "R"):
            print(f"\n  {DIM}checking...{R}")
            data = check()
        elif key in ("l", "L") and items:
            full_list(items)
        elif key in ("u", "U") and items and not data.get("error"):
            print("\033[2J\033[H")
            upgrade(d)
            print(f"\n  {DIM}done - any key for the list again{R} ", end="", flush=True)
            getkey()
            data = check()


def full_list(items):
    """Every row, through a pager so it can be scrolled back."""
    text = "\n".join([f"\n  {ACC}{GLYPH}  Pending upgrades, all of them{R}\n"]
                     + rows(items, len(items)) + [""])
    pager = os.environ.get("PAGER", "less")
    if not shutil.which(pager.split()[0]):
        pager = "cat"
    # -R and -X belong to less, so they go in $LESS where any other pager ignores
    # them rather than being handed flags it will reject.
    env = dict(os.environ, LESS="-R -X")
    try:
        subprocess.run(pager.split(), input=text, text=True, env=env)
    except OSError:
        print(text)


# --- doing the upgrade ----------------------------------------------------

def upgrade(d):
    if d == "fedora":
        # NOT -y, even though the list has been read on screen: dnf's own table is
        # the authoritative one - it knows about dependencies and obsoletes that a
        # list of upgradable packages does not - and its y/N is the last chance to
        # stop with those visible too.
        subprocess.run(["sudo", "dnf", "--refresh", "upgrade"])
    elif d == "gentoo":
        # --ask for the same reason; --keep-going because one package failing to
        # build should not abandon the other forty that would have succeeded.
        subprocess.run(["sudo", "emerge", "-avuDN", "--with-bdeps=y",
                        "--getbinpkg", "--keep-going", "@world"])
    elif d == "nixos":
        upgrade_nixos()


def upgrade_nixos():
    """Update the pin, build as the user, show the difference, then activate."""
    d = nixos_dir()
    if not os.path.isdir(d):
        print(f"  no NixOS flake at {d}")
        return
    host = os.uname().nodename
    before = locked_rev(d)
    print(f"{OK}==>{R} nixpkgs update for {host}\n")
    if subprocess.run(["nix", "flake", "update"], cwd=d).returncode != 0:
        print("  nix flake update failed")
        return
    after = locked_rev(d)
    subprocess.run(["git", "--no-pager", "diff", "--stat", "flake.lock"], cwd=d)

    # BUILD BEFORE ASKING. On NixOS there is no list of packages to print until
    # the new system has been evaluated - "what is upgrading" is the difference
    # between two closures and nothing can name it in advance. Building as your
    # own user also proves the configuration evaluates at all, so a broken flake
    # fails here rather than halfway through an activation.
    print(f"\n{OK}==>{R} Building the new system (no root needed)\n")
    r = run(["nix", "build", "--no-link", "--print-out-paths",
             f".#nixosConfigurations.{host}.config.system.build.toplevel"], cwd=d)
    if r.returncode != 0:
        print(f"  the build failed - nothing has been changed\n{r.stderr.strip()}")
        return
    new = r.stdout.strip().splitlines()[-1]

    print(f"\n{OK}==>{R} What would change\n")
    subprocess.run(["nix", "store", "diff-closures", "/run/current-system", new], cwd=d)

    print()
    try:
        reply = input("Activate this system? [y/N] ")
    except EOFError:
        reply = ""
    if reply.strip().lower() not in ("y", "yes"):
        print(f"\nleft alone - flake.lock has moved but nothing is activated.")
        print(f"  to undo that:  git -C {d} checkout flake.lock")
        return
    if subprocess.run(["sudo", "nixos-rebuild", "switch", "--flake", f".#{host}"], cwd=d).returncode != 0:
        print("  the switch failed - flake.lock is left in the working tree, uncommitted")
        return
    record_lock(d, before, after)


def locked_rev(d):
    try:
        with open(os.path.join(d, "flake.lock")) as f:
            return json.load(f)["nodes"]["nixpkgs"]["locked"]["rev"][:7]
    except Exception:
        return "-"


def record_lock(d, before, after):
    """Commit and push the lock, but only once the system is running it.

    A lock that has moved on disk while the repository still says otherwise is a
    machine nobody can rebuild from the repository - `git checkout flake.lock`
    would quietly put the old pin back and the next rebuild would undo the update.
    After the switch, because that is the point at which the new pin is known to
    work: a lock committed before activation could be a build that fails.
    """
    if run(["git", "-C", d, "diff", "--quiet", "--", "flake.lock"]).returncode == 0:
        print(f"{OK}==>{R} flake.lock unchanged - nothing to record")
        return
    print(f"\n{OK}==>{R} Recording the new pin in the repository")
    # ONLY flake.lock, by pathspec: whatever else is being worked on in that
    # checkout is not this script's business and must not end up in the commit.
    if run(["git", "-C", d, "commit", "-q", "-m", f"nixpkgs: {before} -> {after}",
            "--", "flake.lock"]).returncode != 0:
        print("  could not commit flake.lock - left in the working tree")
        return
    print("  committed: " + run(["git", "-C", d, "log", "--oneline", "-1"]).stdout.strip())
    if os.environ.get("FD44_UPDATES_NO_PUSH"):
        print("  not pushing (FD44_UPDATES_NO_PUSH is set)")
        return
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    if subprocess.run(["git", "-C", d, "push", "-q", "origin", "HEAD"],
                      env=env, capture_output=True).returncode == 0:
        print("  pushed")
    else:
        print("  PUSH FAILED - the commit is local. Retry with:")
        print(f"    git -C {d} push origin HEAD")


def open_terminal():
    # bin/in-terminal.sh owns the window: which terminal, and staying open
    # afterwards so the transcript can be read. bin/backup.sh opens its own the
    # same way.
    #
    # A LITTLE TRANSLUCENCY, because this window is a full screen of its own text
    # rather than a few lines of output - there is not much desktop left showing
    # through, and Hyprland blurs what there is. The other bar windows stay opaque;
    # see the note in in-terminal.sh.
    os.environ["FD44_TERM_OPACITY"] = os.environ.get("FD44_TERM_OPACITY", "0.88")
    os.execv(os.path.join(HERE, "in-terminal.sh"),
             [os.path.join(HERE, "in-terminal.sh"), "System update",
              os.path.abspath(__file__), "show"])


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        status()
    elif cmd == "check":
        check()
        status()
    elif cmd == "show":
        show()
    elif cmd == "open":
        open_terminal()
    elif cmd in ("-h", "--help", "help"):
        print(__doc__ or "usage: updates.py status|check|show|open")
    else:
        print(f"updates.py: unknown command: {cmd} (status, check, show, open)", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
