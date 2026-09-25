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

STILL = {".jpg", ".jpeg", ".png", ".heic", ".gif", ".webp", ".tif", ".tiff",
         ".dng", ".raw"}
VIDEO = {".mov", ".mp4", ".m4v", ".3gp", ".avi", ".mkv", ".mp"}
MEDIA = STILL | VIDEO

#: Google truncates the WHOLE sidecar name to 51 characters, and the suffix is
#: what gets cut: .supplemental-metadata.json becomes .supplement.json,
#: .supplem.json, .suppleme.json, even .s.json, and a long enough media name
#: leaves no suffix at all. A first version tested for the word "supplemental"
#: and so matched none of those - 34 sidecars in one year of a real Takeout
#: were left behind while their photos moved.
#:
#: So sidecars are resolved from the JSON side instead: strip .json, strip any
#: "(N)", then cut trailing dot-separated pieces until what is left ends in a
#: media extension. That reaches every spelling above, because it never has to
#: guess how much of the suffix survived.
NUMBERED = re.compile(r"^(?P<base>.*?)\((?P<n>\d+)\)$")

#: IMG_20150830_130750 / PXL_20211203_174512345 / VID_20190101_ / 20230115_
FILENAME_DATE = re.compile(r"(?<!\d)(20\d{2}|19\d{2})[-_]?(\d{2})[-_]?(\d{2})(?!\d)")

#: 00100dPORTRAIT_00100_BURST20171118140446463_COV.jpg - a date with a
#: millisecond timestamp run straight onto it. The pattern above refuses these
#: because it insists nothing follows the day, which is right for avoiding
#: false hits in serial numbers and wrong for 48 files in this archive. Here
#: the trailing digits are REQUIRED, which is what makes it safe: a bare run
#: of digits does not match, and datetime() still has to accept the result.
BURST_DATE = re.compile(r"(?:^|\D)(20\d{2}|19\d{2})(\d{2})(\d{2})\d{6,}")

#: "IMG_1234(1).jpg" is Google's duplicate marker; "IMG_1234-edited.jpg" its
#: edit. Both belong with the original, whose sidecar carries the date.
DERIVED = re.compile(r"^(?P<stem>.+?)(?:\(\d+\))?(?:-edited|-EFFECTS|-ANIMATION)?$")


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while block := fh.read(chunk):
            h.update(block)
    return h.hexdigest()


def media_for_sidecar(sidecar: Path) -> str | None:
    """The media filename a sidecar belongs to, or None if it cannot be told.

    "IMG_1234.jpg.supplemental-metadata.json" -> "IMG_1234.jpg"
    "IMG_1234.jpg.supplement.json"            -> "IMG_1234.jpg"   (truncated)
    "IMG_1234.jpg.supplemental-metadata(1).json" -> "IMG_1234(1).jpg"
    """
    name = sidecar.name[:-len(".json")] if sidecar.name.lower().endswith(".json") else sidecar.name
    number = None
    match = NUMBERED.match(name)
    if match:
        name, number = match["base"], match["n"]
    while True:
        stem, dot, ext = name.rpartition(".")
        if not dot:
            return None
        if ("." + ext).lower() in MEDIA:
            if number is not None:
                return f"{stem}({number}).{ext}"
            return name
        name = stem


def media_from_title(sidecar: Path) -> str | None:
    """The filename the sidecar itself claims, for names truncated past repair.

    Three sidecars in a real Takeout had been cut so hard that the media
    extension was gone - "PXL_..._exported_0_171855652714.json" - so nothing
    could be read out of the name. The JSON says so itself, in "title".
    """
    try:
        data = json.loads(sidecar.read_text(encoding="utf-8", errors="replace"))
    except (json.JSONDecodeError, OSError):
        return None
    title = data.get("title")
    if isinstance(title, str) and os.path.splitext(title)[1].lower() in MEDIA:
        return title
    return None


def locate(owner: str, filed: dict[str, Path]) -> Path | None:
    """The file `owner` names, allowing for the name on disk being truncated.

    A FIXED PREFIX IS NOT ENOUGH, which two sidecars proved: both
    ..._BURST20190509204951181_COVER.jpg and ..._BURST20190509204951965_COVER.jpg
    agree for their first forty characters, so a forty-character key matched
    two files and gave up on both. What is actually true of a truncation is
    that the shorter name is a PREFIX of the longer one, all the way to where
    it was cut - so that is what is tested, and the longest agreement wins.
    """
    exact = filed.get(owner)
    if exact:
        return exact
    stem, _ = os.path.splitext(owner)
    hits = [(len(os.path.splitext(name)[0]), path) for name, path in filed.items()
            if stem.startswith(os.path.splitext(name)[0])]
    if not hits:
        return None
    best = max(length for length, _ in hits)
    longest = [path for length, path in hits if length == best]
    if len(longest) == 1:
        return longest[0]
    # Google's "(1)" duplicates tie on length. The original - no (N) before the
    # extension - is the one the metadata describes.
    plain = [h for h in longest if not re.search(r"\(\d+\)\.[^.]+$", h.name)]
    return plain[0] if len(plain) == 1 else None


def sidecars_in(directory: Path) -> dict[str, list[Path]]:
    """Every sidecar in a directory, grouped by the media file it belongs to.

    KEYED BY THE NAME ON DISK, not by the name the metadata claims. Google
    truncates the media file too, and at a different point than the sidecar:
    the JSON says 00100lPORTRAIT_00100_BURST20190509204951181_COVER.jpg and the
    file beside it is ..._COV.jpg. Matching those by exact name left three
    sidecars behind in a 14,551-file archive - the media moved, they did not.
    """
    here = {path.name: path for path in directory.iterdir()
            if path.is_file() and path.suffix.lower() in MEDIA}
    out: dict[str, list[Path]] = {}
    for candidate in directory.glob("*.json"):
        owner = media_for_sidecar(candidate) or media_from_title(candidate)
        if not owner:
            continue
        if owner not in here:
            resolved = locate(owner, here)
            if resolved:
                owner = resolved.name
        out.setdefault(owner, []).append(candidate)
    return out


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
    for pattern in (FILENAME_DATE, BURST_DATE):
        match = pattern.search(media.stem)
        if not match:
            continue
        year, month, day = (int(part) for part in match.groups())
        try:
            return datetime(year, month, day, tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def taken(media: Path, index: dict[str, list[Path]]) -> tuple[datetime | None, str]:
    for sidecar in index.get(media.name, []):
        when = date_from_sidecar(sidecar)
        if when:
            return when, "sidecar"
    origin = original_of(media)
    if origin:
        for sidecar in index.get(origin.name, []):
            when = date_from_sidecar(sidecar)
            if when:
                return when, "original's sidecar"
    when = date_from_name(media)
    if when:
        return when, "filename"
    return None, "unknown"


def has_still_companion(media: Path) -> bool:
    """Is this video a PART of a photo rather than a video in its own right?

    A Pixel motion photo is X.MP beside X.MP.jpg; an iPhone live photo is
    IMG_0018.MOV beside IMG_0018.HEIC. Filing those under video/ separates a
    still from its own motion, which is not what "move the videos" means. Here
    that is 594 of 605 .MP files and 23 .MOV - and, checked rather than
    assumed, none of the 1352 .MP4.

    Case-insensitively, because the stills are .HEIC and .JPG in upper case
    while the videos are .MOV: a case-sensitive test found no pairs at all and
    would have moved every one of them.
    """
    here = {path.name.lower() for path in media.parent.iterdir() if path.is_file()}
    stem, full = media.stem.lower(), media.name.lower()
    return any(stem + ext in here or full + ext in here for ext in STILL)


def destination(root: Path, when: datetime, name: str, local: bool,
                video_dir: str | None = None) -> Path:
    moment = when.astimezone() if local else when
    base = root / video_dir if video_dir else root
    return base / f"{moment:%Y}" / f"{moment:%m}" / name


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
    parser.add_argument("--video-dir", metavar="NAME",
                        help="file videos under NAME/YEAR/MONTH instead of YEAR/MONTH; "
                             "a video that is part of a still (motion and live photos) "
                             "stays with the still")
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

    indexes: dict[Path, dict[str, list[Path]]] = {}
    for media in media_files:
        index = indexes.setdefault(media.parent, sidecars_in(media.parent))
        when, how = taken(media, index)
        sources[how] += 1
        if when is None:
            undated.append(media)
            continue
        into_video = (args.video_dir
                      and media.suffix.lower() in VIDEO
                      and not has_still_companion(media))
        target = destination(dest_root, when, media.name, local=not args.utc,
                             video_dir=args.video_dir if into_video else None)
        if target.parent == media.parent:
            continue                      # already filed
        final, what = unique(target, media)
        if final is None:
            identical += 1
            continue
        # ALL of them: a file can have both .supplemental-metadata.json and a
        # truncated twin, and leaving either behind is what this rewrite is for.
        companions = [(sc, final.parent / sc.name) for sc in index.get(media.name, [])]
        moves.append((media, final, companions))

    # --- strays --------------------------------------------------------
    #
    # A sidecar whose media is NOT beside it any more: either an earlier run
    # moved the media and left this behind, or the two were separated some
    # other way. Reuniting them is the repair for exactly that, and on a fresh
    # archive it finds nothing.
    filed: dict[str, Path] = {}
    for path in dest_root.rglob("*"):
        if path.is_file() and path.suffix.lower() in MEDIA:
            filed.setdefault(path.name, path)

    strays: list[tuple[Path, Path]] = []
    for sidecar in source.rglob("*.json"):
        owner = media_for_sidecar(sidecar) or media_from_title(sidecar)
        if not owner or (sidecar.parent / owner).exists():
            continue
        home = locate(owner, filed)
        if home and home.parent != sidecar.parent:
            target = home.parent / sidecar.name
            if not target.exists():
                strays.append((sidecar, target))

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

    if strays:
        print(f"  {len(strays):>6} stranded sidecars would rejoin their media")
    if not moves and not strays:
        return 0
    if not args.apply:
        print("\n  Examples:")
        for src, dst, _ in moves[:5]:
            print(f"    {src.relative_to(source)}\n      -> {dst.relative_to(dest_root)}")
        print("\n  dry run: nothing moved. Add --apply to do it.")
        return 0

    manifest_path = args.manifest or (dest_root / f"photo-sort-{datetime.now():%Y%m%d-%H%M%S}.csv")
    moved = failed = 0
    with manifest_path.open("w", newline="", encoding="utf-8") as fh:
        # LF, not the csv module's default CRLF: the manifest is read by shell
        # one-liners as often as by this script, and a trailing \r turns every
        # path into one that does not exist - which had me reporting 1840
        # missing files that were all present.
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(["source", "destination"])
        for src, dst, companions in moves:
            try:
                dst.parent.mkdir(parents=True, exist_ok=True)
                transfer(src, dst, args.copy)
                writer.writerow([str(src), str(dst)])
                for sidecar, sidecar_dst in companions:
                    if sidecar.exists() and not sidecar_dst.exists():
                        transfer(sidecar, sidecar_dst, args.copy)
                        writer.writerow([str(sidecar), str(sidecar_dst)])
                moved += 1
            except OSError as error:
                print(f"  failed: {src}: {error}", file=sys.stderr)
                failed += 1
            fh.flush()                    # so an interruption still leaves a usable manifest
        for sidecar, target in strays:
            try:
                target.parent.mkdir(parents=True, exist_ok=True)
                transfer(sidecar, target, args.copy)
                writer.writerow([str(sidecar), str(target)])
                moved += 1
            except OSError as error:
                print(f"  failed: {sidecar}: {error}", file=sys.stderr)
                failed += 1
        fh.flush()
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
