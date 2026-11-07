#!/usr/bin/env python3
"""meander-core screentime: screen time for the Digital Wellbeing tab.

Upstream Serpantinum counts screen time in its Rust core. Omarchy has no
screen-time service, so this is Meander's own, stdlib only:

    track [--db-dir DIR]                  count the focused app once a second
    stats DATE [--app CLASS] [--db-dir D] print the tab's JSON for DATE

The focused app comes from Hyprland's event socket. Counting pauses while the
session is locked (Meander's lock marker, or Omarchy's lock) and while no
window has focus. Usage lands in <db-dir>/screentime.db per day and half hour;
`track` also writes today's numbers to $XDG_RUNTIME_DIR/meander/focustime/
focustime_state.json every second (the tab's live view) and, when a daily limit
from settings.json `wellbeing` is reached, limit_event.json (the overlay) plus
a notification.
"""
import datetime as dt
import json
import os
import signal
import socket
import sqlite3
import subprocess
import sys
import threading
import time

HOME = os.path.expanduser("~")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "meander")
STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
DEFAULT_DB_DIR = os.path.join(STATE, "meander", "focustime")
SETTINGS = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "meander", "settings.json")
LIVE_DIR = os.path.join(RUN, "focustime")
LOCK_MARKER = os.path.join(RUN, "lock", "locked")


def db_open(db_dir):
    os.makedirs(db_dir, exist_ok=True)
    con = sqlite3.connect(os.path.join(db_dir, "screentime.db"), timeout=5)
    con.execute("""CREATE TABLE IF NOT EXISTS usage (
        day TEXT NOT NULL, slot INTEGER NOT NULL, class TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '', seconds INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (day, slot, class))""")
    con.execute("CREATE INDEX IF NOT EXISTS usage_class ON usage(class)")
    return con


def iso(d):
    return d.strftime("%Y-%m-%d")


def settings():
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            s = json.load(f)
        w = s.get("wellbeing") or {}
        return w if isinstance(w, dict) else {}
    except (OSError, ValueError):
        return {}


# ---------------------------------------------------------------- stats
def stats(con, date_str, app=None, current=""):
    try:
        day = dt.date.fromisoformat(date_str)
    except ValueError:
        day = dt.date.today()
    where_app = " AND class = ?" if app else ""
    a = (app,) if app else ()

    def day_total(d):
        r = con.execute("SELECT COALESCE(SUM(seconds),0) FROM usage WHERE day = ?" + where_app, (iso(d),) + a).fetchone()
        return int(r[0] or 0)

    total = day_total(day)
    hourly = [0] * 48
    for slot, secs in con.execute("SELECT slot, SUM(seconds) FROM usage WHERE day = ?" + where_app + " GROUP BY slot", (iso(day),) + a):
        if 0 <= slot < 48:
            hourly[slot] = int(secs)

    def apps_between(d0, d1):
        rows = con.execute(
            "SELECT class, MAX(name), SUM(seconds) FROM usage WHERE day BETWEEN ? AND ?" + where_app +
            " GROUP BY class ORDER BY SUM(seconds) DESC", (iso(d0), iso(d1)) + a).fetchall()
        tot = sum(int(r[2]) for r in rows) or 1
        return [{"class": r[0], "name": r[1] or r[0], "seconds": int(r[2]), "percent": round(100.0 * int(r[2]) / tot, 1)} for r in rows]

    week_start = day - dt.timedelta(days=day.weekday())
    week_days = [week_start + dt.timedelta(days=i) for i in range(7)]
    week = [{"date": iso(d), "day": d.strftime("%a"), "total": day_total(d), "is_target": d == day} for d in week_days]
    heat = []
    for d in week_days:
        row = [0] * 24
        for slot, secs in con.execute("SELECT slot, SUM(seconds) FROM usage WHERE day = ?" + where_app + " GROUP BY slot", (iso(d),) + a):
            if 0 <= slot < 48:
                row[slot // 2] += int(secs)
        heat.append(row)

    month_start = day.replace(day=1)
    next_month = (month_start + dt.timedelta(days=32)).replace(day=1)
    month = []
    d = month_start
    while d < next_month:
        month.append({"date": iso(d), "total": day_total(d), "is_target": d == day})
        d += dt.timedelta(days=1)

    used = [w["total"] for w in week if w["total"] > 0]
    known = con.execute("SELECT class, MAX(name), SUM(seconds) FROM usage GROUP BY class ORDER BY SUM(seconds) DESC").fetchall()
    return {
        "selected_date": iso(day),
        "total": total,
        "average": int(sum(used) / len(used)) if used else 0,
        "yesterday": day_total(day - dt.timedelta(days=1)),
        "week_range": "%s - %s" % (week_days[0].strftime("%b %-d"), week_days[-1].strftime("%b %-d")),
        "current": current,
        "apps": apps_between(day, day),
        "week_apps": apps_between(week_days[0], week_days[-1]),
        "all_known_apps": [{"class": r[0], "name": r[1] or r[0], "seconds": int(r[2])} for r in known],
        "week_heatmap": heat,
        "week": week,
        "month": month,
        "hourly": hourly,
    }


# ---------------------------------------------------------------- track
class Focus:
    def __init__(self):
        self.cls = ""
        self.title = ""
        self.lock = threading.Lock()

    def set(self, cls, title):
        with self.lock:
            self.cls, self.title = cls, title

    def get(self):
        with self.lock:
            return self.cls, self.title


def hypr_socket():
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "hypr")
    if not his and os.path.isdir(base):
        cands = sorted((os.path.join(base, d) for d in os.listdir(base)), key=os.path.getmtime, reverse=True)
        his = os.path.basename(cands[0]) if cands else ""
    return os.path.join(base, his, ".socket2.sock")


def initial_focus(focus):
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=3).stdout
        w = json.loads(out or "{}")
        focus.set(w.get("class") or "", w.get("title") or "")
    except (OSError, ValueError, subprocess.SubprocessError):
        pass


def follow_events(focus):
    while True:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(hypr_socket())
            buf = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    ev = line.decode("utf-8", "replace")
                    if ev.startswith("activewindow>>"):
                        cls, _, title = ev[len("activewindow>>"):].partition(",")
                        focus.set(cls, title)
        except OSError:
            pass
        time.sleep(2)
        initial_focus(focus)


def desktop_name(cls, cache):
    """A readable app name for a window class, from its .desktop file."""
    if cls in cache:
        return cache[cls]
    name = cls
    dirs = [os.path.join(HOME, ".local/share/applications"), "/usr/share/applications"]
    want = cls.lower()
    for d in dirs:
        try:
            for f in os.listdir(d):
                if not f.endswith(".desktop"):
                    continue
                stem = f[:-8].lower()
                if stem != want and not stem.endswith("." + want):
                    continue
                with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        if line.startswith("Name="):
                            name = line[5:].strip()
                            break
                raise StopIteration
        except StopIteration:
            break
        except OSError:
            continue
    cache[cls] = name
    return name


class LockProbe:
    """Omarchy's lock is asked every 15s; Meander's leaves a marker file."""

    def __init__(self):
        self.locked = False
        self.next = 0

    def __call__(self):
        if os.path.exists(LOCK_MARKER):
            return True
        now = time.time()
        if now >= self.next:
            self.next = now + 15
            try:
                out = subprocess.run(["omarchy-shell", "lock", "isLocked"], capture_output=True, text=True, timeout=3).stdout.strip()
                self.locked = out == "true"
            except (OSError, subprocess.SubprocessError):
                self.locked = False
        return self.locked


def write_atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def flush(con, pending, names):
    for (day, slot, c), secs in pending.items():
        con.execute("""INSERT INTO usage(day, slot, class, name, seconds) VALUES (?,?,?,?,?)
            ON CONFLICT(day, slot, class) DO UPDATE SET seconds = seconds + excluded.seconds, name = excluded.name""",
                    (day, slot, c, desktop_name(c, names), secs))
    con.commit()
    pending.clear()


def track(db_dir):
    con = db_open(db_dir)
    # The shell stops the tracker with SIGTERM; keep the last seconds.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    focus = Focus()
    initial_focus(focus)
    threading.Thread(target=follow_events, args=(focus,), daemon=True).start()
    is_locked = LockProbe()
    names = {}
    pending = {}
    notified = set()
    notified_day = iso(dt.date.today())
    last_flush = time.time()
    tick = 0

    try:
        loop(con, focus, is_locked, names, pending, notified, notified_day, last_flush, tick)
    finally:
        if pending:
            flush(con, pending, names)


def loop(con, focus, is_locked, names, pending, notified, notified_day, last_flush, tick):
    while True:
        time.sleep(1)
        now = dt.datetime.now()
        today = iso(now.date())
        if today != notified_day:
            notified, notified_day = set(), today
        cls, _title = focus.get()
        w = settings()
        excluded = {str(x).lower() for x in (w.get("excludedApps") or [])}
        counting = bool(cls) and cls.lower() not in excluded and not is_locked()
        if counting:
            key = (today, now.hour * 2 + (1 if now.minute >= 30 else 0), cls)
            pending[key] = pending.get(key, 0) + 1

        if pending and (time.time() - last_flush >= 10 or not counting):
            flush(con, pending, names)
            last_flush = time.time()

        # The live view: today's numbers including what isn't flushed yet,
        # every other second (the tab polls once a second).
        tick += 1
        if tick % 2 == 0:
            try:
                data = stats(con, today, current=desktop_name(cls, names) if cls else "")
                data["total"] += sum(v for (d, _s, _c), v in pending.items() if d == today)
                write_atomic(os.path.join(LIVE_DIR, "focustime_state.json"), json.dumps(data))
            except (sqlite3.Error, OSError):
                pass

        if counting:
            check_limits(con, w, cls, desktop_name(cls, names), today, pending, notified)


def check_limits(con, w, cls, name, today, pending, notified):
    def used(c=None):
        q = "SELECT COALESCE(SUM(seconds),0) FROM usage WHERE day = ?" + (" AND class = ?" if c else "")
        base = int(con.execute(q, (today, c) if c else (today,)).fetchone()[0])
        return base + sum(v for (d, _s, k), v in pending.items() if d == today and (c is None or k == c))

    limits = w.get("appLimits") or {}
    for lc, secs in limits.items():
        if str(lc).lower() == cls.lower() and int(secs or 0) > 0 and lc not in notified:
            u = used(cls)
            if u >= int(secs):
                notified.add(lc)
                fire(cls, name, u)
    overall = int(w.get("overallDailyLimit") or 0)
    if overall > 0 and "__overall__" not in notified and used() >= overall:
        notified.add("__overall__")
        fire("", "Screen time", used())


def fire(cls, name, seconds):
    write_atomic(os.path.join(LIVE_DIR, "limit_event.json"),
                 json.dumps({"stamp": time.time(), "class": cls, "name": name, "seconds": seconds}))
    mins = seconds // 60
    try:
        subprocess.Popen(["notify-send", "-a", "Digital Wellbeing", "Daily limit reached",
                          "%s: %dh %02dm today" % (name, mins // 60, mins % 60)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def main(argv):
    db_dir = DEFAULT_DB_DIR
    app = None
    if "--db-dir" in argv:
        i = argv.index("--db-dir")
        db_dir = argv[i + 1] if i + 1 < len(argv) else db_dir
        argv = argv[:i] + argv[i + 2:]
    if "--app" in argv:
        i = argv.index("--app")
        app = argv[i + 1] if i + 1 < len(argv) else None
        argv = argv[:i] + argv[i + 2:]
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    if argv[0] == "track":
        try:
            track(db_dir)
        except KeyboardInterrupt:
            pass
        return 0
    if argv[0] == "stats":
        con = db_open(db_dir)
        print(json.dumps(stats(con, argv[1] if len(argv) > 1 else iso(dt.date.today()), app)))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
