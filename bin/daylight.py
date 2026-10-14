#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A different wallpaper through the day, and the palette by the sun.

    bin/daylight.py            change the wallpaper if one is due
    bin/daylight.py --now      change it regardless, and restart the hour
    bin/daylight.py --status   what it thinks, and when it changes next
    bin/daylight.py --dry-run  say what it would do

THE WALLPAPER IS RANDOM, ON A CLOCK. One is picked at random every
interval_minutes (an hour by default), so the desktop moves through the whole
collection instead of showing the same four pictures it always did.

AT NIGHT IT PICKS FROM THE DARKER HALF ONLY. Unconstrained random puts a
249-luminance picture on screen at two in the morning, and a wallpaper that is
right at noon glares in a dark room - which is the fault the four fixed slots
were measured to fix, and not one worth reintroducing for the sake of being
random. Day picks from all 63; night picks from the darker half by measured
luminance. "Night" is the sun's, not the clock's.

MEASURED ONCE AND CACHED. dwebp decodes each wallpaper to 64x36 and the average
luminance is kept in the cache, keyed by size and mtime, so the measuring pass
happens the first time and never again until a file changes. With no dwebp the
night restriction is skipped rather than guessed at, and it says so.

THE SLOTS REMAIN, FOR THE PALETTE ONLY: morning around first light, day,
evening as it goes, night. Fixed hours would be two hours wrong between June and
December, which is the whole difficulty this is meant to answer.

  morning   sunrise - 30m  ->  sunrise + 2h
  day       sunrise + 2h   ->  sunset  - 90m
  evening   sunset  - 90m  ->  sunset  + 30m
  night     everything else

NO NETWORK, NO API KEY, NO GEOCLUE. Sunrise and sunset are arithmetic given a
date and a place, and the place comes from the timezone database: zone1970.tab
carries a latitude and longitude for every zone, so America/New_York answers
40.71, -74.01 without asking anyone. Set `latitude` and `longitude` in
daylight/slots.conf if you are not near the zone's city - a degree of longitude
is four minutes of sunrise.

A MANUAL CHOICE WINS FOR THE REST OF THE DAY. If the wallpaper or the theme is
not the one this last set, someone changed it on purpose and this stops
touching that thing until tomorrow. It is the rule bin/theme.sh already uses
for wallpapers, and the reason a stay-out-of-my-way feature is bearable at all.

IT WRITES THE SAME TWO THINGS ANYTHING ELSE WOULD: bin/wallpaper.sh set, and
bin/theme.sh set. No new mechanism, so the picker, SUPER+T and this cannot
disagree about what "the wallpaper" or "the theme" is.
"""

from __future__ import annotations

import argparse
import math
import random
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "daylight" / "slots.conf"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "fd44-hyprdot"
STATE = STATE_DIR / "daylight"
WALLPAPER_STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "wallpaper"

#: Where each slot begins, as an offset from sunrise or sunset.
SLOTS = [
    ("morning", "sunrise", -30),
    ("day",     "sunrise", +120),
    ("evening", "sunset",  -90),
    ("night",   "sunset",  +30),
]


# --- the sun -------------------------------------------------------------
#
# The NOAA sunrise equation, which is accurate to about a minute at these
# latitudes - far finer than a wallpaper needs, and the same arithmetic every
# almanac uses. -0.833 degrees is the standard solar altitude for "rise": half
# the sun's disc below the horizon plus the usual refraction.

def _julian(day: datetime) -> float:
    return day.timestamp() / 86400.0 + 2440587.5


def sun_times(when: datetime, lat: float, lon: float) -> tuple[datetime, datetime] | None:
    """Sunrise and sunset, in UTC, for the date of `when`. None above the circles."""
    midnight = when.astimezone(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    n = round(_julian(midnight) - 2451545.0 + 0.0008)
    noon = n - lon / 360.0
    M = (357.5291 + 0.98560028 * noon) % 360
    C = (1.9148 * math.sin(math.radians(M))
         + 0.0200 * math.sin(math.radians(2 * M))
         + 0.0003 * math.sin(math.radians(3 * M)))
    lam = (M + C + 180 + 102.9372) % 360
    transit = (2451545.0 + noon + 0.0053 * math.sin(math.radians(M))
               - 0.0069 * math.sin(math.radians(2 * lam)))
    declination = math.asin(math.sin(math.radians(lam)) * math.sin(math.radians(23.44)))
    try:
        omega = math.acos(
            (math.sin(math.radians(-0.833)) - math.sin(math.radians(lat)) * math.sin(declination))
            / (math.cos(math.radians(lat)) * math.cos(declination)))
    except ValueError:
        return None                      # the sun neither rises nor sets today
    rise = transit - math.degrees(omega) / 360.0
    sett = transit + math.degrees(omega) / 360.0
    to_dt = lambda j: datetime.fromtimestamp((j - 2440587.5) * 86400.0, tz=timezone.utc)
    return to_dt(rise), to_dt(sett)


def zone_coordinates() -> tuple[float, float] | None:
    """Latitude and longitude for this machine's timezone, from tzdata."""
    zone = subprocess.run(["timedatectl", "show", "-p", "Timezone", "--value"],
                          capture_output=True, text=True).stdout.strip()
    # WHERE zone1970.tab LIVES DEPENDS ON THE DISTRIBUTION, and getting this
    # wrong is silent: no location, no sunrise, and the service exits 2 with
    # "set latitude and longitude" - which reads like the config is at fault
    # when the config is fine.
    #
    #   /usr/share/zoneinfo/zone1970.tab   Fedora, Debian, Arch, Gentoo
    #   /etc/zoneinfo/zone1970.tab         NixOS - a symlink into the store,
    #                                      where the path carries a hash and so
    #                                      cannot be hardcoded
    #
    # Found on framework00 the day it was installed: every other machine this
    # repository builds is FHS, so the first NixOS one was the first to fail.
    table = next((t for t in (Path("/usr/share/zoneinfo/zone1970.tab"),
                              Path("/etc/zoneinfo/zone1970.tab"))
                  if t.exists()), None)
    if not zone or table is None:
        return None
    for line in table.read_text().splitlines():
        if line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3 or zone not in parts[2].split(","):
            continue
        # +404251-0740023 -> 40 42' 51" N, 74 00' 23" W
        m = re.match(r"([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$", parts[1])
        if not m:
            return None
        lat = int(m[1]) + math.copysign(int(m[2]) / 60 + int(m[3] or 0) / 3600, int(m[1]) or 1)
        lon = int(m[4]) + math.copysign(int(m[5]) / 60 + int(m[6] or 0) / 3600, int(m[4]) or 1)
        return lat, lon
    return None


# --- configuration and state ---------------------------------------------

def read_kv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip()
    return out


def write_state(values: dict[str, str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE.write_text("".join(f"{k}={v}\n" for k, v in values.items()))


def current_wallpaper() -> str:
    try:
        return Path(WALLPAPER_STATE.read_text().strip()).name
    except OSError:
        return ""


def current_theme() -> str:
    result = subprocess.run([str(REPO / "bin" / "theme.sh"), "current"],
                            capture_output=True, text=True)
    return result.stdout.strip()


# --- what time it is -----------------------------------------------------

WALLPAPERS = REPO / "wallpapers"
LUM_CACHE = (Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
             / "fd44-hyprdot" / "wallpaper-luminance")


def wallpaper_files() -> list[Path]:
    return sorted(WALLPAPERS.glob("*.webp"))


def measure(path: Path) -> float | None:
    """Average luminance 0-255, or None if it cannot be read.

    64x36 IS ENOUGH AND 4K IS NOT FREE. What is wanted is one number for the
    whole picture, and dwebp will scale while it decodes, so the full image is
    never held. The weights are the usual perceptual ones rather than a plain
    mean, because green reads as brighter than blue at the same value.
    """
    try:
        r = subprocess.run(["dwebp", "-quiet", "-scale", "64", "36", "-pam",
                            str(path), "-o", "-"], capture_output=True)
    except FileNotFoundError:
        return None
    if r.returncode != 0 or not r.stdout:
        return None
    data = r.stdout
    marker = data.find(b"ENDHDR\n")
    if marker < 0:
        return None
    head = data[:marker].decode("ascii", "replace")
    depth = 4
    for line in head.splitlines():
        if line.startswith("DEPTH"):
            depth = int(line.split()[1])
    px = data[marker + 7:]
    count = len(px) // depth
    if count == 0:
        return None
    total = 0
    for i in range(count):
        o = i * depth
        total += (px[o] * 299 + px[o + 1] * 587 + px[o + 2] * 114) // 1000
    return total / count


def luminances() -> dict[str, float]:
    """Every wallpaper's brightness, measuring only what has changed.

    The cache key is size and mtime, so replacing a file with a different
    picture under the same name is noticed; touching one is not enough to force
    a remeasure, and nor should it be.
    """
    cached: dict[str, tuple[str, float]] = {}
    if LUM_CACHE.exists():
        for line in LUM_CACHE.read_text().splitlines():
            parts = line.split("\t")
            if len(parts) == 3:
                try:
                    cached[parts[0]] = (parts[1], float(parts[2]))
                except ValueError:
                    pass

    out: dict[str, float] = {}
    fresh: dict[str, tuple[str, float]] = {}
    changed = False
    for f in wallpaper_files():
        try:
            st = f.stat()
        except OSError:
            continue
        stamp = f"{st.st_size}:{int(st.st_mtime)}"
        hit = cached.get(f.name)
        if hit and hit[0] == stamp:
            out[f.name] = hit[1]
            fresh[f.name] = hit
            continue
        value = measure(f)
        changed = True
        if value is None:
            continue
        out[f.name] = value
        fresh[f.name] = (stamp, value)

    if changed or len(fresh) != len(cached):
        try:
            LUM_CACHE.parent.mkdir(parents=True, exist_ok=True)
            LUM_CACHE.write_text(
                "".join(f"{n}\t{v[0]}\t{v[1]:.2f}\n" for n, v in sorted(fresh.items())))
        except OSError:
            pass
    return out


def choose_wallpaper(night: bool, avoid: str) -> tuple[str, str]:
    """A random wallpaper, and one line saying how it was narrowed down.

    THE ONE ON SCREEN IS EXCLUDED so that a change is always a change. With a
    single candidate that exclusion would leave nothing, so it only applies
    while there is something else to pick.
    """
    files = [f.name for f in wallpaper_files()]
    if not files:
        return "", "no wallpapers in wallpapers/"

    pool, how = files, f"all {len(files)}"
    if night:
        lum = luminances()
        rated = sorted((v, n) for n, v in lum.items() if n in files)
        if len(rated) >= 4:
            half = rated[: len(rated) // 2]
            pool = [n for _v, n in half]
            how = f"the darker half, {len(pool)} of {len(rated)} under {half[-1][0]:.0f}"
        elif not lum:
            how = f"all {len(files)} - no dwebp, so brightness is unknown"

    options = [n for n in pool if n != avoid] or pool
    return random.choice(options), how


def slot_for(now: datetime, rise: datetime, sett: datetime) -> tuple[str, datetime]:
    """The slot `now` falls in, and when the next one starts."""
    edges = []
    for name, anchor, offset in SLOTS:
        base = rise if anchor == "sunrise" else sett
        edges.append((base + timedelta(minutes=offset), name))
    edges.sort()
    current = edges[-1][1]               # before the first edge it is still night
    following = edges[0][0]
    for at, name in edges:
        if now >= at:
            current = name
        else:
            following = at
            break
    else:
        following = edges[0][0] + timedelta(days=1)
    return current, following


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true")
    # NOT THE SAME AS WAITING. --now is for wanting a different picture this
    # second, so it overrules the interval AND a manual choice: asking for one
    # by hand is itself the choice, and refusing on the grounds that you chose
    # something earlier would be the script arguing with you.
    parser.add_argument("--now", action="store_true",
                        help="change the wallpaper regardless of the interval")
    parser.add_argument("--status", action="store_true")
    args = parser.parse_args()

    config = read_kv(CONFIG)
    coords = None
    if "latitude" in config and "longitude" in config:
        coords = (float(config["latitude"]), float(config["longitude"]))
    else:
        coords = zone_coordinates()
    if not coords:
        print("daylight: no location - set latitude and longitude in daylight/slots.conf",
              file=sys.stderr)
        return 2
    lat, lon = coords

    now = datetime.now(timezone.utc)
    times = sun_times(now, lat, lon)
    if not times:
        print("daylight: the sun does not rise or set here today - nothing to do")
        return 0
    rise, sett = times
    slot, following = slot_for(now, rise, sett)

    theme = config.get(f"{slot}_theme", "")
    state = read_kv(STATE)
    today = now.astimezone().strftime("%Y-%m-%d")
    same_day = state.get("date") == today

    # WHETHER A CHANGE IS DUE IS THE SCRIPT'S TO DECIDE, not the timer's. The
    # unit may fire early, late, twice, or not at all across a suspend, and
    # --dry-run must not consume a turn. Keeping the last change in the state
    # file makes every one of those cases the same question: how long has it
    # been?
    try:
        interval = max(1, int(config.get("interval_minutes", "60")))
    except ValueError:
        interval = 60
    last = state.get("wallpaper_at", "")
    minutes_since = None
    if last:
        try:
            minutes_since = (now - datetime.fromisoformat(last)).total_seconds() / 60
        except ValueError:
            minutes_since = None
    due = args.now or minutes_since is None or minutes_since >= interval

    on_screen = current_wallpaper()
    wallpaper, narrowed = ("", "")
    if due:
        wallpaper, narrowed = choose_wallpaper(slot == "night", Path(on_screen).name)

    if args.status or args.dry_run:
        local = lambda d: d.astimezone().strftime("%H:%M")
        print(f"  location      {lat:.2f}, {lon:.2f}")
        print(f"  sunrise       {local(rise)}")
        print(f"  sunset        {local(sett)}")
        print(f"  slot          {slot}")
        print(f"  next slot at  {local(following)}")
        print(f"  every         {interval} minutes")
        if minutes_since is None:
            print("  last change   never")
        else:
            print(f"  last change   {minutes_since:.0f} minutes ago"
                  + ("" if due else f", next in {interval - minutes_since:.0f}"))
        print(f"  picking from  {narrowed or ('the darker half at night' if slot == 'night' else 'all of them')}")
        print(f"  wallpaper     {wallpaper or '(not due yet)'}")
        print(f"  theme         {theme or '(none set for this slot)'}")
        if same_day:
            print(f"  last set      wallpaper={state.get('wallpaper','-')} theme={state.get('theme','-')}")

    # A manual change wins until tomorrow - per thing, so picking a wallpaper
    # does not also stop the theme following the sun.
    wallpaper_overridden = (not args.now) and same_day and state.get("wallpaper") not in ("", None, current_wallpaper())
    theme_overridden = same_day and state.get("theme") not in ("", None, current_theme())

    actions: list[tuple[str, list[str]]] = []
    if wallpaper and not wallpaper_overridden and Path(on_screen).name != wallpaper:
        actions.append(("wallpaper", [str(REPO / "bin" / "wallpaper.sh"), "set",
                                      str(REPO / "wallpapers" / wallpaper)]))
    if theme and not theme_overridden and current_theme() != theme:
        actions.append(("theme", [str(REPO / "bin" / "theme.sh"), "set", theme]))

    if args.status:
        for what, flag in (("wallpaper", wallpaper_overridden), ("theme", theme_overridden)):
            if flag:
                print(f"  {what}: changed by hand today - leaving it alone until tomorrow")
        return 0

    for what, command in actions:
        if args.dry_run:
            print(f"  would set {what}: {' '.join(command[1:])}")
            continue
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"daylight: {what} failed: {result.stderr.strip()}", file=sys.stderr)
            return 1
        print(f"  {what} -> {command[-1].split('/')[-1]}")

    if not args.dry_run:
        changed_now = any(what == "wallpaper" for what, _ in actions)
        write_state({
            "date": today,
            "slot": slot,
            # The clock only restarts when a wallpaper actually went up. A run
            # that was blocked by a manual choice has not had its turn.
            "wallpaper_at": now.isoformat(timespec="seconds") if changed_now
                            else state.get("wallpaper_at", ""),
            # What WE set, so anything else becomes evidence of a manual change.
            "wallpaper": wallpaper if wallpaper and not wallpaper_overridden else state.get("wallpaper", ""),
            "theme": theme if theme and not theme_overridden else state.get("theme", ""),
        })
    return 0


if __name__ == "__main__":
    sys.exit(main())
