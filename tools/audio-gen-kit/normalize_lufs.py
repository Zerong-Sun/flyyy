#!/usr/bin/env python3
"""Normalize game BGM to CAS §2 loudness targets using ffmpeg loudnorm.

CAS §2.2 targets:
  - bgm_globe_day / bgm_market / bgm_night : -16 LUFS (range -16..-14)
  - bgm_menu                              : -18 LUFS

Usage:
  python3 tools/audio-gen-kit/normalize_lufs.py            # normalize to targets, in place
  python3 tools/audio-gen-kit/normalize_lufs.py --dry-run  # measure + print table only

Requirements: ffmpeg (with ebur128 filter) on PATH.
Prints a before/after loudness table; writes normalized files over the .ogg in place.
Godot loads these at runtime via AudioStreamOggVorbis.load_from_file(), so the
.import cache does not need regenerating.
"""

import argparse
import subprocess
import sys
from pathlib import Path

BGM_DIR = Path(__file__).resolve().parents[2] / "game" / "assets" / "audio" / "bgm"

# filename -> target integrated loudness (LUFS)
TARGETS = {
    "audio_bgm_globe_day.ogg": -16.0,
    "audio_bgm_market.ogg": -16.0,
    "audio_bgm_night.ogg": -16.0,
    "audio_bgm_menu.ogg": -18.0,
}

TP = -1.5  # true peak ceiling


def measure_lufs(path: Path) -> float | None:
    """Return integrated loudness (LUFS) via ebur128."""
    cmd = [
        "ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
        "-af", "ebur128=framelog=quiet", "-f", "null", "-",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    out = proc.stderr or ""
    for line in out.splitlines():
        if line.strip() == "I:":
            continue
        if line.strip().startswith("I:"):
            parts = line.strip().split()
            try:
                return float(parts[1].removesuffix("LUFS"))
            except (ValueError, IndexError):
                return None
    return None


def normalize(path: Path, target: float, dry_run: bool) -> tuple[float | None, float | None]:
    before = measure_lufs(path)
    if before is None:
        print(f"  SKIP {path.name}: measure failed")
        return before, None
    tmp = path.with_suffix(".norm.ogg")
    # loudnorm dynamic mode with linear gain applied; keeps the source tone.
    cmd = [
        "ffmpeg", "-hide_banner", "-y", "-i", str(path),
        "-af", f"loudnorm=I={target}:TP={TP}:LRA=11",
        "-c:a", "vorbis", "-strict", "-2", "-q:a", "5", str(tmp),
    ]
    if dry_run:
        print(f"  WOULD normalize {path.name}: {before:.1f} -> {target} LUFS")
        return before, None
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"  FAIL {path.name}:\n{proc.stderr[-2000:]}")
        return before, None
    after = measure_lufs(tmp)
    if after is not None:
        tmp.replace(path)
    return before, after


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize BGM to CAS §2 loudness targets")
    parser.add_argument("--dry-run", action="store_true", help="measure and print only")
    args = parser.parse_args()

    if not BGM_DIR.is_dir():
        print(f"ERROR: {BGM_DIR} not found", file=sys.stderr)
        return 1

    print(f"{'file':<28} {'before':>8} {'target':>8} {'after':>8}")
    print("-" * 60)
    ok = True
    for filename, target in TARGETS.items():
        path = BGM_DIR / filename
        if not path.exists():
            print(f"  MISSING {filename}")
            ok = False
            continue
        before, after = normalize(path, target, args.dry_run)
        after_s = f"{after:+.1f}" if after is not None else "-"
        before_s = f"{before:+.1f}" if before is not None else "-"
        print(f"{filename:<28} {before_s:>8} {target:>8.1f} {after_s:>8}")
        if after is not None and abs(after - target) > 1.5:
            print(f"  WARN {filename} normalized to {after:.1f}, still >1.5 LUFS from target")
    print("\nDone. Re-run with --dry-run to confirm targets.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
