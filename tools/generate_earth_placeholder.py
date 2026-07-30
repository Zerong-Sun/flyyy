#!/usr/bin/env python3
"""Generate an earth placeholder texture (same algorithm as GlobeController._build_earth)
and output as PNG via ffmpeg. Run once to produce `game/assets/earth/earth_albedo_placeholder.png`.
"""
from __future__ import annotations
import math
import subprocess
import sys
from pathlib import Path

W, H = 1024, 512
ROOT = Path(__file__).resolve().parent.parent  # tools/ → repo root
OUT = ROOT / "game" / "assets" / "earth" / "earth_albedo_placeholder.png"

# Same blob data as GlobeController._CONTINENT_BLOBS
BLOBS = [
    [45.0, -100.0, 28.0, 38.0], [60.0, -120.0, 18.0, 28.0], [30.0, -85.0, 14.0, 18.0],
    [72.0, -40.0, 12.0, 18.0], [-15.0, -60.0, 32.0, 18.0], [-5.0, -75.0, 12.0, 10.0],
    [50.0, 15.0, 16.0, 28.0], [60.0, 25.0, 10.0, 20.0], [5.0, 20.0, 32.0, 22.0],
    [25.0, 5.0, 12.0, 16.0], [45.0, 90.0, 28.0, 55.0], [30.0, 70.0, 18.0, 30.0],
    [55.0, 60.0, 14.0, 35.0], [20.0, 105.0, 16.0, 22.0], [65.0, 100.0, 12.0, 40.0],
    [20.0, 78.0, 12.0, 12.0], [5.0, 115.0, 10.0, 18.0], [-25.0, 135.0, 16.0, 22.0],
    [-42.0, 172.0, 8.0, 6.0], [38.0, 138.0, 10.0, 8.0], [54.0, -4.0, 6.0, 8.0],
    [65.0, -18.0, 5.0, 8.0], [-20.0, 47.0, 8.0, 4.0],
]


def _lon_delta(a: float, b: float) -> float:
    d = a - b
    while d > 180:
        d -= 360
    while d < -180:
        d += 360
    return d


def _land_strength(lat: float, lon: float) -> float:
    best = 0.0
    for blob in BLOBS:
        dlat = (lat - blob[0]) / blob[2]
        dlon = _lon_delta(lon, blob[1]) / blob[3]
        d2 = dlat * dlat + dlon * dlon
        if d2 < 1.0:
            best = max(best, 1.0 - d2)
    if best > 0.0:
        n = 0.08 * math.sin(lat * 0.35 + lon * 0.22) * math.cos(lon * 0.18)
        best = max(0.0, min(1.0, best + n))
    return best


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * _clamp(t, 0.0, 1.0)


def make_raw() -> bytes:
    """Return W*H*3 bytes of RGB24 in row-major (top-bottom) order."""
    buf = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            u = x / (W - 1)
            v = y / (H - 1)
            lat_rad = (0.5 - v) * math.pi
            lon_rad = (u - 0.5) * math.tau
            lat_deg = math.degrees(lat_rad)

            land = _land_strength(lat_deg, math.degrees(lon_rad))
            polar = abs(lat_deg) > 72.0

            if polar:
                shade = _clamp((abs(lat_deg) - 72.0) / 18.0, 0.0, 1.0)
                r, g, b = _lerp(0.85, 0.75, shade), _lerp(0.90, 0.82, shade), _lerp(0.95, 0.90, shade)
            elif land > 0.45:
                shade = _clamp(land, 0.0, 1.0)
                r = _lerp(0.24, 0.38, shade * 0.45)
                g = _lerp(0.42, 0.36, shade * 0.45)
                b_temp = _lerp(0.31, 0.24, shade * 0.45)
                lat_tint = _clamp(1.0 - abs(lat_deg) / 60.0, 0.0, 0.35)
                r = _lerp(r, 0.32, lat_tint)
                g = _lerp(g, 0.48, lat_tint)
                b_temp = _lerp(b_temp, 0.28, lat_tint)
                r, g, b = r, g, b_temp
            else:
                deep_r, deep_g, deep_b = 0.08, 0.26, 0.45
                shallow_r, shallow_g, shallow_b = 0.12, 0.40, 0.55
                t = 0.45 + 0.35 * math.sin(lat_rad)
                r = _lerp(deep_r, shallow_r, t)
                g = _lerp(deep_g, shallow_g, t)
                b = _lerp(deep_b, shallow_b, t)

            idx = (y * W + x) * 3
            buf[idx] = int(_clamp(r, 0, 1) * 255)
            buf[idx + 1] = int(_clamp(g, 0, 1) * 255)
            buf[idx + 2] = int(_clamp(b, 0, 1) * 255)
    return bytes(buf)


def main() -> int:
    raw = make_raw()
    OUT.parent.mkdir(parents=True, exist_ok=True)

    # Write via ffmpeg: rawvideo → PNG
    result = subprocess.run(
        [
            "ffmpeg", "-y", "-v", "quiet",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
            "-i", "pipe:0", str(OUT),
        ],
        input=raw, timeout=60,
    )
    if result.returncode != 0:
        print("ffmpeg failed", file=sys.stderr)
        return 1
    print(f"OK: {OUT}  ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
