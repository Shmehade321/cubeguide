#!/usr/bin/env python3
"""Generate CubeGuide's original non-speech PCM masters and bundled AAC effects."""

import math
import pathlib
import struct
import subprocess
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
MASTERS = ROOT / "Assets" / "AudioMasters"
BUNDLE = ROOT / "cubeguide"
RATE = 44_100


def envelope(index: int, count: int) -> float:
    attack = min(1.0, index / (RATE * 0.012))
    release = min(1.0, (count - index - 1) / (RATE * 0.035))
    return max(0.0, min(attack, release))


def render(identifier: str, seconds: float, sample) -> None:
    count = int(RATE * seconds)
    MASTERS.mkdir(parents=True, exist_ok=True)
    wav_path = MASTERS / f"{identifier}.wav"
    with wave.open(str(wav_path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        frames = []
        for index in range(count):
            value = max(-0.82, min(0.82, sample(index / RATE))) * envelope(index, count)
            frames.append(struct.pack("<h", round(value * 32767)))
        output.writeframes(b"".join(frames))
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav_path),
         "-ac", "1", "-ar", str(RATE), "-c:a", "aac", "-b:a", "96k",
         str(BUNDLE / f"{identifier}.m4a")],
        check=True,
    )


render("E01", 0.12, lambda t: 0.34 * math.sin(2 * math.pi * 880 * t))
render("E02", 0.20, lambda t: 0.28 * math.sin(2 * math.pi * (440 if t < 0.09 else 330) * t))
render(
    "E03", 0.72,
    lambda t: 0.18 * sum(math.sin(2 * math.pi * frequency * t)
                         for frequency in ((523.25, 659.25, 783.99) if t < 0.34
                                           else (659.25, 783.99, 1046.50))),
)
