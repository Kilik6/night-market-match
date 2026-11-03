"""合成夜市翻牌的背景音樂：五聲音階的撥弦旋律、低音、木魚節奏，可以無縫循環。

用法：python3 tools/make_music.py assets/sounds
輸出 bgm.wav（22.05kHz、16-bit、單聲道，約 21 秒）。
"""
import math
import random
import struct
import sys
import wave

SR = 22050
OUT = sys.argv[1]
random.seed(11)

BPM = 92
BEAT = 60 / BPM
BARS = 8
LENGTH = int(SR * BEAT * 4 * BARS)

buf = [0.0] * LENGTH


def add(start_sec, samples):
    """疊到音軌上；超出結尾的部分繞回開頭，讓循環接縫沒有斷音。"""
    o = int(start_sec * SR)
    for i, v in enumerate(samples):
        buf[(o + i) % LENGTH] += v


def pluck(freq, dur, vol):
    """古箏感的撥弦：多個泛音、高頻衰減得比較快。"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = (math.sin(2 * math.pi * freq * t) * math.exp(-3.2 * t)
             + 0.45 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-5.5 * t)
             + 0.18 * math.sin(2 * math.pi * freq * 3 * t) * math.exp(-8 * t))
        out.append(vol * min(1, t / 0.003) * s)
    return out


def bass(freq, dur, vol):
    n = int(SR * dur)
    return [vol * min(1, (i / SR) / 0.02) * math.exp(-1.6 * i / SR)
            * (math.sin(2 * math.pi * freq * i / SR) + 0.25 * math.sin(4 * math.pi * freq * i / SR))
            for i in range(n)]


def woodblock(vol, pitch=1.0):
    n = int(SR * 0.06)
    return [vol * math.exp(-70 * i / SR) * (math.sin(2 * math.pi * 1250 * pitch * i / SR)
                                            + 0.3 * (random.random() * 2 - 1))
            for i in range(n)]


# D 宮五聲音階：D E F# A B
NOTE = {'A3': 220.0, 'B3': 246.9, 'D4': 293.7, 'E4': 329.6, 'F#4': 370.0, 'A4': 440.0,
        'B4': 493.9, 'D5': 587.3, 'E5': 659.3, 'F#5': 740.0, 'A5': 880.0}

# 旋律：(拍數, 音)；None 是休止。每小節 4 拍，共 8 小節。
melody = [
    (1, 'A4'), (0.5, 'B4'), (0.5, 'A4'), (1, 'F#4'), (1, 'E4'),
    (1.5, 'D4'), (0.5, 'E4'), (1, 'F#4'), (1, None),
    (1, 'A4'), (0.5, 'D5'), (0.5, 'B4'), (1, 'A4'), (1, 'F#4'),
    (1.5, 'E4'), (0.5, 'F#4'), (2, 'E4'),
    (1, 'B4'), (0.5, 'D5'), (0.5, 'E5'), (1, 'D5'), (1, 'B4'),
    (1, 'A4'), (0.5, 'B4'), (0.5, 'A4'), (1, 'F#4'), (1, 'E4'),
    (1, 'F#4'), (0.5, 'A4'), (0.5, 'F#4'), (1, 'E4'), (1, 'D4'),
    (2, 'E4'), (2, 'D4'),
]
assert sum(b for b, _ in melody) == BARS * 4, sum(b for b, _ in melody)

t = 0.0
for beats, n in melody:
    if n:
        add(t * BEAT, pluck(NOTE[n], beats * BEAT + 0.8, 0.32))
    t += beats

# 低音：每小節兩個音
bass_line = ['D4', 'A3', 'D4', 'A3', 'B3', 'A3', 'D4', 'A3', 'B3', 'A3', 'D4', 'A3', 'B3', 'A3', 'D4', 'D4']
for i, n in enumerate(bass_line):
    add(i * 2 * BEAT, bass(NOTE[n] / 2, 2 * BEAT + 0.4, 0.28))

# 木魚：第 1、3 拍重，反拍輕
for beat in range(BARS * 4):
    add(beat * BEAT, woodblock(0.12 if beat % 2 == 0 else 0.07, 1.0 if beat % 4 == 0 else 1.15))
    add((beat + 0.5) * BEAT, woodblock(0.04, 1.3))

peak = max(abs(v) for v in buf)
with wave.open(f"{OUT}/bgm.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(v / peak * 0.7 * 32767)) for v in buf))
print(f"done: {LENGTH / SR:.1f}s")
