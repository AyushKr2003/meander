#!/usr/bin/env python3
"""meander-core launcher: app ranking, launch log and file search.

Upstream's Rust core ranks apps from screen time and launches, both decaying
by half a week. Omarchy's own launcher keeps no usage data, so this is
Meander's:

    rank         {"focus": {class: score}, "launch": {name: score}, "context": {class: score}}
    log NAME     count a launch of NAME
    files QUERY  [{name, path, isDir}]: a path query lists that folder, anything
                 else searches $HOME by name (fd when installed)
"""
import json
import math
import os
import shutil
import sqlite3
import subprocess
import sys
import time
import datetime as dt

HOME = os.path.expanduser("~")
STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
DB = os.path.join(STATE, "meander", "focustime", "screentime.db")
LAUNCHES = os.path.join(STATE, "meander", "launcher", "launches.json")
HALF_LIFE_DAYS = 3.5
MAX_FILES = 60


def decay(age_days):
    return math.pow(0.5, max(0.0, age_days) / HALF_LIFE_DAYS)


def rank():
    focus, context = {}, {}
    today = dt.date.today()
    hour_slots = {(dt.datetime.now().hour * 2 + d) % 48 for d in (-2, -1, 0, 1, 2, 3)}
    if os.path.exists(DB):
        try:
            con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True, timeout=2)
            since = (today - dt.timedelta(days=28)).isoformat()
            for day, slot, cls, secs in con.execute("SELECT day, slot, class, seconds FROM usage WHERE day >= ?", (since,)):
                try:
                    age = (today - dt.date.fromisoformat(day)).days
                except ValueError:
                    continue
                w = decay(age) * secs / 3600.0
                key = cls.lower()
                focus[key] = focus.get(key, 0.0) + w
                if slot in hour_slots:
                    context[key] = context.get(key, 0.0) + w
        except sqlite3.Error:
            pass
    launch = {}
    now = time.time()
    for name, stamps in read_launches().items():
        launch[name] = sum(decay((now - t) / 86400.0) for t in stamps)
    r = lambda d: {k: round(v, 4) for k, v in d.items() if v > 0.0005}
    return {"focus": r(focus), "launch": r(launch), "context": r(context)}


def read_launches():
    try:
        with open(LAUNCHES, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def log(name):
    d = read_launches()
    now = time.time()
    cutoff = now - 60 * 86400
    stamps = [t for t in d.get(name, []) if t > cutoff][-200:]
    stamps.append(now)
    d[name] = stamps
    os.makedirs(os.path.dirname(LAUNCHES), exist_ok=True)
    tmp = LAUNCHES + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f)
    os.replace(tmp, LAUNCHES)


def files(query):
    q = (query or "").strip()
    out = []
    if q.startswith("/") or q.startswith("~"):
        path = os.path.expanduser(q)
        folder, prefix = (path, "") if path.endswith("/") else os.path.split(path)
        try:
            for e in sorted(os.scandir(folder or "/"), key=lambda e: (not e.is_dir(), e.name.lower())):
                if e.name.startswith(".") and not prefix.startswith("."):
                    continue
                if prefix and not e.name.lower().startswith(prefix.lower()):
                    continue
                out.append({"name": e.name, "path": e.path, "isDir": e.is_dir()})
                if len(out) >= MAX_FILES:
                    break
        except OSError:
            pass
        return out
    if not q:
        # Nothing typed: the most recently changed files in the usual folders.
        cands = []
        for sub in ("Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music"):
            d = os.path.join(HOME, sub)
            try:
                for e in os.scandir(d):
                    if not e.name.startswith("."):
                        cands.append((e.stat().st_mtime, e))
            except OSError:
                continue
        cands.sort(key=lambda x: x[0], reverse=True)
        return [{"name": e.name, "path": e.path, "isDir": e.is_dir()} for _, e in cands[:MAX_FILES]]
    fd = shutil.which("fd") or shutil.which("fdfind")
    try:
        if fd:
            res = subprocess.run([fd, "--max-results", str(MAX_FILES), "-i", "--", q, HOME],
                                 capture_output=True, text=True, timeout=4).stdout
        else:
            res = subprocess.run(["find", HOME, "-iname", "*%s*" % q, "-not", "-path", "*/.*"],
                                 capture_output=True, text=True, timeout=4).stdout
    except (OSError, subprocess.SubprocessError):
        res = ""
    for line in res.splitlines()[:MAX_FILES]:
        p = line.rstrip("/")
        out.append({"name": os.path.basename(p), "path": p, "isDir": os.path.isdir(p)})
    return out


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    if argv[0] == "rank":
        print(json.dumps(rank()))
    elif argv[0] == "log" and len(argv) > 1:
        log(" ".join(argv[1:]))
    elif argv[0] == "files":
        print(json.dumps(files(" ".join(argv[1:]))))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
