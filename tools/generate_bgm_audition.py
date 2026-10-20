"""生成 BGM 降嗡声的试听候选，不碰 assets/audio/bgm/ 里的正式文件。

第一章的嗡声主要落在 200~320Hz：持续和弦垫的根音区叠得太厚；低频持续音
（73/110Hz）和风声的低频段又把它垫实了。这里做两版：

  A_eq   只对现成 OGG 做循环域 EQ：45Hz 高通 + 230Hz 一带收 4dB + 低频轻收。
         曲子编排完全不动，适合「只是嗡声重、别的都满意」。
  B_soft 重新合成：和弦垫 -2dB、持续音 -8dB、风声 -2.5dB，再做同一套 EQ。
         改动更彻底，适合 A 还觉得闷的情况。

两版都按原母带同一口径归一化到 RMS -20dBFS、峰值留 3dB，试听时响度一致。
输出到项目根目录 _audition_bgm/，游戏内文件保持原样，等试听通过再替换。

    python tools/generate_bgm_audition.py
"""
from __future__ import annotations

import copy
import math
import os
import sys

import numpy as np
import soundfile as sf

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
sys.path.insert(0, TOOLS_DIR)
import generate_bgm as g  # noqa: E402

OUT_DIR = os.path.join(ROOT, "_audition_bgm")
SRC_DIR = os.path.join(ROOT, "assets", "audio", "bgm")


def circular_eq(x: np.ndarray) -> np.ndarray:
    n = x.shape[0]
    freqs = np.fft.rfftfreq(n, 1.0 / g.SR)
    # 45Hz 二阶高通：切掉听不见但会糊住低频的次声。
    hp = 1.0 / np.sqrt(1.0 + (45.0 / np.maximum(freqs, 1e-6)) ** 4)
    # 280Hz 宽钟形衰减 5dB：这是「嗡」的主频段（250~400Hz 都压到）。
    bell_db = -5.0 * np.exp(-0.5 * (np.log2(np.maximum(freqs, 1.0) / 280.0) / 0.80) ** 2)
    # 120Hz 以下再轻收 2.5dB，压住持续低音对「闷」的贡献。
    low_db = -2.5 / (1.0 + (freqs / 120.0) ** 2)
    gain = hp * 10.0 ** ((bell_db + low_db) / 20.0)
    return np.fft.irfft(np.fft.rfft(x, axis=0) * gain[:, None], n, axis=0)


def normalize(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float64, copy=True)
    rms = math.sqrt(float(np.mean(x ** 2)))
    x *= 10 ** (-20.0 / 20.0) / max(rms, 1e-9)
    peak = float(np.max(np.abs(x)))
    ceiling = 10 ** (-3.0 / 20.0)
    if peak > ceiling:
        x *= ceiling / peak
    return x


def bands(x: np.ndarray) -> dict[str, float]:
    from scipy.signal import welch
    mono = x.mean(axis=1)
    f, p = welch(mono, fs=g.SR, nperseg=32768)
    total = float(np.trapezoid(p[(f >= 20) & (f < 20000)], f[(f >= 20) & (f < 20000)]))
    out = {}
    for lo, hi in [(20, 60), (60, 120), (120, 200), (200, 320), (320, 640)]:
        sel = (f >= lo) & (f < hi)
        out[f"{lo}-{hi}"] = 10 * math.log10(
            float(np.trapezoid(p[sel], f[sel])) / max(total, 1e-20))
    return out


def soft_spec(spec: dict) -> dict:
    s = copy.deepcopy(spec)
    s["pad_level"] *= 0.72
    s["drone_level"] *= 0.22
    s["wind_level"] *= 0.68
    return s


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, spec in g.TRACKS.items():
        # A：现成录音只做 EQ。
        src, sr = sf.read(os.path.join(SRC_DIR, name + ".ogg"), always_2d=True)
        if sr != g.SR:
            raise SystemExit(f"{name}: 采样率 {sr} != {g.SR}")
        a = normalize(circular_eq(src))
        a_path = os.path.join(OUT_DIR, f"{name}_A_eq.ogg")
        g.write_ogg(a_path, a)

        # B：重新合成（同一随机种子、同一渲染顺序），再走同一套 EQ。
        b = normalize(circular_eq(g.render_track(soft_spec(spec))))
        b_path = os.path.join(OUT_DIR, f"{name}_B_soft.ogg")
        g.write_ogg(b_path, b)

        print(f"{name}:")
        print("  原始   ", " ".join(f"{k}:{v:+.1f}" for k, v in bands(src).items()))
        print("  A_eq   ", " ".join(f"{k}:{v:+.1f}" for k, v in bands(a).items()))
        print("  B_soft ", " ".join(f"{k}:{v:+.1f}" for k, v in bands(b).items()))
        print(f"  写出 {os.path.basename(a_path)} / {os.path.basename(b_path)}")


if __name__ == "__main__":
    main()
