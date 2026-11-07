#!/usr/bin/env python3
"""meander-core clipboard: Meander's clipboard panel over Omarchy's history.

Upstream Serpantinum reads cliphist through its Rust core. Omarchy already
records the clipboard (its omarchy.clipboard plugin writes
~/.local/state/omarchy/clipboard-history.json, newest first, text entries as
{type, text} and images as {type, mime, path}), so Meander runs no recorder
of its own and serves that file instead.

Ids are content hashes, stable across new copies (Omarchy's own ids are list
indexes). Pins are Meander's and are kept as whole entries in
<cache-dir>/pins.json, so a pinned entry outlives Omarchy's history cap.

    list OFFSET LIMIT   JSON [{id, content, type, pinned}], pinned first
    decode ID           the full text (or the image path) on stdout
    copy ID             put the entry on the clipboard
    pin ID              toggle the pin
    delete ID           remove from Omarchy's history and the pins
    wipe                clear Omarchy's history; pinned entries stay
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile

STATE = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
HISTORY = os.path.join(STATE, "omarchy", "clipboard-history.json")
PREVIEW_CHARS = 400


def entry_id(e):
    if e.get("type") == "image":
        base = os.path.basename(e.get("path") or "")
        return "i" + (os.path.splitext(base)[0][:16] or hashlib.sha1(base.encode()).hexdigest()[:16])
    return "t" + hashlib.sha1((e.get("text") or "").encode("utf-8", "replace")).hexdigest()[:16]


def read_json(path, fallback):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return fallback


def write_json(path, data):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".meander-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def history():
    h = read_json(HISTORY, [])
    return [e for e in h if isinstance(e, dict) and e.get("type") in ("text", "image")] if isinstance(h, list) else []


def pins_path(cache):
    return os.path.join(cache, "pins.json")


def pins(cache):
    p = read_json(pins_path(cache), [])
    return [e for e in p if isinstance(e, dict)] if isinstance(p, list) else []


def find(cache, cid):
    for e in pins(cache) + history():
        if entry_id(e) == cid:
            return e
    return None


def as_row(e, pinned):
    if e.get("type") == "image":
        content = e.get("path") or ""
    else:
        content = (e.get("text") or "")[:PREVIEW_CHARS]
    return {"id": entry_id(e), "content": content, "type": e.get("type"), "pinned": pinned}


def cmd_list(cache, offset, limit):
    pinned = pins(cache)
    pinned_ids = {entry_id(e) for e in pinned}
    rows = [as_row(e, True) for e in pinned]
    seen = set(pinned_ids)
    for e in history():
        i = entry_id(e)
        if i in seen:
            continue
        seen.add(i)
        rows.append(as_row(e, False))
    print(json.dumps(rows[offset:offset + limit], ensure_ascii=False))


def cmd_copy(cache, cid):
    e = find(cache, cid)
    if not e:
        return 1
    if e.get("type") == "image":
        path = e.get("path") or ""
        if not os.path.isfile(path):
            return 1
        with open(path, "rb") as f:
            subprocess.run(["wl-copy", "-t", e.get("mime") or "image/png"], stdin=f, check=False)
    else:
        subprocess.run(["wl-copy"], input=(e.get("text") or "").encode("utf-8"), check=False)
    return 0


def cmd_pin(cache, cid):
    p = pins(cache)
    if any(entry_id(e) == cid for e in p):
        p = [e for e in p if entry_id(e) != cid]
    else:
        e = find(cache, cid)
        if not e:
            return 1
        p.insert(0, e)
    write_json(pins_path(cache), p)
    return 0


def cmd_delete(cache, cid):
    p = pins(cache)
    write_json(pins_path(cache), [e for e in p if entry_id(e) != cid])
    h = read_json(HISTORY, [])
    if isinstance(h, list):
        write_json(HISTORY, [e for e in h if not (isinstance(e, dict) and entry_id(e) == cid)])
    return 0


def cmd_wipe(cache):
    if os.path.exists(HISTORY):
        write_json(HISTORY, [])
    return 0


def main(argv):
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "meander", "clipboard")
    if "--cache-dir" in argv:
        i = argv.index("--cache-dir")
        if i + 1 < len(argv):
            cache = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        offset = int(args[0]) if len(args) > 0 and args[0].isdigit() else 0
        limit = int(args[1]) if len(args) > 1 and args[1].isdigit() else 50
        cmd_list(cache, offset, limit)
        return 0
    if cmd == "decode" and args:
        e = find(cache, args[0])
        if not e:
            return 1
        sys.stdout.write(e.get("path") if e.get("type") == "image" else (e.get("text") or ""))
        return 0
    if cmd == "copy" and args:
        return cmd_copy(cache, args[0])
    if cmd == "pin" and args:
        return cmd_pin(cache, args[0])
    if cmd == "delete" and args:
        return cmd_delete(cache, args[0])
    if cmd == "wipe":
        return cmd_wipe(cache)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
