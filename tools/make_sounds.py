"""Generates the car sound effects for RRS (no external libraries needed).

    python tools/make_sounds.py

Writes mono 16-bit WAV files to assets/audio/car/. Looping sounds carry a
'smpl' loop chunk, which Godot's WAV importer picks up automatically.

Engine model: a 4-cylinder fires twice per crank revolution, so the main
tone is rpm / 30 Hz. Each layer is recorded at a fixed rpm and the game
pitch-shifts and cross-fades four layers (low/high rpm x on/off throttle).
"""
import math
import os
import random
import struct

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio", "car")
TAU = 2.0 * math.pi


# --- helpers -------------------------------------------------------------------

def write_wav(name, samples, loop):
    peak = max(1e-6, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.85)) * 32767)) for s in samples)
    n = len(samples)
    fmt = struct.pack("<HHIIHH", 1, 1, RATE, RATE * 2, 2, 16)
    body = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)
    print("wrote", name, "%.2fs" % (n / RATE), "loop" if loop else "")


def loop_crossfade(samples, fade):
    """Make a loop seamless: the extra tail is faded into the start."""
    body = samples[:-fade]
    tail = samples[-fade:]
    for i in range(fade):
        w = i / fade
        body[i] = body[i] * w + tail[i] * (1.0 - w)
    return body


class Biquad:
    """RBJ band-pass / low-pass / high-pass filter."""

    def __init__(self, kind, freq, q=0.707):
        w = TAU * freq / RATE
        alpha = math.sin(w) / (2 * q)
        c = math.cos(w)
        if kind == "lp":
            b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        elif kind == "hp":
            b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        else:  # band-pass, 0 dB peak
            b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * c, 1 - alpha]
        self.b = [x / a[0] for x in b]
        self.a = [x / a[0] for x in a]
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def __call__(self, x):
        y = self.b[0] * x + self.b[1] * self.x1 + self.b[2] * self.x2 - self.a[1] * self.y1 - self.a[2] * self.y2
        self.x2, self.x1, self.y2, self.y1 = self.x1, x, self.y1, y
        return y


def soft_clip(samples, drive):
    k = math.tanh(drive)
    return [math.tanh(drive * s) / k for s in samples]


# --- engine --------------------------------------------------------------------

def engine(base_hz, seconds, brightness, noise_amt, rumble, seed):
    """One engine layer at a fixed rpm (base_hz = firing frequency)."""
    rng = random.Random(seed)
    n = int(RATE * seconds)
    cycles = int(round(base_hz * seconds))
    harmonics = max(8, min(40, int(4500 / base_hz)))
    amps, phases = [], []
    for k in range(1, harmonics + 1):
        f = k * base_hz
        a = 1.0 / (k ** brightness)
        # Exhaust / intake resonances give the engine its character.
        a *= 1.0 + 1.8 * math.exp(-((f - 650) / 260) ** 2) + 0.9 * math.exp(-((f - 1900) / 600) ** 2)
        amps.append(a)
        phases.append(rng.uniform(0, TAU))
    # Combustion is never perfectly even: a little variation per firing.
    jitter = [1.0 + rng.uniform(-0.18, 0.18) for _ in range(cycles)]
    hiss = Biquad("bp", 1400, 0.6)
    out = []
    fade = 2000
    for i in range(n + fade):
        t = i / RATE
        pos = t * base_hz
        c0 = int(pos) % cycles
        frac = pos - int(pos)
        j = jitter[c0] * (1 - frac) + jitter[(c0 + 1) % cycles] * frac
        s = 0.0
        w = TAU * base_hz * t
        for k in range(harmonics):
            s += amps[k] * math.sin((k + 1) * w + phases[k])
        s += rumble * math.sin(0.5 * w)  # uneven crank: half-order rumble
        pulse = max(0.0, math.sin(w)) ** 2
        s = s * j + noise_amt * hiss(rng.uniform(-1, 1)) * (0.4 + pulse) * 6.0
        out.append(s)
    # Harmonics repeat exactly; the crossfade hides the noise seam.
    out = loop_crossfade(out, fade)
    peak = max(abs(x) for x in out)
    return soft_clip([x / peak for x in out], 1.8)


# --- tyres, surface, wind, impact ------------------------------------------------

def tire_squeal(seconds=1.5, seed=3):
    rng = random.Random(seed)
    n = int(RATE * seconds)
    f0 = 520.0  # integer cycles per loop (780)
    partials = [(1.0, 1.0), (1.5, 0.55), (2.0, 0.35), (3.0, 0.12)]
    # Periodic wobble (integer LFO cycles over the loop keeps it seamless).
    lfos = [(4.0 / seconds, 0.018), (9.0 / seconds, 0.011), (17.0 / seconds, 0.006)]
    hiss = Biquad("bp", 2600, 0.8)
    phase = [0.0] * len(partials)
    out = []
    for i in range(n + 2000):
        t = i / RATE
        mod = sum(d * math.sin(TAU * f * t + k) for k, (f, d) in enumerate(lfos))
        am = 0.75 + 0.25 * math.sin(TAU * (7.0 / seconds) * t) * math.sin(TAU * (3.0 / seconds) * t + 1.0)
        s = 0.0
        for p, (ratio, amp) in enumerate(partials):
            phase[p] += TAU * f0 * ratio * (1.0 + mod) / RATE
            s += amp * math.sin(phase[p])
        s = s * am + 0.35 * hiss(rng.uniform(-1, 1)) * 3.0
        out.append(s)
    return soft_clip(loop_crossfade(out, 2000), 1.3)


def dirt_rumble(seconds=2.0, seed=5):
    rng = random.Random(seed)
    lp = Biquad("lp", 260, 0.9)
    lp2 = Biquad("lp", 900, 0.7)
    out = []
    for i in range(int(RATE * seconds) + 3000):
        s = lp(rng.uniform(-1, 1)) * 3.0
        if rng.random() < 0.004:  # stones and clods hitting the floor
            s += rng.uniform(-1, 1) * 2.5
        out.append(lp2(s))
    return loop_crossfade(out, 3000)


def wind(seconds=2.5, seed=7):
    rng = random.Random(seed)
    bp = Biquad("bp", 500, 0.5)
    lp = Biquad("lp", 1800, 0.7)
    out = []
    for i in range(int(RATE * seconds) + 4000):
        t = i / RATE
        gust = 0.75 + 0.25 * math.sin(TAU * t / seconds * 2) * math.sin(TAU * t / seconds * 3 + 0.7)
        out.append(lp(bp(rng.uniform(-1, 1))) * gust)
    return loop_crossfade(out, 4000)


def impact(seconds=0.45, seed=9):
    rng = random.Random(seed)
    lp = Biquad("lp", 700, 0.8)
    out = []
    for i in range(int(RATE * seconds)):
        t = i / RATE
        body = math.sin(TAU * 62 * t) * math.exp(-t * 12) + 0.6 * math.sin(TAU * 118 * t) * math.exp(-t * 18)
        crunch = lp(rng.uniform(-1, 1)) * math.exp(-t * 22) * 2.5
        out.append(body + crunch)
    return soft_clip(out, 2.0)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    # 50 Hz = 1500 rpm, 150 Hz = 4500 rpm (2 s loops hold whole cycles).
    write_wav("engine_low_on.wav", engine(50.0, 2.0, 0.95, 0.35, 0.35, 11), True)
    write_wav("engine_low_off.wav", engine(50.0, 2.0, 1.5, 0.12, 0.45, 12), True)
    write_wav("engine_high_on.wav", engine(150.0, 2.0, 0.85, 0.3, 0.25, 13), True)
    write_wav("engine_high_off.wav", engine(150.0, 2.0, 1.45, 0.1, 0.3, 14), True)
    write_wav("tire_squeal.wav", tire_squeal(), True)
    write_wav("dirt_rumble.wav", dirt_rumble(), True)
    write_wav("wind.wav", wind(), True)
    write_wav("impact.wav", impact(), False)
