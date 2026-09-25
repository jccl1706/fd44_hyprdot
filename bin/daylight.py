#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Follow the sun: wallpaper, and the palette with it.

    bin/daylight.py            apply whatever the hour calls for
    bin/daylight.py --status   what it thinks, and when it changes next
    bin/daylight.py --dry-run  say what it would do

FOUR SLOTS, ANCHORED TO SUNRISE AND SUNSET rather than to the clock: morning
around first light, day, evening as it goes, night. Fixed hours would be two
hours wrong between June and December, which is the whole difficulty this is
meant to answer.

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
    table = Path("/usr/share/zoneinfo/zone1970.tab")
    if not zone or not table.exists():
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

    wallpaper = config.get(f"{slot}_wallpaper", "")
    theme = config.get(f"{slot}_theme", "")
    state = read_kv(STATE)
    today = now.astimezone().strftime("%Y-%m-%d")
    same_day = state.get("date") == today

    if args.status or args.dry_run:
        local = lambda d: d.astimezone().strftime("%H:%M")
        print(f"  location      {lat:.2f}, {lon:.2f}")
        print(f"  sunrise       {local(rise)}")
        print(f"  sunset        {local(sett)}")
        print(f"  slot          {slot}")
        print(f"  next slot at  {local(following)}")
        print(f"  wallpaper     {wallpaper or '(none set for this slot)'}")
        print(f"  theme         {theme or '(none set for this slot)'}")
        if same_day:
            print(f"  last set      wallpaper={state.get('wallpaper','-')} theme={state.get('theme','-')}")

    # A manual change wins until tomorrow - per thing, so picking a wallpaper
    # does not also stop the theme following the sun.
    wallpaper_overridden = same_day and state.get("wallpaper") not in ("", None, current_wallpaper())
    theme_overridden = same_day and state.get("theme") not in ("", None, current_theme())

    actions: list[tuple[str, list[str]]] = []
    if wallpaper and not wallpaper_overridden and current_wallpaper() != wallpaper:
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
        write_state({
            "date": today,
            "slot": slot,
            # What WE set, so anything else becomes evidence of a manual change.
            "wallpaper": wallpaper if wallpaper and not wallpaper_overridden else state.get("wallpaper", ""),
            "theme": theme if theme and not theme_overridden else state.get("theme", ""),
        })
    return 0


if __name__ == "__main__":
    sys.exit(main())
