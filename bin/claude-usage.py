#!/usr/bin/env python3
# =========================================================================
# claude-usage.py - how many tokens Claude Code has spent, from the logs
# =========================================================================
#
# Usage:  bin/claude-usage.py status   the cached answer as JSON, for the bar
#         bin/claude-usage.py scan     read what is new, rewrite the cache
#         bin/claude-usage.py show     the same figures as text, for a terminal
#
# The bar's plugin (quickshell/ClaudeUsage.qml) calls `scan` on a timer and
# reads what it prints. Everything that knows the shape of a transcript lives
# here rather than in QML.
#
# LOCAL LOGS, NOT THE API. Claude Code writes every exchange to
# ~/.claude/projects/<project>/<session>.jsonl, and each assistant message
# carries the usage the server reported for it. So the token counts here are
# exact and cost nothing to obtain: no credentials, no network, no rate limit,
# nothing leaving the machine.
#
# WHAT THIS CANNOT TELL YOU, and no amount of log parsing will: the LIMIT. The
# transcripts record what was spent, never what the allowance was. So this
# reports usage and the shape of it over time, and never a percentage - a "73%"
# computed against a guessed ceiling is worse than no number, because it looks
# authoritative. Tools that show a real percentage query Anthropic's usage
# endpoint for it, which is a different trade: credentials, rate limits, and
# nothing while offline.
#
# IT READS ONLY WHAT IS NEW. The transcripts on this machine are 567 MB, and
# the one for an active session grows while you are looking at it, so a plugin
# that reparsed them on a timer would read half a gigabyte every minute to
# answer a question about the last five hours. The cache remembers each file's
# size and inode; a later run seeks to where it stopped and reads forward from
# there. A file that shrank or was replaced is read again from the start, which
# is what happens when a session is rolled over.
#
# BUCKETS ARE FIVE HOURS BECAUSE THAT IS HOW THE LIMIT WORKS, aligned to the
# hour rather than to "now", so the number does not change meaning between two
# readings a minute apart.

import json
import os
import sys
import time
from datetime import datetime, timezone, timedelta

PROJECTS = os.path.expanduser("~/.claude/projects")
CACHE = os.path.expanduser("~/.cache/fd44-claude-usage/state.json")

BUCKET_HOURS = 5

# The four counters a usage object carries. Kept apart rather than summed into
# one "tokens" number, because they are not the same thing at all: a cache READ
# is most of the volume and almost none of the cost, and a plugin that showed
# their sum would report an enormous number that mostly meant "the context was
# resent", which is the one thing the user did not do.
FIELDS = ("input_tokens", "output_tokens",
          "cache_creation_input_tokens", "cache_read_input_tokens")


def bucket_start(ts: float) -> float:
    """The start of the BUCKET_HOURS window `ts` falls in, aligned to the hour."""
    dt = datetime.fromtimestamp(ts, timezone.utc).replace(
        minute=0, second=0, microsecond=0)
    return (dt - timedelta(hours=dt.hour % BUCKET_HOURS)).timestamp()


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def load_cache():
    try:
        with open(CACHE) as f:
            c = json.load(f)
        if c.get("version") != 1:
            raise ValueError("old cache")
        return c
    except Exception:
        # A missing or unreadable cache is not an error, it is the first run.
        return {"version": 1, "files": {}, "buckets": {}, "models": {}}


def save_cache(c):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".new"
    with open(tmp, "w") as f:
        json.dump(c, f)
    os.replace(tmp, CACHE)      # never half a file for a reader


def scan():
    """Read whatever is new in every transcript and fold it into the cache."""
    c = load_cache()
    files = c.setdefault("files", {})
    buckets = c.setdefault("buckets", {})
    models = c.setdefault("models", {})

    if not os.path.isdir(PROJECTS):
        c["scanned"] = time.time()
        save_cache(c)
        return c

    for root, _dirs, names in os.walk(PROJECTS):
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            try:
                st = os.stat(path)
            except OSError:
                continue

            seen = files.get(path) or {}
            offset = seen.get("offset", 0)
            # A SHRUNK OR REPLACED FILE IS READ AGAIN. Comparing the inode as
            # well as the size catches a session rolled over into a new file of
            # the same name, which a size check alone would read from the middle.
            if st.st_size < offset or seen.get("inode") != st.st_ino:
                offset = 0
            if st.st_size == offset:
                continue

            try:
                with open(path, "r", errors="replace") as f:
                    f.seek(offset)
                    data = f.read()
            except OSError:
                continue

            # A partial last line happens whenever the active session is mid
            # write. Keep the offset before it so it is read whole next time.
            consumed = offset
            for line in data.splitlines(keepends=True):
                if not line.endswith("\n"):
                    break
                consumed += len(line.encode("utf-8", "replace"))
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                msg = d.get("message") or {}
                usage = msg.get("usage")
                if not usage:
                    continue
                ts = parse_ts(d.get("timestamp"))
                if ts is None:
                    continue

                key = str(int(bucket_start(ts)))
                b = buckets.setdefault(key, dict.fromkeys(FIELDS, 0))
                b["messages"] = b.get("messages", 0) + 1
                for fld in FIELDS:
                    v = usage.get(fld)
                    if isinstance(v, int):
                        b[fld] = b.get(fld, 0) + v

                model = msg.get("model") or "unknown"
                m = models.setdefault(model, dict.fromkeys(FIELDS, 0))
                for fld in FIELDS:
                    v = usage.get(fld)
                    if isinstance(v, int):
                        m[fld] = m.get(fld, 0) + v

            files[path] = {"offset": consumed, "inode": st.st_ino}

    # Buckets older than 30 days are dropped: this is a bar plugin, not an
    # accounting record, and an unbounded cache would grow for ever.
    cutoff = time.time() - 30 * 86400
    for k in [k for k in buckets if float(k) < cutoff]:
        del buckets[k]

    c["scanned"] = time.time()
    save_cache(c)
    return c


def summarise(c):
    now = time.time()
    buckets = c.get("buckets", {})

    cur_key = str(int(bucket_start(now)))
    cur = buckets.get(cur_key, {})

    def billed(b):
        """Input + output + cache writes. Cache READS are excluded on purpose:
        they are the bulk of the volume and a fraction of the price, and
        including them makes every number look alarming for no reason."""
        return (b.get("input_tokens", 0) + b.get("output_tokens", 0)
                + b.get("cache_creation_input_tokens", 0))

    midnight = datetime.now().replace(hour=0, minute=0, second=0,
                                      microsecond=0).timestamp()
    today = {f: 0 for f in FIELDS}
    today["messages"] = 0
    for k, b in buckets.items():
        if float(k) >= midnight:
            for f in FIELDS:
                today[f] += b.get(f, 0)
            today["messages"] += b.get("messages", 0)

    week = {f: 0 for f in FIELDS}
    since = now - 7 * 86400
    for k, b in buckets.items():
        if float(k) >= since:
            for f in FIELDS:
                week[f] += b.get(f, 0)

    # The bucket ends BUCKET_HOURS after it began, which is the only thing here
    # that resembles a deadline - so it is worth saying how long is left.
    cur_start = bucket_start(now)
    ends_in = int(cur_start + BUCKET_HOURS * 3600 - now)

    models = sorted(c.get("models", {}).items(),
                    key=lambda kv: -billed(kv[1]))

    return {
        "ok": True,
        "scanned": c.get("scanned", 0),
        "block": {
            "billed": billed(cur),
            "messages": cur.get("messages", 0),
            "endsIn": max(0, ends_in),
            "hours": BUCKET_HOURS,
            **{f: cur.get(f, 0) for f in FIELDS},
        },
        "today": {"billed": billed(today), **today},
        "week": {"billed": billed(week), **week},
        "models": [{"name": n, "billed": billed(v)} for n, v in models[:6]],
        # The recent blocks, oldest first, for a sparkline. Each entry is one
        # BUCKET_HOURS window; empty windows are included as zero so the shape
        # over time is honest rather than compressed.
        "recent": recent_blocks(buckets, now, 12, billed),
    }


def recent_blocks(buckets, now, count, billed):
    out = []
    start = bucket_start(now)
    for i in range(count - 1, -1, -1):
        k = str(int(start - i * BUCKET_HOURS * 3600))
        out.append(billed(buckets.get(k, {})))
    return out


def human(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}k"
    return str(n)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"

    if cmd == "scan":
        print(json.dumps(summarise(scan())))
        return 0

    if cmd == "status":
        # Does not read the transcripts: whatever the last scan left.
        print(json.dumps(summarise(load_cache())))
        return 0

    if cmd == "show":
        s = summarise(scan())
        b, t, w = s["block"], s["today"], s["week"]
        print(f"this {s['block']['hours']}h block   {human(b['billed'])} billed"
              f"   {b['messages']} messages"
              f"   {b['endsIn']//3600}h{b['endsIn']%3600//60:02d}m left")
        print(f"today             {human(t['billed'])} billed"
              f"   {t['messages']} messages")
        print(f"last 7 days       {human(w['billed'])} billed")
        print()
        print("  billed = input + output + cache writes."
              " Cache reads are counted separately:")
        print(f"  block cache reads {human(b['cache_read_input_tokens'])}")
        print()
        for m in s["models"]:
            print(f"  {m['name']:<28} {human(m['billed'])}")
        return 0

    print(f"claude-usage: unknown command: {cmd}", file=sys.stderr)
    print(__doc__ or "", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
