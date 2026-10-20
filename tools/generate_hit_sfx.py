"""生成三段打击音效，替代原来那一声单薄的噪声爆点。

原来的 hit.wav 是一段 0.12s 的白噪声线性衰减，没有低频、没有起手、没有尾音，
听上去像「噗」而不是「砸中」。这里按打击乐的常规分层来叠：

  1. 低频 body：60~150Hz 的快速下滑正弦，负责「沉」；
  2. 中频 crack：600~3500Hz 的带通噪声，负责「脆」；
  3. 起手 click：高通噪声 3ms 衰减，负责「利落」；
  4. 一点点金属余响和短混响，负责「有空间」。

三段只在音高、亮度、长短上错开，不换配方，切换时才不会像三种武器。

    python tools/generate_hit_sfx.py

依赖：numpy scipy soundfile
输出：assets/audio/sfx/hit_1.wav / hit_2.wav / hit_3.wav（不覆盖原 hit.wav）
"""
from __future__ import annotations

import math
import os

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "audio", "sfx")

# 三段分别偏「重 / 脆 / 均衡」，时长和基频都拉开一点。
VARIANTS = [
    {"name": "hit_1", "seconds": 0.34, "f0": 52.0, "body_decay": 0.11,
     "crack_lo": 500.0, "crack_hi": 2800.0, "ring": 1650.0, "seed": 11},
    {"name": "hit_2", "seconds": 0.24, "f0": 64.0, "body_decay": 0.075,
     "crack_lo": 900.0, "crack_hi": 4600.0, "ring": 2350.0, "seed": 23},
    {"name": "hit_3", "seconds": 0.30, "f0": 58.0, "body_decay": 0.095,
     "crack_lo": 700.0, "crack_hi": 3600.0, "ring": 1980.0, "seed": 37},
]


def band_noise(n: int, lo: float, hi: float, rng: np.random.Generator) -> np.ndarray:
    raw = rng.standard_normal(n)
    sos = butter(2, [lo, hi], btype="bandpass", fs=SR, output="sos")
    y = sosfilt(sos, raw)
    return y / max(float(np.max(np.abs(y))), 1e-9)


def highpass_noise(n: int, lo: float, rng: np.random.Generator) -> np.ndarray:
    raw = rng.standard_normal(n)
    sos = butter(2, lo, btype="highpass", fs=SR, output="sos")
    y = sosfilt(sos, raw)
    return y / max(float(np.max(np.abs(y))), 1e-9)


def make_hit(spec: dict) -> np.ndarray:
    rng = np.random.default_rng(spec["seed"])
    seconds: float = spec["seconds"]
    n = int(seconds * SR)
    t = np.arange(n) / SR

    # 低频 body：起手 1.9 倍高，40ms 内落回基频，听感是「砸下去」而不是「嗡」。
    f0: float = spec["f0"]
    freq = f0 * (1.0 + 0.9 * np.exp(-t / 0.028))
    phase = 2.0 * math.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * np.exp(-t / spec["body_decay"])
    body += 0.45 * np.sin(phase * 2.0) * np.exp(-t / (spec["body_decay"] * 0.45))
    body *= np.minimum(t / 0.002, 1.0)

    # 中频 crack：决定「脆不脆」。
    crack = band_noise(n, spec["crack_lo"], spec["crack_hi"], rng)
    crack *= np.exp(-t / 0.018) * 0.85

    # 起手 click：极短，只负责让瞬态立起来。
    click = highpass_noise(n, 2600.0, rng) * np.exp(-t / 0.004) * 0.55

    # 金属余响：两个不成谐波的频率，衰减快，只是让声音不是一团噪声。
    ring = (np.sin(2.0 * math.pi * spec["ring"] * t)
            + 0.55 * np.sin(2.0 * math.pi * spec["ring"] * 1.47 * t)) * np.exp(-t / 0.035) * 0.08

    sig = body * 0.95 + crack + click + ring
    # 整体再收一道：打击音必须「来得快、走得也快」，尾巴拖长就变成一声闷雷。
    sig *= np.exp(-t / 0.105)

    # 短混响：给一点房间尾巴，不拖泥带水。
    ir_n = int(0.09 * SR)
    ir_t = np.arange(ir_n) / SR
    ir = rng.standard_normal(ir_n) * np.exp(-ir_t / 0.022)
    ir[0] = 1.0
    ir /= math.sqrt(float(np.sum(ir ** 2)))
    tail = np.convolve(sig, ir)[:n] * 0.15
    sig = sig + tail

    sig = np.tanh(sig * 1.15) / math.tanh(1.15)
    # 末尾 12ms 收到零，避免播放结束时「啪」一下。
    fade = int(0.012 * SR)
    sig[-fade:] *= np.linspace(1.0, 0.0, fade)
    # 峰值统一到 -1dBFS；三段响度接近，随机切换不会忽大忽小。
    sig *= 0.891 / max(float(np.max(np.abs(sig))), 1e-9)
    return sig.astype(np.float32)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for spec in VARIANTS:
        data = make_hit(spec)
        path = os.path.join(OUT_DIR, spec["name"] + ".wav")
        sf.write(path, data, SR, subtype="PCM_16")
        rms = math.sqrt(float(np.mean(data.astype(np.float64) ** 2)))
        print(f"{spec['name']}: {data.size / SR:.2f}s  peak={np.max(np.abs(data)):.3f}  "
              f"rms={rms:.3f}  {os.path.getsize(path) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
