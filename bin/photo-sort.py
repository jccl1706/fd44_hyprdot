#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Sort a Google Photos Takeout into year/month folders.

    bin/photo-sort.py SOURCE                 what it would do, and nothing else
    bin/photo-sort.py SOURCE --apply         do it, writing a manifest
    bin/photo-sort.py --undo MANIFEST        put every file back where it was

WHAT IT IS FOR. A Takeout arrives as "Photos from 2015" ... "Photos from 2025",
which is the only grouping Google offers and is too coarse to find anything in:
one folder here holds a whole year. This moves each photo into YEAR/MONTH.

WHERE THE DATE COMES FROM, in order, because this is the whole problem:

  1. THE SIDECAR. Takeout ships <name>.<ext>.supplemental-metadata.json beside
     each file with photoTakenTime.timestamp - a UTC epoch, and the date Google
     itself believes. It is right even for the files that carry no date of
     their own, which here is every .mov, .mp and .png.
  2. THE FILENAME. IMG_20150830_130750.jpg, PXL_20211203_..., VID_..., and
     download_20150512_135415 all state a date. Used only when there is no
     sidecar, and only when it parses as a real date.
  3. NOTHING ELSE. In particular NOT the modification time: the export rewrote
     every one of them to the day it was downloaded, so mtime says 2025 for a
     photo from 2015. A file with no sidecar and no date in its name is left
     exactly where it is and listed at the end. Guessing would scatter files
     into the wrong months, which is worse than leaving them in one place.

WHAT MOVES WITH WHAT. A sidecar follows its media file, so nothing is orphaned.
"-edited" versions and Google's "(1)" duplicates inherit their original's date
even though they have no sidecar of their own, so an edit never lands in a
different month from the photo it came from.

NOTHING IS EVER DELETED OR OVERWRITTEN. A destination that already exists is
compared by size and, if that matches, by SHA-256: identical files are left
alone and reported, different ones get a -1, -2 suffix. Every move is written
to a manifest, and --undo replays it backwards.

SAME FILESYSTEM ONLY, unless --copy. A move within one filesystem is a rename:
instant, atomic, and needs no free space - which matters on a 2 TB disk with
49 GB left. Across filesystems it would be a copy and a delete, and this will
not do that silently.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

MEDIA = {".jpg", ".jpeg", ".png", ".heic", ".gif", ".webp", ".tif", ".tiff",
         ".mov", ".mp4", ".m4v", ".3gp", ".avi", ".mkv", ".mp", ".dng", ".raw"}

#: Google truncates the whole sidecar name to a fixed length, so the suffix
#: appears as .supplemental-metadata.json, .supplemental-met.json,
#: .supplemental-m.json and so on. Older exports use a bare .json.
SIDECAR_HINTS = ("supplemental", "metadata")

#: IMG_20150830_130750 / PXL_20211203_174512345 / VID_20190101_ / 20230115_
FILENAME_DATE = re.compile(r"(?<!\d)(20\d{2}|19\d{2})[-_]?(\d{2})[-_]?(\d{2})(?!\d)")

#: "IMG_1234(1).jpg" is Google's duplicate marker; "IMG_1234-edited.jpg" its
#: edit. Both belong with the original, whose sidecar carries the date.
DERIVED = re.compile(r"^(?P<stem>.+?)(?:\(\d+\))?(?:-edited|-EFFECTS|-ANIMATION)?$")


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while block := fh.read(chunk):
            h.update(block)
    return h.hexdigest()


def find_sidecar(media: Path) -> Path | None:
    """The JSON Takeout wrote for this file, under any of its spellings."""
    candidates = []
    # The common shapes, cheapest first.
    candidates.append(media.with_name(media.name + ".supplemental-metadata.json"))
    candidates.append(media.with_name(media.name + ".json"))
    for candidate in candidates:
        if candidate.exists():
            return candidate
    # Truncated spellings: anything starting with the media name and ending
    # .json, which is how Google's length limit leaves them.
    prefix = media.name
    for sibling in media.parent.glob(glob_escape(prefix) + "*.json"):
        if any(hint in sibling.name for hint in SIDECAR_HINTS):
            return sibling
    # "IMG_1234(1).jpg" -> "IMG_1234.jpg(1).json"
    match = re.match(r"^(?P<base>.+?)\((?P<n>\d+)\)(?P<ext>\.[^.]+)$", media.name)
    if match:
        alt = media.with_name(f"{match['base']}{match['ext']}({match['n']}).json")
        if alt.exists():
            return alt
    return None


def glob_escape(text: str) -> str:
    return re.sub(r"([*?\[\]])", r"[\1]", text)


def original_of(media: Path) -> Path | None:
    """For an -edited or (1) file, the original it was derived from."""
    stem, ext = os.path.splitext(media.name)
    base = DERIVED.match(stem)
    if not base or base["stem"] == stem:
        return None
    candidate = media.with_name(base["stem"] + ext)
    return candidate if candidate.exists() else None


def date_from_sidecar(sidecar: Path) -> datetime | None:
    try:
        data = json.loads(sidecar.read_text(encoding="utf-8", errors="replace"))
    except (json.JSONDecodeError, OSError):
        return None
    for key in ("photoTakenTime", "creationTime"):
        stamp = (data.get(key) or {}).get("timestamp")
        if stamp:
            try:
                return datetime.fromtimestamp(int(stamp), tz=timezone.utc)
            except (ValueError, OverflowError):
                continue
    return None


def date_from_name(media: Path) -> datetime | None:
    match = FILENAME_DATE.search(media.stem)
    if not match:
        return None
    year, month, day = (int(part) for part in match.groups())
    try:
        return datetime(year, month, day, tzinfo=timezone.utc)
    except ValueError:
        return None


def taken(media: Path) -> tuple[datetime | None, str]:
    sidecar = find_sidecar(media)
    if sidecar:
        when = date_from_sidecar(sidecar)
        if when:
            return when, "sidecar"
    origin = original_of(media)
    if origin:
        origin_sidecar = find_sidecar(origin)
        if origin_sidecar:
            when = date_from_sidecar(origin_sidecar)
            if when:
                return when, "original's sidecar"
    when = date_from_name(media)
    if when:
        return when, "filename"
    return None, "unknown"


def destination(root: Path, when: datetime, name: str, local: bool) -> Path:
    moment = when.astimezone() if local else when
    return root / f"{moment:%Y}" / f"{moment:%m}" / name


def unique(path: Path, source: Path) -> tuple[Path | None, str]:
    """A free name at `path`, or (None, reason) when the file is already there."""
    if not path.exists():
        return path, "move"
    if path.stat().st_size == source.stat().st_size and sha256(path) == sha256(source):
        return None, "identical"
    stem, ext = os.path.splitext(path.name)
    for n in range(1, 1000):
        candidate = path.with_name(f"{stem}-{n}{ext}")
        if not candidate.exists():
            return candidate, "renamed"
        if (candidate.stat().st_size == source.stat().st_size
                and sha256(candidate) == sha256(source)):
            return None, "identical"
    return None, "no free name"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("source", nargs="?", type=Path, help="the Takeout folder")
    parser.add_argument("--apply", action="store_true", help="actually move files")
    parser.add_argument("--dest", type=Path, help="where YEAR/MONTH goes (default: SOURCE)")
    parser.add_argument("--copy", action="store_true",
                        help="copy instead of moving, needed across filesystems")
    parser.add_argument("--utc", action="store_true",
                        help="group by UTC rather than this machine's timezone")
    parser.add_argument("--manifest", type=Path, help="where to write the record of moves")
    parser.add_argument("--undo", type=Path, help="reverse the moves in a manifest")
    args = parser.parse_args()

    if args.undo:
        return undo(args.undo)
    if not args.source:
        parser.error("a SOURCE folder is required")
    source = args.source.resolve()
    if not source.is_dir():
        parser.error(f"{source} is not a directory")
    dest_root = (args.dest or source).resolve()

    if not args.copy and source.stat().st_dev != dest_root.stat().st_dev:
        print(f"photo-sort: {source} and {dest_root} are different filesystems;"
              " a move would be a copy and a delete. Pass --copy to mean it.",
              file=sys.stderr)
        return 2

    media_files = [p for p in sorted(source.rglob("*"))
                   if p.is_file() and p.suffix.lower() in MEDIA]
    if not media_files:
        print(f"photo-sort: no media under {source}")
        return 0

    moves: list[tuple[Path, Path, Path | None, Path | None]] = []
    sources = {"sidecar": 0, "original's sidecar": 0, "filename": 0, "unknown": 0}
    undated: list[Path] = []
    identical = 0

    for media in media_files:
        when, how = taken(media)
        sources[how] += 1
        if when is None:
            undated.append(media)
            continue
        target = destination(dest_root, when, media.name, local=not args.utc)
        if target.parent == media.parent:
            continue                      # already filed
        final, what = unique(target, media)
        if final is None:
            identical += 1
            continue
        sidecar = find_sidecar(media)
        sidecar_target = final.with_name(sidecar.name) if sidecar else None
        moves.append((media, final, sidecar, sidecar_target))

    print(f"  {len(media_files):>6} media files under {source}")
    for how, count in sources.items():
        if count:
            print(f"  {count:>6} dated by {how}")
    print(f"  {len(moves):>6} would move")
    if identical:
        print(f"  {identical:>6} already at the destination, byte for byte - left alone")
    if undated:
        print(f"  {len(undated):>6} have no date anywhere - LEFT WHERE THEY ARE")
        for path in undated[:5]:
            print(f"         {path.relative_to(source)}")
        if len(undated) > 5:
            print(f"         ... and {len(undated) - 5} more")

    if not moves:
        return 0
    if not args.apply:
        print("\n  Examples:")
        for src, dst, _, _ in moves[:5]:
            print(f"    {src.relative_to(source)}\n      -> {dst.relative_to(dest_root)}")
        print("\n  dry run: nothing moved. Add --apply to do it.")
        return 0

    manifest_path = args.manifest or (dest_root / f"photo-sort-{datetime.now():%Y%m%d-%H%M%S}.csv")
    moved = failed = 0
    with manifest_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["source", "destination"])
        for src, dst, sidecar, sidecar_dst in moves:
            try:
                dst.parent.mkdir(parents=True, exist_ok=True)
                transfer(src, dst, args.copy)
                writer.writerow([str(src), str(dst)])
                if sidecar and sidecar_dst and not sidecar_dst.exists():
                    transfer(sidecar, sidecar_dst, args.copy)
                    writer.writerow([str(sidecar), str(sidecar_dst)])
                moved += 1
            except OSError as error:
                print(f"  failed: {src}: {error}", file=sys.stderr)
                failed += 1
            fh.flush()                    # so an interruption still leaves a usable manifest
    print(f"\n  moved {moved}, failed {failed}")
    print(f"  manifest: {manifest_path}")
    print(f"  to undo:  {sys.argv[0]} --undo {manifest_path}")
    return 1 if failed else 0


def transfer(src: Path, dst: Path, copy: bool) -> None:
    if copy:
        shutil.copy2(src, dst)
    else:
        os.replace(src, dst) if src.stat().st_dev == dst.parent.stat().st_dev else shutil.move(str(src), str(dst))


def undo(manifest: Path) -> int:
    rows = list(csv.reader(manifest.open(encoding="utf-8")))[1:]
    back = failed = 0
    for src, dst in reversed(rows):
        source_path, dest_path = Path(src), Path(dst)
        if not dest_path.exists():
            continue
        try:
            source_path.parent.mkdir(parents=True, exist_ok=True)
            if source_path.exists():
                print(f"  in the way, skipped: {source_path}", file=sys.stderr)
                failed += 1
                continue
            os.replace(dest_path, source_path)
            back += 1
        except OSError as error:
            print(f"  failed: {dest_path}: {error}", file=sys.stderr)
            failed += 1

    # THE YEAR AND MONTH DIRECTORIES ARE OURS TO REMOVE, and only while they
    # are empty: rmdir refuses a directory with anything in it, so a folder
    # holding a file this manifest does not know about is left alone. Deepest
    # first, or a year would still hold its months.
    removed = 0
    for row in sorted({Path(dst).parent for _, dst in rows},
                      key=lambda p: len(p.parts), reverse=True):
        for directory in (row, row.parent):
            try:
                directory.rmdir()
                removed += 1
            except OSError:
                pass
    print(f"  put back {back}, failed {failed}"
          + (f", removed {removed} empty folders" if removed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
