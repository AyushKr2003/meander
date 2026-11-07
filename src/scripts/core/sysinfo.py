#!/usr/bin/env python3
"""meander-core sysinfo: system usage for the monitors, widgets and lock screen.

    sysinfo                    one JSON object
    watch sysinfo [--interval S]  one JSON object per line, every S seconds

{cpu, ramPercent, ramGb, temp, netRx, netTx, diskPercent, diskUsedGb,
diskTotalGb}; net in bytes per second. Read from /proc and /sys, as
upstream's core does; Omarchy has no usage feed of its own.
"""
import json
import os
import sys
import time


def cpu_times():
    with open("/proc/stat") as f:
        parts = f.readline().split()[1:]
    vals = [int(x) for x in parts]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
    return idle, sum(vals)


def memory():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            info[k] = int(v.split()[0])
    total = info.get("MemTotal", 1)
    avail = info.get("MemAvailable", info.get("MemFree", 0))
    used = total - avail
    return round(100.0 * used / total), round(used / 1048576.0, 1)


def temperature():
    best = 0
    # Prefer the CPU package sensor (coretemp / k10temp / zenpower).
    base = "/sys/class/hwmon"
    try:
        for h in os.listdir(base):
            d = os.path.join(base, h)
            try:
                name = open(os.path.join(d, "name")).read().strip()
            except OSError:
                continue
            if name not in ("coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"):
                continue
            for f in sorted(os.listdir(d)):
                if f.startswith("temp") and f.endswith("_input"):
                    try:
                        t = int(open(os.path.join(d, f)).read().strip()) // 1000
                    except (OSError, ValueError):
                        continue
                    if name != "acpitz":
                        return t
                    best = max(best, t)
    except OSError:
        pass
    if best:
        return best
    try:
        for z in os.listdir("/sys/class/thermal"):
            if z.startswith("thermal_zone"):
                t = int(open("/sys/class/thermal/%s/temp" % z).read().strip()) // 1000
                best = max(best, t)
    except (OSError, ValueError):
        pass
    return best


def net_bytes():
    rx = tx = 0
    with open("/proc/net/dev") as f:
        for line in f.readlines()[2:]:
            name, data = line.split(":", 1)
            name = name.strip()
            if name == "lo" or name.startswith(("veth", "docker", "br-", "virbr")):
                continue
            v = data.split()
            rx += int(v[0])
            tx += int(v[8])
    return rx, tx


def disk():
    s = os.statvfs(os.path.expanduser("~"))
    total = s.f_blocks * s.f_frsize
    free = s.f_bavail * s.f_frsize
    used = total - free
    return round(100.0 * used / total) if total else 0, round(used / 1e9, 1), round(total / 1e9, 1)


def sample(prev, interval):
    idle0, total0, rx0, tx0, t0 = prev
    idle1, total1 = cpu_times()
    rx1, tx1 = net_bytes()
    t1 = time.time()
    dt = max(1e-3, t1 - t0)
    dtotal = total1 - total0
    cpu = round(100.0 * (1.0 - (idle1 - idle0) / dtotal)) if dtotal > 0 else 0
    ram_pct, ram_gb = memory()
    dp, du, dtot = disk()
    out = {
        "cpu": max(0, min(100, cpu)),
        "ramPercent": ram_pct,
        "ramGb": ram_gb,
        "temp": temperature(),
        "netRx": max(0, (rx1 - rx0) / dt),
        "netTx": max(0, (tx1 - tx0) / dt),
        "diskPercent": dp,
        "diskUsedGb": du,
        "diskTotalGb": dtot,
    }
    return out, (idle1, total1, rx1, tx1, t1)


def first():
    idle, total = cpu_times()
    rx, tx = net_bytes()
    return (idle, total, rx, tx, time.time())


def main(argv):
    watch = bool(argv) and argv[0] == "watch"
    interval = 2.0
    if "--interval" in argv:
        i = argv.index("--interval")
        try:
            interval = max(0.5, float(argv[i + 1]))
        except (IndexError, ValueError):
            pass
    prev = first()
    if not watch:
        time.sleep(0.25)
        out, _ = sample(prev, 0.25)
        print(json.dumps(out))
        return 0
    try:
        while True:
            time.sleep(interval)
            out, prev = sample(prev, interval)
            sys.stdout.write(json.dumps(out) + "\n")
            sys.stdout.flush()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
