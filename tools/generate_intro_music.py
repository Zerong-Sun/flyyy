"""Generate the original 30-second opening theme (PCM master for Godot)."""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

RATE = 32000
DURATION = 30
OUT = Path(__file__).resolve().parents[1] / 'game/assets/audio/bgm/audio_bgm_intro.wav'
rng = np.random.default_rng(2407)
mix = np.zeros(RATE * DURATION, dtype=np.float64)


def add(start: float, signal: np.ndarray, gain: float = 1.0) -> None:
    begin = round(start * RATE)
    end = min(begin + len(signal), len(mix))
    if begin < len(mix) and end > begin:
        mix[begin:end] += gain * signal[:end - begin]


def tone(note: int, length: float, kind: str) -> np.ndarray:
    t = np.arange(round(length * RATE)) / RATE
    hz = 440 * 2 ** ((note - 69) / 12)
    phase = 2 * np.pi * hz * t
    if kind == 'flute':
        vibrato = 0.018 * np.sin(2 * np.pi * 5.1 * t)
        sound = np.sin(phase + vibrato) + .14 * np.sin(2 * phase)
        envelope = np.minimum(1, t / .085) * np.minimum(1, (length - t) / .18)
    elif kind == 'plucked':
        sound = np.sin(phase) + .24 * np.sin(2 * phase) + .10 * np.sin(3 * phase)
        envelope = np.minimum(1, t / .008) * np.exp(-t * 4.6) * np.minimum(1, (length - t) / .07)
    else:  # soft drone, with breath-like motion
        sound = np.sin(phase) + .17 * np.sin(2 * phase)
        envelope = np.minimum(1, t / .22) * np.minimum(1, (length - t) / .4)
        envelope *= .87 + .13 * np.sin(2 * np.pi * .7 * t)
    return sound * np.clip(envelope, 0, 1)


def drum(at: float, strong: bool = False) -> None:
    length = .22 if strong else .14
    t = np.arange(round(length * RATE)) / RATE
    pitch = (88 if strong else 155) * np.exp(-t * 22) + (56 if strong else 110)
    phase = 2 * np.pi * np.cumsum(pitch) / RATE
    body = np.sin(phase) * np.exp(-t * (25 if strong else 43))
    noise = rng.standard_normal(len(t)) * np.exp(-t * 65) * (.10 if strong else .045)
    add(at, body + noise, .23 if strong else .12)


# D minor pentatonic with a short E-flat passing note: a shared modal colour,
# using flute, plucked-string and hand-drum timbres rather than quoting folk melodies.
melody = [
    (0.08, 74, .72), (1.05, 77, .65), (1.95, 79, .72),
    (2.85, 81, .75), (3.78, 84, .58), (4.48, 81, .45),
    (5.04, 79, .38), (5.47, 77, .34), (5.87, 79, .35),
    (6.26, 81, .33), (6.64, 84, .36), (7.02, 86, .42),
    (7.49, 84, .45), (8.01, 81, .65), (8.79, 79, .66), (9.55, 77, .38),
]
for section in range(3):
    offset = 10 * section
    for at, note, length in melody:
        # Front-load the hook; later cycles sit lower and calmer under the title.
        selected = note if section == 0 else note - 12
        add(offset + at, tone(selected, length, 'flute'), .23 if section == 0 else .15)
        add(offset + at + .015, tone(selected - 12, min(length, .55), 'plucked'), .16)
    for at, note in [(0.1, 50), (2.1, 57), (4.1, 53), (6.1, 55), (8.1, 50)]:
        add(offset + at, tone(note, 1.8, 'drone'), .10)
    # The pulse rises at 4–8 seconds, then breathes out. Repeat softly afterward.
    for at in [1.1, 3.1, 4.55, 5.3, 5.75, 6.15, 6.52, 6.9, 7.3, 7.8, 8.6]:
        drum(offset + at, at in (4.55, 6.15, 7.8))

# Small, diffuse echo helps the separate timbres feel like one journey.
for delay, level in [(.17, .105), (.41, .075)]:
    samples = round(delay * RATE)
    mix[samples:] += level * mix[:-samples].copy()
# A brief release avoids a click when a player loops the file at 30 seconds.
release = round(.24 * RATE)
mix[-release:] *= np.linspace(1, 0, release)
mix[:round(.02 * RATE)] *= np.linspace(0, 1, round(.02 * RATE))
peak = np.max(np.abs(mix))
assert peak > 0
mix *= .78 / peak
OUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUT), 'wb') as file:
    file.setnchannels(1)
    file.setsampwidth(2)
    file.setframerate(RATE)
    file.writeframes((mix * 32767).astype('<i2').tobytes())
print(f'{OUT}: {DURATION}s, {RATE} Hz, peak {np.max(np.abs(mix)):.3f}')
