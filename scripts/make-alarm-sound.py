#!/usr/bin/env python3
"""Generate sounds/alarm.oga, so the sound's origin and license are plain: it is
synthesized here and covered by this repo's MIT license.

A soft mallet-style figure kept low on purpose. Pure tones with a little second
harmonic and no energy near the 2-5 kHz range where hearing is most sensitive.

Usage: scripts/make-alarm-sound.py sounds/alarm.oga
Needs numpy and ffmpeg.
"""
import subprocess
import sys

import numpy as np

RATE = 44100
NOTES = [(0.00, 392.00), (0.28, 523.25), (0.56, 659.25)]  # G4, C5, E5
LENGTH = 2.2
PEAK = 0.55

t = np.arange(int(LENGTH * RATE)) / RATE
out = np.zeros_like(t)
for start, freq in NOTES:
    local = np.clip(t - start, 0, None)
    attack = np.clip(local / 0.012, 0, 1)  # A hard onset clicks, and a click is what startles.
    decay = np.exp(-local * 2.6)
    tone = np.sin(2 * np.pi * freq * local) + 0.12 * np.sin(4 * np.pi * freq * local)
    out += (t >= start) * attack * decay * tone

fade = np.clip((LENGTH - t) / 0.15, 0, 1)  # End on silence so the loop has no pop.
out = out * fade
out = out / np.abs(out).max() * PEAK

subprocess.run(
    ["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
     "-c:a", "libvorbis", "-q:a", "5", sys.argv[1]],
    input=out.astype(np.float32).tobytes(), check=True)
