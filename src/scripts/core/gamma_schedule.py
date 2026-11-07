#!/usr/bin/env python3
"""Day/night colour temperature for meander-gamma's automatic mode.

Runs in the background while the blue light filter follows the schedule.
Night is between sunset and sunrise at the saved location (NOAA's sunrise
equation), or between the fallback times when no location is set. The
temperature eases over 30 minutes around each change, then goes to
hyprsunset, Omarchy's night light daemon.

    gamma_schedule.py STATE_JSON
"""
import datetime as dt
import json
import math
import subprocess
import sys
import time

RAMP_MIN = 30


def sun_times(day, lat, lon):
    """Local sunrise/sunset datetimes for `day`, or None (polar day/night)."""
    n = day.timetuple().tm_yday
    gamma = 2 * math.pi / 365 * (n - 1)
    eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma)
                       - 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma))
    decl = (0.006918 - 0.399912 * math.cos(gamma) + 0.070257 * math.sin(gamma)
            - 0.006758 * math.cos(2 * gamma) + 0.000907 * math.sin(2 * gamma)
            - 0.002697 * math.cos(3 * gamma) + 0.00148 * math.sin(3 * gamma))
    lat_r = math.radians(lat)
    cos_ha = (math.cos(math.radians(90.833)) / (math.cos(lat_r) * math.cos(decl))) - math.tan(lat_r) * math.tan(decl)
    if cos_ha < -1 or cos_ha > 1:
        return None
    ha = math.degrees(math.acos(cos_ha))
    offset = dt.datetime.now().astimezone().utcoffset().total_seconds() / 60.0
    midnight = dt.datetime.combine(day, dt.time())
    rise = midnight + dt.timedelta(minutes=720 - 4 * (lon + ha) - eqtime + offset)
    sset = midnight + dt.timedelta(minutes=720 - 4 * (lon - ha) - eqtime + offset)
    return rise, sset


def parse_hm(s, default):
    try:
        h, m = s.split(":")
        return dt.time(int(h), int(m))
    except (ValueError, AttributeError):
        return default


def target(state, now):
    day_t = int(state.get("day", 6500))
    night_t = int(state.get("night", 4000))
    lat, lon = state.get("lat"), state.get("lon")
    times = None
    if lat is not None and lon is not None and not (lat == 0 and lon == 0):
        times = sun_times(now.date(), float(lat), float(lon))
    if times is None:
        rise = dt.datetime.combine(now.date(), parse_hm(state.get("dayStart"), dt.time(6, 30)))
        sset = dt.datetime.combine(now.date(), parse_hm(state.get("nightStart"), dt.time(19, 0)))
    else:
        rise, sset = times
    ramp = dt.timedelta(minutes=RAMP_MIN)

    def blend(frac):
        frac = max(0.0, min(1.0, frac))
        return round(night_t + (day_t - night_t) * frac)

    if rise <= now <= rise + ramp:
        return blend((now - rise) / ramp)
    if sset - ramp <= now <= sset:
        return blend((sset - now) / ramp)
    return day_t if rise + ramp < now < sset - ramp else night_t


def apply(temp):
    if temp >= 6500:
        subprocess.run(["hyprctl", "hyprsunset", "identity"], capture_output=True)
    else:
        subprocess.run(["hyprctl", "hyprsunset", "temperature", str(temp)], capture_output=True)
    subprocess.run(["omarchy-shell", "-q", "nightlight", "refresh"], capture_output=True)


def main(argv):
    path = argv[0]
    last = None
    while True:
        try:
            with open(path) as f:
                state = json.load(f)
        except (OSError, ValueError):
            return 0
        if state.get("mode") != "auto":
            return 0
        t = target(state, dt.datetime.now())
        if t != last:
            apply(t)
            last = t
        time.sleep(60)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
