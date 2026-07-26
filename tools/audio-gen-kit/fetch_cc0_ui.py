#!/usr/bin/env python3
"""Optional: download Kenney UI Audio (CC0) for click/panel SFX.

Falls back silently if network fails. Synthesize script uses procedural audio
when CC0 files are missing.
"""
from __future__ import annotations

import io
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(__file__).resolve().parent / "_cc0_cache"
OUT_SFX = ROOT / "game" / "assets" / "audio" / "sfx"

# Kenney UI Audio (CC0) — try official site then GitHub mirror
ZIP_URLS = [
    "https://kenney.nl/media/pages/assets/ui-audio/0aee44be53-1673019784/kenney_ui-audio.zip",
    "https://github.com/Calinou/kenney-ui-audio/archive/refs/heads/master.zip",
]

# Map our IDs → preferred filenames inside Kenney pack (best-effort)
MAP = {
    "sfx_ui_click": ["click1.wav", "click2.wav", "click3.wav"],
    "sfx_ui_hover": ["rollover1.wav", "rollover2.wav", "rollover3.wav"],
    "sfx_ui_open_panel": ["switch1.wav", "switch2.wav", "switch3.wav"],
    "sfx_ui_close_panel": ["switch4.wav", "switch5.wav", "mouserelease1.wav"],
}


def main() -> int:
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT_SFX.mkdir(parents=True, exist_ok=True)
    zip_path = CACHE / "kenney_ui-audio.zip"
    last_err: Exception | None = None
    used_url = ""
    for url in ZIP_URLS:
        try:
            print(f"Fetching {url} ...")
            urllib.request.urlretrieve(url, zip_path)
            used_url = url
            break
        except Exception as e:
            last_err = e
            print(f"  failed: {e}")
    if not used_url:
        print(f"CC0 fetch failed ({last_err}); synthesize will use procedural UI SFX.", file=sys.stderr)
        return 1

    with zipfile.ZipFile(zip_path) as zf:
        names = {}
        for n in zf.namelist():
            low = Path(n).name.lower()
            if low.endswith((".ogg", ".wav")):
                names[low] = n
        copied = 0
        used: set[str] = set()
        for sid, candidates in MAP.items():
            src_name = None
            for c in candidates:
                key = c.lower()
                if key in names and names[key] not in used:
                    src_name = names[key]
                    break
            if not src_name:
                for key, full in names.items():
                    if full in used:
                        continue
                    if any(tok in key for tok in ("click", "switch", "rollover")):
                        src_name = full
                        break
            if not src_name:
                continue
            used.add(src_name)
            dest = OUT_SFX / f"audio_{sid}.ogg"
            raw = zf.read(src_name)
            if src_name.lower().endswith(".wav"):
                # convert via oggenc/ffmpeg
                tmp_wav = CACHE / f"_tmp_{sid}.wav"
                tmp_wav.write_bytes(raw)
                try:
                    subprocess.run(
                        ["oggenc", "-q", "5", "-o", str(dest), str(tmp_wav)],
                        check=True,
                        capture_output=True,
                    )
                except Exception:
                    subprocess.run(
                        [
                            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                            "-i", str(tmp_wav), "-c:a", "vorbis", "-strict", "-2", str(dest),
                        ],
                        check=True,
                    )
                tmp_wav.unlink(missing_ok=True)
            else:
                dest.write_bytes(raw)
            (CACHE / f"{sid}.cc0").write_text(
                f"license=CC0\nauthor=Kenney\nsource_url={used_url}\nfile={src_name}\n",
                encoding="utf-8",
            )
            print(f"  CC0 → {dest.name} ({src_name})")
            copied += 1
    print(f"Done. Copied {copied} UI sounds.")
    return 0 if copied else 1


if __name__ == "__main__":
    raise SystemExit(main())
