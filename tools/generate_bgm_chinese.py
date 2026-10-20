"""三章中国古典器乐版 BGM（试听候选），不碰 assets/audio/bgm/ 里的正式文件。

和第 1 版最大的区别不是 EQ，而是编曲：
- 彻底没有和弦垫、持续低音、常驻风声——上一版「一直嗯/一直嗡」就是它们造成的；
- 只留三件主奏：古筝（分解/滑音/摇指/刮奏）、箫（长音旋律）、编钟（句读与转场）；
- 乐句之间真空出来，最长有整整一小节只剩余音，不做任何铺底；
- 第二、三章各加一点很轻的堂鼓，只打点，不留低频尾巴。

循环仍是整小节长度、所有音符尾巴绕回开头，接缝无缝。
输出到 _audition_bgm/chN_C.ogg，试听通过前不替换正式文件。

    python tools/generate_bgm_chinese.py
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
sys.path.insert(0, TOOLS_DIR)
from generate_bgm import (  # noqa: E402
    SR, add_wrapped, band_noise, midi_hz, pan_gains, smoothstep, write_ogg,
)

OUT_DIR = os.path.join(ROOT, "_audition_bgm")
TARGET_RMS_DB = -23.5
PEAK_CEILING_DB = -3.0


# --- 基础工具 ---------------------------------------------------------------

def local_rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def release_env(t: np.ndarray, seconds: float, tail: float = 0.35) -> np.ndarray:
    return smoothstep(np.clip((seconds - t) / tail, 0.0, 1.0))


def circular_eq(x: np.ndarray, highpass: float, lowpass: float) -> np.ndarray:
    n = x.size
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    hp = 1.0 / (1.0 + (highpass / np.maximum(freqs, 1e-6)) ** 4)
    lp = 1.0 / (1.0 + (freqs / lowpass) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * hp * lp, n)


def make_ir(rng: np.random.Generator, seconds: float = 3.0,
            decay: float = 0.80) -> np.ndarray:
    m = int(seconds * SR)
    t = np.arange(m) / SR
    ir = rng.standard_normal(m) * np.exp(-t / decay)
    ir[0] += 1.0
    for delay, gain in ((0.019, 0.30), (0.031, 0.20), (0.047, 0.13), (0.067, 0.08)):
        ir[int(delay * SR)] += gain
    return ir / math.sqrt(float(np.sum(ir ** 2)))


def circular_reverb(x: np.ndarray, ir: np.ndarray, wet: float) -> np.ndarray:
    n = x.size
    wet_sig = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir, n), n)
    return (1.0 - wet) * x + wet * wet_sig


# --- 乐器 -------------------------------------------------------------------

def guzheng(freq: float, seconds: float, rng: np.random.Generator,
            brightness: float = 0.6, bend_cents: float = 0.0,
            bend_start: float = 0.16, bend_time: float = 0.45) -> np.ndarray:
    """古筝：钢丝弦的明亮起手 + 木腔的温润衰减，带按音滑音。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    # 起手有极轻微的上扬，像指甲压弦
    cents = 7.0 * np.exp(-t / 0.055)
    if bend_cents:
        cents += bend_cents * smoothstep((t - bend_start) / bend_time)
    ratio = 2.0 ** (cents / 1200.0)
    phase = 2.0 * np.pi * np.cumsum(freq * ratio) / SR

    # 谐波略带非谐性，避免合成器那种「纯音叠加」的塑料感
    partials = [
        (1.0, 1.00, 2.60),
        (2.0, 0.52, 1.80),
        (3.0, 0.30 * brightness, 1.25),
        (4.0, 0.17 * brightness, 0.95),
        (5.0, 0.10 * brightness, 0.70),
        (6.0, 0.06, 0.52),
        (7.0, 0.035, 0.40),
    ]
    sig = np.zeros(n)
    for mult, amp, decay in partials:
        inharm = mult * (1.0 + 0.00035 * mult * mult)
        sig += amp * np.sin(phase * inharm + rng.uniform(0.0, 2.0 * math.pi)) \
            * np.exp(-t / decay)
    # 指甲触弦的短促沙沙声
    click = band_noise(n, 700.0, 4500.0, rng) * np.exp(-t / 0.012) * 0.13
    env = np.minimum(t / 0.004, 1.0) * release_env(t, seconds, 0.30)
    return (sig * 0.50 + click) * env


def xiao(freq: float, seconds: float, rng: np.random.Generator,
         scoop_cents: float = 30.0, vibrato_rate: float = 5.2,
         vibrato_depth: float = 0.0035) -> np.ndarray:
    """箫：低音区气息长音，起音带一点下探再滑入，揉弦迟到。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vibrato = vibrato_depth * np.sin(2.0 * math.pi * vibrato_rate * t) \
        * smoothstep((t - 0.25) / 0.55)
    scoop = (2.0 ** (scoop_cents / 1200.0) - 1.0) \
        * (1.0 - smoothstep(t / 0.13))
    pitch = 1.0 + vibrato + scoop
    phase = 2.0 * np.pi * np.cumsum(freq * pitch) / SR

    tone = np.sin(phase) + 0.21 * np.sin(2.0 * phase) + 0.07 * np.sin(3.0 * phase)
    breath_env = smoothstep(np.clip(t / 0.20, 0.0, 1.0)) \
        * release_env(t, seconds, 0.55)
    breath = band_noise(n, 900.0, 4200.0, rng) * breath_env * 0.075
    chiff = band_noise(n, 800.0, 3000.0, rng) * np.exp(-t / 0.05) * 0.06
    env = smoothstep(np.clip(t / 0.19, 0.0, 1.0)) * release_env(t, seconds, 0.50)
    return (tone * env * 0.40 + breath + chiff * env)


def bianzhong(freq: float, seconds: float, rng: np.random.Generator) -> np.ndarray:
    """编钟：青铜钟的非谐分音 + 木槌击打的瞬态，余音长。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for ratio, amp, decay in [
        (1.00, 1.00, 3.60),
        (2.00, 0.52, 2.45),
        (2.76, 0.30, 1.80),
        (4.07, 0.15, 1.15),
        (5.43, 0.07, 0.85),
    ]:
        sig += amp * np.sin(2.0 * math.pi * freq * ratio * t
                            + rng.uniform(0.0, 2.0 * math.pi)) * np.exp(-t / decay)
    strike = band_noise(n, 250.0, 5000.0, rng) * np.exp(-t / 0.022) * 0.16
    env = np.minimum(t / 0.002, 1.0) * release_env(t, seconds, 0.45)
    return (sig * 0.32 + strike) * env


def tanggu(freq: float, rng: np.random.Generator, seconds: float = 0.85) -> np.ndarray:
    """堂鼓：中低音鼓腔，刻意不往 60Hz 以下沉，避免留下低频嗡。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = freq * (1.0 - 0.18 * smoothstep(t / 0.10))
    phase = 2.0 * math.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.22)
    body += 0.28 * np.sin(2.0 * phase) * np.exp(-t / 0.12)
    click = band_noise(n, 160.0, 950.0, rng) * np.exp(-t / 0.018) * 0.10
    env = np.minimum(t / 0.003, 1.0) * release_env(t, seconds, 0.12)
    return (body * 0.80 + click) * env


def muyu(rng: np.random.Generator, seconds: float = 0.30) -> np.ndarray:
    """木鱼：只在高处「笃」一下，不占低频。"""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    sig = np.sin(2.0 * math.pi * 920.0 * t) * np.exp(-t / 0.045)
    sig += 0.45 * np.sin(2.0 * math.pi * 1510.0 * t) * np.exp(-t / 0.028)
    click = band_noise(n, 1200.0, 5000.0, rng) * np.exp(-t / 0.008) * 0.25
    env = np.minimum(t / 0.002, 1.0) * release_env(t, seconds, 0.05)
    return (sig * 0.5 + click) * env


# --- 演奏织体 ---------------------------------------------------------------

def render_tremolo(freq: float, seconds: float, rng: np.random.Generator,
                   rate: float = 10.5) -> np.ndarray:
    """摇指：快速重复的短拨，而不是把一个长音做振幅调制。"""
    n = int(seconds * SR)
    out = np.zeros(n)
    step = max(1, int(SR / rate))
    for k in range(0, n, step):
        amp = 0.85 + 0.15 * ((k // step) % 2)
        sig = guzheng(freq, 0.85, rng, brightness=0.40)
        end = min(n, k + sig.size)
        out[k:end] += sig[:end - k] * amp
    t = np.arange(n) / SR
    out *= smoothstep(np.clip(t / 0.15, 0.0, 1.0)) \
        * smoothstep(np.clip((seconds - t) / 0.30, 0.0, 1.0))
    return out * 0.55


def pentatonic_desc(lo: int, hi: int, pcs: set[int]) -> list[int]:
    return [m for m in range(hi, lo - 1, -1) if m % 12 in pcs]


def add_gliss(buf: np.ndarray, notes: list[int], start: int, gain: float,
              pan: float, rng: np.random.Generator) -> None:
    """刮奏：一串快速拨弦，从高到低，力度渐收。"""
    count = max(1, len(notes))
    for i, note in enumerate(notes):
        sig = guzheng(midi_hz(note), 1.5, rng, brightness=0.55)
        dyn = 1.0 - 0.35 * (i / max(1, count - 1))
        add_wrapped(buf, sig, start + int(i * 0.115 * SR), pan, gain * dyn)


# --- 单曲合成 ---------------------------------------------------------------

def render(spec: dict) -> np.ndarray:
    bpm = spec["bpm"]
    beats_per_bar = 4
    beat = 60.0 / bpm
    loop_seconds = spec["bars"] * beats_per_bar * beat
    n = int(round(loop_seconds * SR))
    loop_seconds = n / SR
    rng = local_rng(spec["seed"])
    buf = np.zeros((2, n), dtype=np.float64)

    def at(bar: float, beat_in_bar: float = 1.0) -> int:
        return int(round(((bar - 1) * beats_per_bar + (beat_in_bar - 1)) * beat * SR))

    for bar, beat_in_bar, note, gain, pan, bend in spec.get("guzheng", []):
        sig = guzheng(midi_hz(note), 4.0, rng, bend_cents=bend)
        add_wrapped(buf, sig, at(bar, beat_in_bar), pan, gain)

    for bar, beat_in_bar, note, length, gain, pan, scoop in spec.get("xiao", []):
        sig = xiao(midi_hz(note), length * beat, rng, scoop_cents=scoop)
        add_wrapped(buf, sig, at(bar, beat_in_bar), pan, gain)

    for bar, beat_in_bar, note, gain, pan in spec.get("bells", []):
        add_wrapped(buf, bianzhong(midi_hz(note), 6.5, rng), at(bar, beat_in_bar), pan, gain)

    for bar, beat_in_bar, note, length, gain, pan in spec.get("tremolo", []):
        sig = render_tremolo(midi_hz(note), length * beat, rng)
        add_wrapped(buf, sig, at(bar, beat_in_bar), pan, gain)

    for bar, beat_in_bar, gain in spec.get("tanggu", []):
        add_wrapped(buf, tanggu(spec["drum_hz"], rng), at(bar, beat_in_bar), 0.0, gain)

    for bar, beat_in_bar, gain in spec.get("muyu", []):
        add_wrapped(buf, muyu(rng), at(bar, beat_in_bar), -0.2, gain)

    for bar, beat_in_bar, lo, hi, gain, pan in spec.get("gliss", []):
        notes = pentatonic_desc(lo, hi, spec["scale_pcs"])
        add_gliss(buf, notes, at(bar, beat_in_bar), gain, pan, rng)

    ir = make_ir(rng)
    for ch in range(2):
        buf[ch] = circular_reverb(buf[ch], ir, spec["wet"])
    for ch in range(2):
        buf[ch] = circular_eq(buf[ch], 38.0, spec["lowpass"])

    rms = math.sqrt(float(np.mean(buf ** 2)))
    buf *= 10 ** (TARGET_RMS_DB / 20.0) / max(rms, 1e-9)
    peak = float(np.max(np.abs(buf)))
    ceiling = 10 ** (PEAK_CEILING_DB / 20.0)
    if peak > ceiling:
        buf *= ceiling / peak
    return buf.T.astype(np.float32)


# --- 三章 -------------------------------------------------------------------
# 记法：所有音符位置都是 (小节, 小节内第几拍)，1 起算，可写小数拍。
# 留白是刻意的：没有音符的小节只剩余音，绝不再铺任何持续层。

TRACKS = {
    # 第一章：D 羽调（D 自然小调 / 五声骨架），古筝为主，箫在句末应答。
    "ch1": {
        "seed": 6101, "bpm": 60, "bars": 16, "wet": 0.22, "lowpass": 9000,
        "scale_pcs": {2, 5, 7, 9, 0},  # D F G A C
        "bells": [
            (1, 1, 50, 0.075, 0.30), (5, 1, 57, 0.050, 0.30),
            (9, 1, 50, 0.060, 0.30), (12, 1, 57, 0.045, 0.30),
            (15, 1, 50, 0.045, 0.30),
        ],
        "guzheng": [
            # 第 1~2 小节：起手低音与分解和弦
            (1, 1, 38, 0.100, 0.00, 0), (1, 1.5, 45, 0.070, -0.10, 0),
            (1, 2, 50, 0.055, 0.10, 0),
            (1, 3, 62, 0.070, 0.20, 0), (1, 4, 65, 0.065, 0.30, 0),
            (2, 1, 69, 0.075, 0.25, 0), (2, 2, 72, 0.060, 0.10, 0),
            (2, 3, 67, 0.060, -0.10, 0), (2, 4, 65, 0.055, -0.25, 0),
            # 第 3~4 小节：箫进来，古筝让位
            (3, 1, 50, 0.045, 0.00, 0), (3, 3, 57, 0.045, 0.10, 0),
            (4, 1, 43, 0.050, -0.10, 0), (4, 3, 50, 0.045, 0.00, 0),
            # 第 5~6 小节：古筝单独一句，句内渐密，句尾收住
            (5, 1, 74, 0.065, 0.25, 0), (5, 1.75, 72, 0.055, 0.10, 0),
            (5, 2.5, 69, 0.060, -0.10, 0), (5, 3.5, 67, 0.055, -0.25, 0),
            (5, 1, 38, 0.060, 0.00, 0),
            (6, 1, 65, 0.060, 0.20, 0), (6, 2, 62, 0.055, 0.05, 0),
            (6, 3, 60, 0.050, -0.10, 0), (6, 4, 62, 0.050, -0.20, 0),
            (6, 1, 43, 0.050, 0.00, 0),
            # 第 7~8 小节：箫接回去，古筝只点两下
            (7, 1, 53, 0.050, 0.00, 0), (7, 3, 60, 0.050, 0.10, 40),
            (8, 1, 57, 0.050, 0.00, 0), (8, 3.5, 65, 0.055, 0.20, 0),
            # 第 9~10 小节：第二次起势
            (9, 1, 38, 0.070, 0.00, 0),
            (9, 1, 62, 0.050, 0.25, 0), (9, 2, 65, 0.050, 0.10, 0),
            (9, 3, 69, 0.055, -0.05, 0), (9, 4, 74, 0.060, -0.20, 0),
            (10, 2, 77, 0.050, 0.25, 0), (10, 3.5, 74, 0.050, 0.05, 0),
            (10, 1, 45, 0.050, 0.00, 0),
            # 第 11 小节：摇指撑一下，马上退回
            (11, 3, 57, 0.045, 0.00, 0), (11, 3, 65, 0.040, 0.15, 0),
            # 第 12 小节
            (12, 1, 53, 0.050, 0.00, -40), (12, 3, 60, 0.050, 0.10, 0),
            # 第 13~14 小节：收束
            (13, 1, 57, 0.045, 0.05, 0), (13, 3, 50, 0.045, -0.10, 0),
            (14, 1, 38, 0.050, 0.00, 0), (14, 2.5, 45, 0.040, 0.00, 0),
            # 第 15 小节：最后一口
            (15, 1, 38, 0.050, 0.00, 0),
        ],
        "xiao": [
            (3, 1, 62, 2.0, 0.075, -0.20, 35), (3, 3, 65, 2.0, 0.070, -0.10, 25),
            (4, 1, 69, 2.0, 0.075, -0.15, 30), (4, 3, 67, 2.0, 0.070, -0.25, 20),
            (7, 1, 65, 2.0, 0.075, -0.15, 35), (7, 3, 67, 2.0, 0.070, -0.05, 25),
            (8, 1, 69, 3.0, 0.080, -0.20, 30),
            (9, 1, 69, 2.0, 0.080, -0.15, 25), (9, 3, 72, 2.0, 0.075, -0.05, 20),
            (10, 1, 74, 2.0, 0.085, -0.20, 30), (10, 3, 72, 2.0, 0.075, -0.10, 20),
            (11, 3, 65, 2.0, 0.070, -0.20, 30),
            (12, 1, 67, 2.0, 0.075, -0.15, 25), (12, 3, 65, 2.0, 0.070, -0.25, 20),
            (13, 1, 65, 2.0, 0.070, -0.15, 30), (13, 3, 62, 2.0, 0.065, -0.20, 25),
            (14, 1, 62, 4.0, 0.070, -0.20, 35),
        ],
        "tremolo": [
            (11, 1, 62, 2.0, 0.045, 0.10),
        ],
        "gliss": [],
        "tanggu": [],
        "muyu": [],
    },
    # 第二章：G 小调，箫主奏、古筝点缀，堂鼓只做很轻的心跳。
    "ch2": {
        "seed": 6202, "bpm": 52, "bars": 16, "wet": 0.24, "lowpass": 8200,
        "scale_pcs": {7, 9, 10, 2, 5},  # G A Bb D F
        "drum_hz": 88.0,
        "bells": [
            (1, 1, 43, 0.070, 0.30), (3, 1, 50, 0.040, 0.30),
            (8, 1, 50, 0.040, 0.30), (9, 1, 43, 0.060, 0.30),
            (14, 1, 50, 0.040, 0.30), (16, 1, 43, 0.035, 0.30),
        ],
        "guzheng": [
            (1, 1, 43, 0.080, 0.00, 0), (1, 2, 50, 0.055, 0.10, 0),
            (1, 3, 67, 0.060, 0.20, 0), (1, 4, 70, 0.055, 0.10, 0),
            (2, 1, 55, 0.045, 0.00, 0), (2, 3, 62, 0.050, 0.10, 0),
            (3, 1, 58, 0.045, 0.00, 0), (3, 3, 55, 0.045, 0.10, 0),
            (4, 1, 53, 0.050, 0.00, 0), (4, 3, 60, 0.050, 0.10, 0),
            # 第 5~6 小节：箫休息，古筝一句
            (5, 1, 62, 0.060, 0.20, 0), (5, 1.75, 67, 0.055, 0.10, 0),
            (5, 2.5, 70, 0.060, -0.05, 0), (5, 3.5, 74, 0.055, -0.15, 0),
            (5, 1, 43, 0.050, 0.00, 0),
            (6, 1, 72, 0.055, 0.20, 0), (6, 2, 70, 0.050, 0.05, 0),
            (6, 3, 67, 0.055, -0.10, 0), (6, 4, 65, 0.050, -0.20, 0),
            (6, 1, 50, 0.045, 0.00, 0),
            # 第 7~8 小节：箫回来
            (7, 1, 55, 0.045, 0.00, 0), (7, 3, 62, 0.045, 0.10, 0),
            (8, 1, 58, 0.045, 0.00, 0), (8, 3, 55, 0.045, 0.10, 0),
            # 第 9~10 小节：第二次起势
            (9, 1, 43, 0.080, 0.00, 0),
            (9, 1, 67, 0.045, 0.20, 0), (9, 2, 70, 0.050, 0.10, 0),
            (9, 3, 74, 0.055, -0.05, 0), (9, 4, 77, 0.045, -0.15, 0),
            (10, 1, 62, 0.045, 0.20, 0), (10, 3, 67, 0.050, 0.05, 0),
            # 第 11 小节：古筝行走，箫停
            (11, 1, 65, 0.055, 0.20, 0), (11, 1.75, 70, 0.050, 0.10, 0),
            (11, 2.5, 74, 0.055, -0.05, 0), (11, 3.5, 77, 0.045, -0.20, 0),
            (11, 1, 48, 0.045, 0.00, 0),
            # 第 12~13 小节
            (12, 1, 60, 0.045, 0.00, 0), (12, 3, 67, 0.045, 0.10, 0),
            (13, 1, 58, 0.045, 0.00, 0), (13, 3, 55, 0.045, 0.10, 0),
            # 第 14~16 小节：淡出
            (14, 1, 53, 0.045, 0.00, -35),
            (15, 1, 43, 0.050, 0.00, 0),
        ],
        "xiao": [
            (2, 1, 74, 2.0, 0.075, -0.15, 30), (2, 3, 72, 2.0, 0.070, -0.05, 20),
            (3, 1, 70, 3.0, 0.075, -0.20, 35), (3, 4, 67, 1.0, 0.060, -0.10, 20),
            (4, 1, 65, 2.0, 0.070, -0.15, 30), (4, 3, 67, 2.0, 0.070, -0.25, 20),
            (7, 1, 70, 2.0, 0.070, -0.15, 35), (7, 3, 74, 2.0, 0.070, -0.05, 25),
            (8, 1, 72, 2.0, 0.070, -0.20, 30), (8, 3, 70, 2.0, 0.070, -0.10, 20),
            (9, 1, 74, 3.0, 0.080, -0.15, 30), (9, 4, 72, 1.0, 0.065, -0.05, 20),
            (10, 1, 70, 2.0, 0.075, -0.20, 30), (10, 3, 67, 2.0, 0.070, -0.10, 20),
            (12, 1, 72, 2.0, 0.070, -0.15, 30), (12, 3, 74, 2.0, 0.070, -0.25, 20),
            (13, 1, 70, 2.0, 0.070, -0.15, 35), (13, 3, 67, 2.0, 0.065, -0.20, 20),
            (14, 1, 65, 3.0, 0.070, -0.20, 35), (14, 4, 62, 1.0, 0.055, -0.15, 20),
            (15, 1, 67, 2.0, 0.065, -0.15, 30), (15, 3, 62, 2.0, 0.060, -0.20, 20),
        ],
        "tremolo": [],
        "gliss": [],
        "tanggu": [
            (2, 1, 0.050), (4, 1, 0.050), (6, 1, 0.045), (8, 1, 0.050),
            (9, 1, 0.060), (10, 1, 0.050), (12, 1, 0.045), (15, 1, 0.040),
        ],
        "muyu": [],
    },
    # 第三章：A 小调 / 弗里几亚色彩，编钟与堂鼓压阵，箫声更窄。
    "ch3": {
        "seed": 6303, "bpm": 48, "bars": 16, "wet": 0.26, "lowpass": 7600,
        "scale_pcs": {9, 0, 2, 4, 7},  # A C D E G
        "drum_hz": 84.0,
        "bells": [
            (1, 1, 45, 0.085, 0.30), (5, 1, 45, 0.055, 0.30),
            (9, 1, 45, 0.070, 0.30), (14, 1, 45, 0.050, 0.30),
        ],
        "guzheng": [
            (1, 1, 45, 0.080, 0.00, 0), (1, 1.5, 52, 0.055, -0.10, 0),
            (1, 2.5, 57, 0.055, 0.10, 0), (1, 3.5, 64, 0.050, 0.20, 0),
            (2, 1, 45, 0.050, 0.00, 0),
            (3, 1, 58, 0.050, 0.00, 0), (3, 3, 57, 0.045, 0.10, -35),
            (4, 1, 52, 0.050, 0.00, 0), (4, 3, 45, 0.045, -0.10, 0),
            # 第 5~6 小节：低音与分解
            (5, 1, 69, 0.060, 0.20, 0), (5, 1.75, 72, 0.055, 0.10, 0),
            (5, 2.5, 76, 0.055, -0.05, 0), (5, 3.5, 72, 0.050, -0.15, 0),
            (5, 1, 45, 0.060, 0.00, 0),
            (6, 1, 70, 0.060, 0.20, 0), (6, 2, 69, 0.055, 0.05, 0),
            (6, 3, 65, 0.050, -0.10, 0), (6, 4, 64, 0.050, -0.20, 0),
            (6, 1, 50, 0.045, 0.00, 0),
            (7, 1, 58, 0.045, 0.00, 0), (7, 3, 57, 0.045, 0.10, 0),
            (8, 1, 48, 0.050, 0.00, 0), (8, 3, 43, 0.045, -0.10, 0),
            # 第 9~10 小节：高潮
            (9, 1, 45, 0.070, 0.00, 0),
            (9, 1, 69, 0.055, 0.20, 0), (9, 2, 72, 0.055, 0.10, 0),
            (9, 3, 76, 0.060, -0.05, 0), (9, 4, 81, 0.050, -0.20, 0),
            (10, 1, 64, 0.050, 0.20, 0), (10, 2, 69, 0.050, 0.10, 0),
            (10, 3, 72, 0.055, -0.05, 0), (10, 4, 76, 0.050, -0.15, 0),
            # 第 11 小节：摇指压住
            (11, 1, 45, 0.050, 0.00, 0),
            # 第 12 小节
            (12, 1, 58, 0.045, 0.00, 0), (12, 3, 55, 0.045, 0.10, 0),
            # 第 13 小节：刮奏之后只留箫
            (13, 1, 45, 0.050, 0.00, 0),
            # 第 14~15 小节：收
            (14, 1, 45, 0.045, 0.00, 0), (14, 2.5, 52, 0.040, 0.00, 0),
            (15, 1, 45, 0.050, 0.00, 0), (15, 2.5, 52, 0.040, 0.00, 0),
        ],
        "xiao": [
            (2, 1, 69, 2.0, 0.070, -0.15, 30), (2, 3, 72, 2.0, 0.070, -0.05, 20),
            (3, 1, 70, 2.0, 0.075, -0.20, 35), (3, 3, 69, 2.0, 0.070, -0.10, 20),
            (4, 1, 64, 2.0, 0.070, -0.15, 30), (4, 3, 67, 2.0, 0.065, -0.25, 20),
            (7, 1, 70, 2.0, 0.075, -0.15, 35), (7, 3, 69, 2.0, 0.070, -0.05, 25),
            (8, 1, 72, 2.0, 0.075, -0.20, 30), (8, 3, 67, 2.0, 0.070, -0.10, 20),
            (9, 1, 76, 2.0, 0.080, -0.15, 30), (9, 3, 74, 2.0, 0.075, -0.05, 20),
            (10, 1, 72, 2.0, 0.075, -0.20, 30), (10, 3, 70, 2.0, 0.070, -0.10, 20),
            (12, 1, 70, 2.0, 0.070, -0.15, 35), (12, 3, 67, 2.0, 0.065, -0.25, 20),
            (13, 3, 72, 2.0, 0.070, -0.20, 30),
            (14, 1, 69, 4.0, 0.070, -0.20, 35),
        ],
        "tremolo": [
            (11, 1, 69, 2.0, 0.045, 0.10),
        ],
        "gliss": [
            (13, 1, 57, 81, 0.050, 0.15),  # A3 -> A5 下行刮奏
        ],
        "tanggu": [
            (4, 1, 0.050), (4, 3, 0.030),
            (5, 1, 0.055), (6, 1, 0.050), (6, 3, 0.030),
            (8, 1, 0.055), (8, 3, 0.030),
            (9, 1, 0.060), (9, 3, 0.035),
            (10, 1, 0.055), (11, 1, 0.050), (11, 3, 0.030),
            (12, 1, 0.050),
        ],
        "muyu": [],
    },
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, spec in TRACKS.items():
        data = render(spec)
        path = os.path.join(OUT_DIR, f"{name}_C.ogg")
        write_ogg(path, data)
        mono = data.mean(axis=1)
        rms = math.sqrt(float(np.mean(mono ** 2)))
        duration = data.shape[0] / SR
        print(f"{name}_C: {duration:.1f}s  peak={np.max(np.abs(data)):.3f}  "
              f"rms={20 * math.log10(rms):.1f}dBFS  {os.path.getsize(path) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
