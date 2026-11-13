"""用純 Python 合成夜市翻牌的音效（16-bit mono WAV, 44.1kHz）。

用法：python3 tools/make_sounds.py assets/sounds
"""
import math
import random
import struct
import sys
import wave

SR = 44100
OUT = sys.argv[1]
random.seed(7)


def note(freq, dur, vol=0.5, decay=6.0, harmonics=((1, 1.0), (2, 0.35), (3, 0.12)), attack=0.004):
    """鐘聲感的音：基音加泛音，快速起音、指數衰減。"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-decay * t)
        s = sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics)
        out.append(vol * env * s)
    return out


def sweep(f0, f1, dur, vol=0.5, decay=30.0, noise=0.0):
    n = int(SR * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / SR
        env = min(1.0, t / 0.002) * math.exp(-decay * t)
        s = math.sin(phase) + noise * (random.random() * 2 - 1)
        out.append(vol * env * s)
    return out


def silence(dur):
    return [0.0] * int(SR * dur)


def mix(*tracks):
    """把多軌疊在一起（每軌可以是 (起始秒數, 樣本)）。"""
    length = max(int(SR * start) + len(s) for start, s in tracks)
    out = [0.0] * length
    for start, s in tracks:
        o = int(SR * start)
        for i, v in enumerate(s):
            out[o + i] += v
    return out


def save(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    k = gain / peak
    fade = int(SR * 0.01)
    with wave.open(f"{OUT}/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for i, s in enumerate(samples):
            if i > len(samples) - fade:
                s *= (len(samples) - i) / fade
            frames += struct.pack("<h", int(max(-1, min(1, s * k)) * 32767))
        w.writeframes(bytes(frames))


# 翻牌：短促的「啪」— 下滑音加一點雜訊
save("flip", sweep(1400, 500, 0.07, decay=45, noise=0.35), gain=0.55)

# 配對成功：兩個上行的鐘聲
save("match", mix((0, note(1318.5, 0.35)), (0.08, note(1760.0, 0.45))), gain=0.7)

# 連擊（3 連以上）：三個上行的鐘聲
save("combo", mix((0, note(1318.5, 0.3)), (0.07, note(1760.0, 0.3)), (0.14, note(2217.5, 0.5))), gain=0.75)

# 翻錯：低沉的兩聲「嘟嘟」
low = ((1, 1.0), (3, 0.25), (5, 0.08))
save("miss", mix((0, note(233.1, 0.14, decay=12, harmonics=low)),
                 (0.12, note(196.0, 0.22, decay=10, harmonics=low))), gain=0.6)

# 過關：C 大調琶音，最後和弦延長
win = [(0.00, 523.3), (0.09, 659.3), (0.18, 784.0), (0.27, 1046.5)]
tracks = [(t, note(f, 0.4, decay=7)) for t, f in win]
tracks += [(0.40, note(f, 1.0, vol=0.35, decay=3)) for f in (523.3, 659.3, 784.0, 1046.5)]
save("win", mix(*tracks), gain=0.8)

# 時間到：下行三音
lose = [(0.0, 784.0), (0.18, 659.3), (0.36, 523.3)]
save("lose", mix(*[(t, note(f, 0.5 if i == 2 else 0.25, decay=5 if i == 2 else 9)) for i, (t, f) in enumerate(lose)]),
     gain=0.6)

# 金幣：快速的兩個高音
save("coin", mix((0, note(987.8, 0.08, decay=20)), (0.07, note(1318.5, 0.4, decay=8))), gain=0.6)

# 記牌倒數：輕柔的木頭「叩」聲，每秒一下
save("countdown", mix((0, note(1046.5, 0.12, decay=28, harmonics=((1, 1.0), (2.76, 0.3)))),
                      (0, sweep(1800, 900, 0.02, decay=120, noise=0.6))), gain=0.45)

# 剩 5 秒：輕輕的時鐘「滴、答」，每秒交替一聲
def clock_tick(freq):
    click = [0.25 * math.exp(-200 * i / SR) * (random.random() * 2 - 1) for i in range(int(SR * 0.02))]
    return mix((0, note(freq, 0.06, decay=70, harmonics=((1, 1.0), (2.3, 0.4)))), (0, click))


save("hurry", clock_tick(1200), gain=0.35)
save("hurry_tock", clock_tick(950), gain=0.35)

print("done")
