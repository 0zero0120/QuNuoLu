"""生成三章无缝循环背景音乐（以及一层很轻的环境风声）。

全部用 numpy/scipy 合成，不依赖任何外部音源，输出 OGG 到 assets/audio/bgm/。
设计口径：慢速、五声音阶/教会调式、软起音、无 55Hz 拍频嗡鸣、无高频毛刺。
每首的时间轴都按「圆」来算：音符尾、混响尾、和弦交叉淡化都绕回开头，
所以循环点不需要淡入淡出也不会「咔」。

    python tools/generate_bgm.py

依赖：numpy scipy soundfile
"""
from __future__ import annotations

import math
import os

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "audio", "bgm")
RNG = np.random.default_rng(20261020)


# --- 基础工具 ---------------------------------------------------------------

def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def quantized(freq: float, loop_seconds: float) -> float:
    """把频率吸到「整个循环里正好整数个周期」——持续音因此天生无缝。"""
    cycles = max(1.0, round(freq * loop_seconds))
    return cycles / loop_seconds


def pan_gains(pan: float) -> tuple[float, float]:
    angle = (pan + 1.0) * math.pi / 4.0
    return math.cos(angle), math.sin(angle)


def add_wrapped(buf: np.ndarray, sig: np.ndarray, start: int, pan: float, gain: float) -> None:
    """把一段声音绕回循环里加进去；超出末尾的尾巴从开头接上。"""
    n = buf.shape[1]
    idx = (np.arange(sig.size) + int(start)) % n
    gl, gr = pan_gains(pan)
    np.add.at(buf[0], idx, sig * gain * gl)
    np.add.at(buf[1], idx, sig * gain * gr)


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def periodic_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    spec = rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1)
    return np.fft.irfft(spec, n)


def band_noise(n: int, lo: float, hi: float, rng: np.random.Generator) -> np.ndarray:
    raw = periodic_noise(n, rng)
    sos = butter(2, [lo, hi], btype="bandpass", fs=SR, output="sos")
    y = sosfilt(sos, raw)
    return y / max(np.max(np.abs(y)), 1e-9)


def circular_eq(x: np.ndarray, lowpass: float, highpass: float = 32.0) -> np.ndarray:
    n = x.size
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    spec = np.fft.rfft(x)
    hp = 1.0 / (1.0 + (highpass / np.maximum(freqs, 1e-6)) ** 4)
    lp = 1.0 / (1.0 + (freqs / lowpass) ** 4)
    return np.fft.irfft(spec * hp * lp, n)


# --- 乐器 -------------------------------------------------------------------

def pluck(freq: float, seconds: float, brightness: float = 0.5) -> np.ndarray:
    """拨弦：几次谐波各自衰减 + 一点点起手噪声。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    # 起手有极小的下滑音，听上去像手指压出来的，不是纯合成器
    glide = 1.0 + 0.006 * np.exp(-t / 0.035)
    phase = 2.0 * math.pi * freq * np.cumsum(glide) / SR
    sig = np.zeros(n)
    partials = [(1, 1.0, 1.0), (2, 0.42, 0.68), (3, 0.20 * brightness, 0.48),
                (4, 0.09 * brightness, 0.34), (5, 0.04 * brightness, 0.24)]
    for mult, amp, decay in partials:
        sig += amp * np.sin(phase * mult) * np.exp(-t / (decay * 1.5))
    sig *= np.minimum(t / 0.005, 1.0)
    # 拨片/指甲的沙沙声，只留 30ms
    click = band_noise(n, 900.0, 3200.0, RNG) * np.exp(-t / 0.018) * 0.10
    return (sig * 0.55 + click)


def bell(freq: float, seconds: float) -> np.ndarray:
    n = int(seconds * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for mult, amp, decay in [(1.0, 1.0, 1.0), (2.76, 0.38, 0.55), (5.40, 0.18, 0.32)]:
        sig += amp * np.sin(2.0 * math.pi * freq * mult * t) * np.exp(-t / (decay * 1.8))
    sig *= np.minimum(t / 0.004, 1.0)
    return sig * 0.5


def flute(freq: float, seconds: float, vibrato_cycles: int, loop_seconds: float) -> np.ndarray:
    """气声长音：慢起音、迟到的揉弦、一点吹气噪声。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vib_rate = max(1, round(vibrato_cycles / loop_seconds))
    vib = np.sin(2.0 * math.pi * vib_rate * t) * 0.0032 * smoothstep((t - 0.35) / 0.5)
    phase = 2.0 * math.pi * freq * (t + np.cumsum(vib) / SR)
    sig = np.sin(phase) + 0.22 * np.sin(2.0 * phase) + 0.06 * np.sin(3.0 * phase)
    attack = np.minimum(t / 0.22, 1.0)
    release = np.minimum((seconds - t) / 0.55, 1.0)
    env = np.minimum(attack, release)
    env = smoothstep(env)
    breath = band_noise(n, 1200.0, 4200.0, RNG) * 0.045
    return (sig + breath) * env * 0.5


def reed(freq: float, seconds: float, vibrato_cycles: int, loop_seconds: float) -> np.ndarray:
    """第三章的低音吹管/弦：奇次谐波为主，慢起慢收。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vib_rate = max(1, round(vibrato_cycles / loop_seconds))
    vib = np.sin(2.0 * math.pi * vib_rate * t) * 0.0040 * smoothstep((t - 0.45) / 0.6)
    phase = 2.0 * math.pi * freq * (t + np.cumsum(vib) / SR)
    sig = np.sin(phase) + 0.30 * np.sin(3.0 * phase) + 0.12 * np.sin(5.0 * phase)
    attack = np.minimum(t / 0.35, 1.0)
    release = np.minimum((seconds - t) / 0.8, 1.0)
    env = smoothstep(np.minimum(attack, release))
    return sig * env * 0.42


def low_drum(freq: float, seconds: float = 0.9, pitch_drop: float = 0.82) -> np.ndarray:
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = freq * (1.0 - (1.0 - pitch_drop) * smoothstep(t / 0.16))
    phase = 2.0 * math.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.26)
    click = band_noise(n, 180.0, 900.0, RNG) * np.exp(-t / 0.025) * 0.18
    return (body + click) * np.minimum(t / 0.003, 1.0) * 0.85


def frame_drum() -> np.ndarray:
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    body = band_noise(n, 140.0, 420.0, RNG) * np.exp(-t / 0.09)
    return body * np.minimum(t / 0.002, 1.0) * 0.8


def gong(freq: float, seconds: float = 6.0) -> np.ndarray:
    n = int(seconds * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for mult, amp, decay in [(1.0, 1.0, 2.8), (1.52, 0.35, 1.9), (2.41, 0.22, 1.2),
                             (3.13, 0.12, 0.8)]:
        sig += amp * np.sin(2.0 * math.pi * freq * mult * t + RNG.uniform(0, 6.28)) \
            * np.exp(-t / decay)
    return sig * np.minimum(t / 0.02, 1.0) * 0.5


# --- 和弦垫 ----------------------------------------------------------------

def chord_weights(n: int, bar_lengths: list[int], fade_fraction: float = 0.22) -> np.ndarray:
    """每个和弦在循环里的权重。相邻两段的升降沿互补，权重和恒为 1。"""
    total_bars = sum(bar_lengths)
    weights = np.zeros((len(bar_lengths), n))
    cursor = 0
    for i, bars in enumerate(bar_lengths):
        start = cursor / total_bars * n
        end = (cursor + bars) / total_bars * n
        cursor += bars
        start_i, end_i = int(round(start)), int(round(end))
        length = end_i - start_i
        u = (np.arange(length) + 0.5) / length
        fade = fade_fraction
        w = np.ones(length)
        w[u < fade] = 0.5 - 0.5 * np.cos(math.pi * u[u < fade] / fade)
        w[u > 1.0 - fade] = 0.5 - 0.5 * np.cos(math.pi * (1.0 - u[u > 1.0 - fade]) / fade)
        weights[i, (np.arange(start_i, end_i) % n)] = w
    weights /= np.maximum(weights.sum(axis=0, keepdims=True), 1e-6)
    return weights


def render_pad(chords: list[list[float]], weights: np.ndarray, loop_seconds: float,
               level: float, phase_seed: int) -> np.ndarray:
    n = weights.shape[1]
    t = np.arange(n) / SR
    rng = np.random.default_rng(phase_seed)
    out = np.zeros((2, n), dtype=np.float64)
    for ci, notes in enumerate(chords):
        w = weights[ci]
        for note in notes:
            for ch, detune in ((0, -0.10), (1, 0.10)):
                f = quantized(midi_hz(note) * 2.0 ** (detune / 1200.0), loop_seconds)
                base_phase = rng.uniform(0, 2.0 * math.pi)
                sig = np.sin(2.0 * math.pi * f * t + base_phase)
                sig += 0.30 * np.sin(2.0 * math.pi * f * 2.0 * t + base_phase * 0.7)
                sig += 0.12 * np.sin(2.0 * math.pi * f * 3.0 * t + base_phase * 1.3)
                # 很慢的呼吸，周期数取整，循环接得上
                breath = 0.80 + 0.20 * np.sin(2.0 * math.pi * (3 + ci) / loop_seconds * t
                                               + base_phase)
                out[ch] += sig * w * breath * (level / max(len(notes), 1))
    return out


# --- 混响 -------------------------------------------------------------------

def make_ir(seconds: float = 2.6, decay: float = 0.75) -> np.ndarray:
    m = int(seconds * SR)
    t = np.arange(m) / SR
    ir = RNG.standard_normal(m) * np.exp(-t / decay)
    ir = np.concatenate(([1.0], ir[1:]))  # 直达声
    for delay, gain in ((0.017, 0.35), (0.029, 0.24), (0.043, 0.16), (0.061, 0.10)):
        ir[int(delay * SR)] += gain
    return ir / math.sqrt(np.sum(ir ** 2))


def circular_reverb(x: np.ndarray, ir: np.ndarray, wet: float) -> np.ndarray:
    n = x.size
    h = np.fft.rfft(ir, n)
    dry = np.fft.rfft(x)
    wet_sig = np.fft.irfft(dry * h, n)
    return (1.0 - wet) * x + wet * wet_sig


# --- 单曲合成 ---------------------------------------------------------------

def render_track(spec: dict) -> np.ndarray:
    bpm = spec["bpm"]
    bars = spec["bars"]
    beats_per_bar = 4
    beat = 60.0 / bpm
    loop_seconds = bars * beats_per_bar * beat
    n = int(round(loop_seconds * SR))
    loop_seconds = n / SR
    bar_seconds = beats_per_bar * beat
    buf = np.zeros((2, n), dtype=np.float64)

    def at(bar: float, beat_in_bar: float) -> int:
        return int(round(((bar - 1) * beats_per_bar + (beat_in_bar - 1)) * beat * SR))

    # 和弦垫
    weights = chord_weights(n, spec["chord_bars"])
    buf += render_pad(spec["chords"], weights, loop_seconds, spec["pad_level"], spec["seed"])

    # 全局低音开放五度（很轻，避免 55Hz 那种拍频）
    t = np.arange(n) / SR
    for note in spec["drone"]:
        f = quantized(midi_hz(note), loop_seconds)
        hum = np.sin(2.0 * math.pi * f * t + 0.4) + 0.25 * np.sin(2.0 * math.pi * f * 2 * t)
        buf += hum[None, :] * spec["drone_level"] / max(len(spec["drone"]), 1)

    # 拨弦 / 钟 / 吹管
    for bar, beat_in_bar, note, length, gain, pan in spec.get("plucks", []):
        sig = pluck(midi_hz(note), max(length * beat * 2.2, 1.8), brightness=0.55)
        add_wrapped(buf, sig, at(bar, beat_in_bar), pan, gain)
    for bar, beat_in_bar, note, gain, pan in spec.get("bells", []):
        add_wrapped(buf, bell(midi_hz(note), 4.5), at(bar, beat_in_bar), pan, gain)
    for bar, beat_in_bar, note, length, gain, pan in spec.get("flute", []):
        sig = flute(midi_hz(note), length * beat, vibrato_cycles=5, loop_seconds=loop_seconds)
        add_wrapped(buf, sig, at(bar, beat_in_bar), pan, gain)
    for bar, beat_in_bar, note, length, gain, pan in spec.get("reed", []):
        sig = reed(midi_hz(note), length * beat, vibrato_cycles=4, loop_seconds=loop_seconds)
        add_wrapped(buf, sig, at(bar, beat_in_bar), pan, gain)

    # 鼓
    for bar, beat_in_bar, gain in spec.get("drums", []):
        add_wrapped(buf, low_drum(spec["drum_hz"]), at(bar, beat_in_bar), 0.0, gain)
    for bar, beat_in_bar, gain in spec.get("frame_drums", []):
        add_wrapped(buf, frame_drum(), at(bar, beat_in_bar), -0.25, gain)
    for bar, beat_in_bar, note, gain in spec.get("gongs", []):
        add_wrapped(buf, gong(midi_hz(note)), at(bar, beat_in_bar), 0.15, gain)

    # 风：两路独立的周期噪声，用整数周期的慢 LFO 呼吸
    for ch, seed in ((0, spec["seed"] + 11), (1, spec["seed"] + 23)):
        rng = np.random.default_rng(seed)
        wind = band_noise(n, 180.0, 2400.0, rng)
        lfo = (0.62 + 0.24 * np.sin(2.0 * math.pi * 2 / loop_seconds * t + seed % 7)
               + 0.14 * np.sin(2.0 * math.pi * 5 / loop_seconds * t + seed % 11))
        buf[ch] += wind * lfo * spec["wind_level"]
    # 一点高频空气感（只占很小比例，不刺耳）
    for ch, seed in ((0, spec["seed"] + 31), (1, spec["seed"] + 37)):
        rng = np.random.default_rng(seed)
        air = band_noise(n, 3000.0, 6500.0, rng)
        buf[ch] += air * 0.010

    # 混响（循环卷积，尾巴绕回开头）
    ir = make_ir()
    for ch in range(2):
        buf[ch] = circular_reverb(buf[ch], ir, spec["wet"])

    # 总 EQ：切掉 32Hz 以下和高频毛刺，再做一点点软饱和
    for ch in range(2):
        buf[ch] = circular_eq(buf[ch], spec["lowpass"])
    buf = np.tanh(buf * 1.08) / math.tanh(1.08)

    # 统一响度：先按 RMS 定，再给峰值留 3dB
    rms = math.sqrt(float(np.mean(buf ** 2)))
    buf *= 10 ** (-20.0 / 20.0) / max(rms, 1e-9)
    peak = float(np.max(np.abs(buf)))
    ceiling = 10 ** (-3.0 / 20.0)
    if peak > ceiling:
        buf *= ceiling / peak
    return buf.T.astype(np.float32)


# --- 三章 -------------------------------------------------------------------

TRACKS = {
    "ch1": {
        "seed": 101, "bpm": 60, "bars": 16, "chord_bars": [4, 4, 4, 4],
        # D 小调五声：Dm - Bb - F - C
        "chords": [[50, 57, 62, 65], [58, 65, 70, 74], [53, 60, 65, 69], [60, 67, 72, 76]],
        "drone": [38, 45], "drone_level": 0.018,
        "pad_level": 0.105, "wind_level": 0.035, "lowpass": 7200, "wet": 0.34,
        "plucks": [
            (2, 1, 62, 1.0, 0.150, -0.20), (2, 2.5, 65, 1.0, 0.120, 0.15),
            (2, 4, 69, 1.0, 0.110, 0.35),
            (3, 1, 67, 1.5, 0.135, -0.10), (3, 3, 65, 1.0, 0.110, 0.30),
            (3, 4, 62, 1.0, 0.125, -0.35),
            (6, 1, 57, 0.5, 0.120, 0.25), (6, 1.8, 60, 0.5, 0.105, -0.15),
            (6, 2.8, 62, 1.0, 0.130, 0.10), (6, 4, 65, 1.0, 0.115, -0.25),
            (7, 1, 67, 1.2, 0.130, 0.30), (7, 2.8, 69, 0.8, 0.105, -0.10),
            (7, 4, 65, 1.2, 0.120, 0.20),
            (10, 1, 62, 0.8, 0.130, -0.30), (10, 2, 65, 0.8, 0.115, 0.10),
            (10, 3, 67, 0.8, 0.115, 0.30), (10, 4, 69, 1.0, 0.120, -0.10),
            (11, 1, 72, 1.2, 0.115, 0.35), (11, 2.5, 69, 1.0, 0.105, -0.20),
            (11, 4, 67, 1.2, 0.110, 0.15),
            (14, 1, 65, 1.0, 0.120, -0.25), (14, 2.2, 62, 1.0, 0.110, 0.20),
            (14, 3.4, 60, 1.0, 0.100, 0.30), (14, 4, 62, 1.0, 0.105, -0.10),
            (15, 1, 57, 2.0, 0.115, 0.20), (15, 3.5, 62, 1.5, 0.105, -0.15),
        ],
        "bells": [(4, 4, 81, 0.050, 0.45), (12, 4, 74, 0.055, -0.35),
                  (16, 4, 69, 0.045, 0.20)],
    },
    "ch2": {
        "seed": 202, "bpm": 52, "bars": 16, "chord_bars": [4, 4, 4, 4],
        # G 自然小调：Gm - Eb - Cm - Dm
        "chords": [[43, 50, 55, 58], [51, 58, 63, 67], [48, 55, 60, 63], [50, 57, 62, 65]],
        "drone": [31, 38], "drone_level": 0.016,
        "pad_level": 0.115, "wind_level": 0.045, "lowpass": 6200, "wet": 0.38,
        "plucks": [
            (1, 1, 43, 2.0, 0.110, -0.10), (5, 1, 51, 2.0, 0.095, 0.20),
            (9, 1, 48, 2.0, 0.095, -0.20), (13, 1, 50, 2.0, 0.100, 0.10),
        ],
        "flute": [
            (3, 1, 62, 2.0, 0.120, -0.20), (3, 3, 65, 2.0, 0.105, 0.20),
            (4, 1, 70, 2.0, 0.110, 0.10), (4, 3, 67, 2.0, 0.100, -0.25),
            (7, 1, 65, 1.5, 0.110, 0.15), (7, 2.5, 63, 1.5, 0.100, -0.10),
            (7, 4, 62, 1.0, 0.095, 0.25),
            (8, 1, 60, 1.5, 0.105, -0.20), (8, 2.5, 62, 2.5, 0.110, 0.10),
            (11, 1, 67, 1.5, 0.110, 0.20), (11, 2.5, 70, 0.5, 0.095, -0.10),
            (11, 3, 72, 2.0, 0.105, 0.30),
            (12, 1, 70, 2.0, 0.100, -0.15), (12, 3, 67, 2.0, 0.095, 0.15),
            (15, 1, 65, 1.0, 0.100, 0.10), (15, 2, 62, 1.0, 0.095, -0.20),
            (15, 3, 60, 1.0, 0.090, 0.25), (15, 4, 62, 1.0, 0.100, -0.10),
        ],
        "bells": [(6, 4, 75, 0.040, 0.35), (14, 4, 79, 0.035, -0.30)],
        "drums": [(b, 1, 0.105) for b in range(1, 17)]
                  + [(b, 3, 0.065) for b in range(9, 17)],
        "drum_hz": 72.0,
    },
    "ch3": {
        "seed": 303, "bpm": 48, "bars": 16, "chord_bars": [4, 4, 4, 4],
        # A 弗里几亚/和声小调：Am - Bb - Dm - E
        "chords": [[45, 52, 57, 60], [46, 53, 58, 62], [50, 57, 62, 65], [40, 47, 52, 56]],
        "drone": [33, 40], "drone_level": 0.015,
        "pad_level": 0.120, "wind_level": 0.050, "lowpass": 5600, "wet": 0.40,
        "plucks": [
            (1, 1, 45, 2.5, 0.105, -0.15), (9, 1, 52, 2.5, 0.095, 0.15),
        ],
        "reed": [
            (3, 1, 64, 1.5, 0.090, -0.10), (3, 2.5, 65, 1.5, 0.085, 0.15),
            (3, 4, 64, 1.0, 0.080, -0.20),
            (6, 1, 62, 2.0, 0.090, 0.10), (6, 3, 60, 2.0, 0.085, -0.15),
            (7, 1, 59, 1.5, 0.080, 0.20), (7, 2.5, 60, 1.5, 0.085, -0.10),
            (7, 4, 59, 1.0, 0.080, 0.15),
            (10, 1, 57, 2.0, 0.090, -0.20), (10, 3, 60, 2.0, 0.085, 0.10),
            (11, 1, 62, 1.5, 0.085, 0.15), (11, 2.5, 64, 1.5, 0.090, -0.10),
            (11, 4, 65, 1.0, 0.085, 0.20),
            (14, 1, 64, 2.0, 0.090, -0.15), (14, 3, 62, 1.0, 0.080, 0.10),
            (14, 4, 59, 1.0, 0.080, -0.20),
            (15, 1, 57, 3.0, 0.090, 0.10),
        ],
        "bells": [(1, 1, 69, 0.045, 0.35), (5, 3, 72, 0.040, -0.25),
                  (9, 1, 76, 0.045, 0.30), (13, 1, 69, 0.040, -0.30)],
        "gongs": [(1, 1, 45, 0.070), (9, 1, 45, 0.055)],
        "drums": [(b, 1, 0.125) for b in range(1, 17)]
                  + [(b, 3, 0.075) for b in range(9, 17)],
        "frame_drums": [(b, 2.5, 0.045) for b in range(5, 17)],
        "drum_hz": 68.0,
    },
}


def render_ambience() -> np.ndarray:
    seconds = 40.0
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros((2, n), dtype=np.float64)
    for ch, seed in ((0, 901), (1, 907)):
        rng = np.random.default_rng(seed)
        wind = band_noise(n, 160.0, 2600.0, rng)
        lfo = (0.55 + 0.30 * np.sin(2.0 * math.pi * 3 / seconds * t + seed % 5)
               + 0.15 * np.sin(2.0 * math.pi * 7 / seconds * t + seed % 9))
        out[ch] = wind * lfo
    rms = math.sqrt(float(np.mean(out ** 2)))
    out *= 10 ** (-26.0 / 20.0) / max(rms, 1e-9)
    return out.T.astype(np.float32)


def write_ogg(path: str, data: np.ndarray) -> None:
    """按块写入。libsndfile 的 Vorbis 编码器一次吃几百万帧会爆栈。"""
    block = 4096
    with sf.SoundFile(path, mode="w", samplerate=SR, channels=data.shape[1],
                      format="OGG", subtype="VORBIS") as f:
        for start in range(0, data.shape[0], block):
            f.write(data[start:start + block])


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, spec in TRACKS.items():
        data = render_track(spec)
        path = os.path.join(OUT_DIR, name + ".ogg")
        write_ogg(path, data)
        duration = data.shape[0] / SR
        print(f"{name}: {duration:.1f}s  peak={np.max(np.abs(data)):.3f}  "
              f"rms={np.sqrt(np.mean(data ** 2)):.3f}  {os.path.getsize(path) / 1024:.0f} KB")
    amb = render_ambience()
    path = os.path.join(OUT_DIR, "ambience.ogg")
    write_ogg(path, amb)
    print(f"ambience: 40.0s  {os.path.getsize(path) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
