#!/usr/bin/env python3
"""Synthesize Demo audio pack (bgm_globe_day + P0 SFX) → Ogg + AUDIO_MANIFEST.csv.

Deterministic seeds. Prefer CC0 UI files if --prefer-cc0 and markers exist.
Requires: numpy, ffmpeg on PATH.
"""
from __future__ import annotations

import argparse
import csv
import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "game" / "assets" / "audio"
BGM_DIR = AUDIO / "bgm"
SFX_DIR = AUDIO / "sfx"
CACHE = Path(__file__).resolve().parent / "_cc0_cache"
SR = 48000
SEED = 20260726


def _fade(n: int, fade_in: int = 0, fade_out: int = 0) -> np.ndarray:
    env = np.ones(n, dtype=np.float64)
    if fade_in > 0:
        fi = min(fade_in, n)
        env[:fi] *= np.linspace(0, 1, fi)
    if fade_out > 0:
        fo = min(fade_out, n)
        env[-fo:] *= np.linspace(1, 0, fo)
    return env


def _stereo(mono: np.ndarray, width: float = 0.15) -> np.ndarray:
    """Simple stereo from mono with slight L/R delay."""
    delay = int(SR * 0.008 * width)
    left = mono
    right = np.zeros_like(mono)
    if delay > 0:
        right[delay:] = mono[:-delay]
        right[:delay] = mono[:delay] * 0.5
    else:
        right = mono
    # slight balance
    return np.stack([left * 0.98, right * 1.02], axis=1)


def _normalize(x: np.ndarray, peak: float = 0.35) -> np.ndarray:
    m = np.max(np.abs(x)) + 1e-12
    return (x / m) * peak


def _tone(
    freq: float,
    dur_s: float,
    *,
    amp: float = 0.3,
    attack: float = 0.005,
    release: float = 0.04,
    noise: float = 0.0,
    seed: int = 0,
) -> np.ndarray:
    n = int(SR * dur_s)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    sig = np.sin(2 * math.pi * freq * t) * amp
    if noise > 0:
        sig += rng.normal(0, noise, n)
    sig *= _fade(n, int(attack * SR), int(release * SR))
    return sig


def _chirp(f0: float, f1: float, dur_s: float, amp: float = 0.25, seed: int = 0) -> np.ndarray:
    n = int(SR * dur_s)
    t = np.arange(n) / SR
    phase = 2 * math.pi * (f0 * t + (f1 - f0) * t * t / (2 * dur_s))
    sig = np.sin(phase) * amp
    sig *= _fade(n, int(0.01 * SR), int(0.05 * SR))
    return sig


def write_wav(path: Path, stereo: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(stereo, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def wav_to_ogg(wav: Path, ogg: Path) -> None:
    """Encode WAV → Ogg Vorbis via oggenc, else ffmpeg vorbis, else fail."""
    ogg.parent.mkdir(parents=True, exist_ok=True)
    # Prefer vorbis-tools oggenc (reliable on macOS Homebrew ffmpeg builds)
    try:
        subprocess.run(
            ["oggenc", "-q", "5", "-o", str(ogg), str(wav)],
            check=True,
            capture_output=True,
        )
        return
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    # Fallback: ffmpeg native vorbis encoder
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", str(wav),
        "-c:a", "vorbis", "-strict", "-2", "-q:a", "5",
        str(ogg),
    ]
    subprocess.run(cmd, check=True)


def synth_bgm_globe_day() -> np.ndarray:
    """~135s ambient pad + sparse pulses, loop-friendly fades."""
    rng = np.random.default_rng(SEED)
    dur = 135.0
    n = int(SR * dur)
    t = np.arange(n) / SR
    # layered slow pads
    freqs = [110.0, 164.8, 220.0, 329.6]  # A2-ish stack
    sig = np.zeros(n)
    for i, f in enumerate(freqs):
        lfo = 0.5 + 0.5 * np.sin(2 * math.pi * (0.03 + i * 0.007) * t)
        sig += np.sin(2 * math.pi * f * t + 0.3 * np.sin(2 * math.pi * 0.05 * t)) * (0.08 / (i + 1)) * lfo
    # sparse soft pulses every ~4s
    pulse_len = int(0.35 * SR)
    for k in range(0, n - pulse_len, int(4.0 * SR)):
        offset = int(rng.uniform(0, 0.4) * SR)
        i0 = k + offset
        if i0 + pulse_len >= n:
            break
        pt = np.arange(pulse_len) / SR
        pulse = np.sin(2 * math.pi * 523.25 * pt) * np.exp(-pt * 6) * 0.06
        sig[i0 : i0 + pulse_len] += pulse
    # very light noise bed
    sig += rng.normal(0, 0.004, n)
    sig *= _fade(n, int(2.0 * SR), int(2.0 * SR))
    sig = _normalize(sig, peak=0.28)
    return _stereo(sig, width=0.25)


def synth_sfx(sid: str) -> tuple[np.ndarray, dict]:
    """Return stereo samples + manifest meta."""
    meta = {"bus": "SFX", "loop": "false", "loop_start_ms": "", "loop_end_ms": ""}
    if sid == "sfx_ui_click":
        mono = _tone(880, 0.06, amp=0.35, attack=0.001, release=0.04, noise=0.02, seed=1)
        meta["bus"] = "UI"
    elif sid == "sfx_ui_hover":
        mono = _tone(1200, 0.03, amp=0.15, attack=0.001, release=0.02, noise=0.01, seed=2)
        meta["bus"] = "UI"
    elif sid == "sfx_ui_open_panel":
        mono = _chirp(400, 700, 0.12, amp=0.22, seed=3)
        meta["bus"] = "UI"
    elif sid == "sfx_ui_close_panel":
        mono = _chirp(700, 400, 0.1, amp=0.2, seed=4)
        meta["bus"] = "UI"
    elif sid == "sfx_search_type":
        mono = _tone(1400, 0.02, amp=0.1, attack=0.001, release=0.015, seed=5)
        meta["bus"] = "UI"
    elif sid == "sfx_airport_select":
        a = _tone(660, 0.08, amp=0.28, seed=6)
        b = _tone(990, 0.08, amp=0.22, attack=0.01, release=0.05, seed=7)
        mono = np.zeros(int(0.12 * SR))
        mono[: len(a)] += a
        mono[int(0.04 * SR) : int(0.04 * SR) + len(b)] += b
    elif sid == "sfx_buy":
        base = _tone(523.25, 0.15, amp=0.3, seed=8)  # C5
        harm = _tone(659.25, 0.12, amp=0.18, attack=0.02, release=0.08, seed=9)
        mono = np.zeros(max(len(base), len(harm)))
        mono[: len(base)] += base
        mono[: len(harm)] += harm
    elif sid == "sfx_sell":
        # ~2–3 semitones above buy
        base = _tone(622.25, 0.15, amp=0.3, seed=10)  # D#5
        harm = _tone(783.99, 0.12, amp=0.18, attack=0.02, release=0.08, seed=11)
        mono = np.zeros(max(len(base), len(harm)))
        mono[: len(base)] += base
        mono[: len(harm)] += harm
    elif sid == "sfx_error":
        base = _tone(180, 0.2, amp=0.35, attack=0.005, release=0.1, noise=0.03, seed=12)
        harm = _tone(140, 0.15, amp=0.2, seed=13)
        mono = np.zeros(max(len(base), len(harm)))
        mono[: len(base)] += base
        mono[: len(harm)] += harm
    elif sid == "sfx_ticket_ok":
        mono = np.zeros(int(0.25 * SR))
        for i, f in enumerate([440, 554, 659]):
            ton = _tone(f, 0.1, amp=0.22, seed=14 + i)
            off = int(0.05 * i * SR)
            mono[off : off + len(ton)] += ton
    elif sid == "sfx_ff_confirm":
        mono = _chirp(300, 900, 0.2, amp=0.25, seed=20)
    elif sid == "sfx_boarding_alert":
        n = int(0.55 * SR)
        mono = np.zeros(n)
        pulse = _tone(740, 0.12, amp=0.4, attack=0.002, release=0.08, seed=21)
        mono[: len(pulse)] += pulse
        mono[int(0.22 * SR) : int(0.22 * SR) + len(pulse)] += pulse * 0.95
    elif sid == "sfx_takeoff":
        # ~1.6s rising whoosh
        dur = 1.6
        n = int(SR * dur)
        t = np.arange(n) / SR
        rng = np.random.default_rng(30)
        noise = rng.normal(0, 0.15, n)
        # lowpass-ish by cumulative mean
        kern = np.ones(64) / 64
        noise = np.convolve(noise, kern, mode="same")
        rise = np.linspace(0.15, 1.0, n)
        bass = np.sin(2 * math.pi * (80 + 40 * t / dur) * t) * 0.2 * rise
        mono = (noise * 0.35 * rise + bass) * _fade(n, int(0.05 * SR), int(0.15 * SR))
        meta["bus"] = "Transition"
    elif sid == "sfx_cruise":
        dur = 1.8
        n = int(SR * dur)
        t = np.arange(n) / SR
        rng = np.random.default_rng(31)
        noise = np.convolve(rng.normal(0, 0.08, n), np.ones(128) / 128, mode="same")
        hum = np.sin(2 * math.pi * 95 * t) * 0.12
        mono = (noise + hum) * _fade(n, int(0.1 * SR), int(0.1 * SR))
        meta["bus"] = "Transition"
        meta["loop"] = "true"
        meta["loop_start_ms"] = "100"
        meta["loop_end_ms"] = str(int(dur * 1000) - 100)
    elif sid == "sfx_landing":
        dur = 1.6
        n = int(SR * dur)
        t = np.arange(n) / SR
        rng = np.random.default_rng(32)
        noise = np.convolve(rng.normal(0, 0.12, n), np.ones(48) / 48, mode="same")
        fall = np.linspace(1.0, 0.2, n)
        bass = np.sin(2 * math.pi * (120 - 50 * t / dur) * t) * 0.18 * fall
        mono = (noise * 0.3 * fall + bass) * _fade(n, int(0.05 * SR), int(0.2 * SR))
        meta["bus"] = "Transition"
    elif sid == "sfx_arrive":
        mono = np.zeros(int(0.3 * SR))
        for i, f in enumerate([523.25, 659.25, 783.99]):
            ton = _tone(f, 0.12, amp=0.25, seed=40 + i)
            off = int(0.06 * i * SR)
            mono[off : off + len(ton)] += ton
    else:
        raise ValueError(f"unknown sfx id: {sid}")

    mono = _normalize(mono, peak=0.4 if meta["bus"] != "UI" else 0.32)
    return _stereo(mono, width=0.1), meta


P0_SFX = [
    "sfx_ui_click",
    "sfx_ui_hover",
    "sfx_ui_open_panel",
    "sfx_ui_close_panel",
    "sfx_search_type",
    "sfx_airport_select",
    "sfx_buy",
    "sfx_sell",
    "sfx_error",
    "sfx_ticket_ok",
    "sfx_ff_confirm",
    "sfx_boarding_alert",
    "sfx_takeoff",
    "sfx_cruise",
    "sfx_landing",
    "sfx_arrive",
]


def _cc0_meta(sid: str) -> dict | None:
    marker = CACHE / f"{sid}.cc0"
    if not marker.exists():
        return None
    data = {}
    for line in marker.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip()
    return data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefer-cc0", action="store_true", help="Keep existing CC0 UI oggs if present")
    ap.add_argument("--keep-wav", action="store_true")
    args = ap.parse_args()

    BGM_DIR.mkdir(parents=True, exist_ok=True)
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    tmp = AUDIO / "_tmp_wav"
    tmp.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []

    # BGM
    print("Synthesizing bgm_globe_day ...")
    bgm = synth_bgm_globe_day()
    wav = tmp / "audio_bgm_globe_day.wav"
    ogg = BGM_DIR / "audio_bgm_globe_day.ogg"
    write_wav(wav, bgm)
    wav_to_ogg(wav, ogg)
    rows.append({
        "id": "bgm_globe_day",
        "filename": "bgm/audio_bgm_globe_day.ogg",
        "license": "original-procedural",
        "author": "Airborne Trader / audio-gen-kit",
        "source_url": "",
        "source": "procedural",
        "loop": "true",
        "loop_start_ms": "8000",
        "loop_end_ms": "133000",
        "bus": "BGM",
        "notes": "Demo P0 ambient pad; ~135s",
    })

    for sid in P0_SFX:
        dest = SFX_DIR / f"audio_{sid}.ogg"
        cc0 = _cc0_meta(sid) if args.prefer_cc0 else None
        if args.prefer_cc0 and dest.exists() and cc0:
            print(f"  keep CC0 {sid}")
            rows.append({
                "id": sid,
                "filename": f"sfx/audio_{sid}.ogg",
                "license": cc0.get("license", "CC0"),
                "author": cc0.get("author", "Kenney"),
                "source_url": cc0.get("source_url", ""),
                "source": "cc0",
                "loop": "false",
                "loop_start_ms": "",
                "loop_end_ms": "",
                "bus": "UI",
                "notes": f"Kenney UI Audio: {cc0.get('file', '')}",
            })
            continue

        print(f"  synth {sid}")
        stereo, meta = synth_sfx(sid)
        wav = tmp / f"audio_{sid}.wav"
        write_wav(wav, stereo)
        wav_to_ogg(wav, dest)
        rows.append({
            "id": sid,
            "filename": f"sfx/audio_{sid}.ogg",
            "license": "original-procedural",
            "author": "Airborne Trader / audio-gen-kit",
            "source_url": "",
            "source": "procedural",
            "loop": meta["loop"],
            "loop_start_ms": meta["loop_start_ms"],
            "loop_end_ms": meta["loop_end_ms"],
            "bus": meta["bus"],
            "notes": "Demo P0 procedural",
        })

    manifest = AUDIO / "AUDIO_MANIFEST.csv"
    fields = [
        "id", "filename", "license", "author", "source_url", "source",
        "loop", "loop_start_ms", "loop_end_ms", "bus", "notes",
    ]
    with manifest.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    if not args.keep_wav:
        for p in tmp.glob("*.wav"):
            p.unlink()
        try:
            tmp.rmdir()
        except OSError:
            pass

    print(f"Wrote {len(rows)} entries → {manifest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FileNotFoundError as e:
        print(f"Missing dependency: {e}. Install ffmpeg and numpy.", file=sys.stderr)
        raise SystemExit(2)
    except subprocess.CalledProcessError as e:
        print(f"ffmpeg failed: {e}", file=sys.stderr)
        raise SystemExit(2)
