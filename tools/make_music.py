"""合成夜市翻牌的背景音樂「小吃攤輕快」：烏克麗麗旋律和刷和弦、低音、拍手和沙鈴，可以無縫循環。

用法：python3 tools/make_music.py assets/sounds
輸出 bgm.wav（22.05kHz、16-bit、單聲道，約 18.5 秒）。
"""
import math
import random
import struct
import sys
import wave

SR = 22050
OUT = sys.argv[1]

NOTES = {}
for octave in range(2, 7):
    for i, name in enumerate(['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']):
        NOTES[f'{name}{octave}'] = 440.0 * 2 ** ((octave - 4) + (i - 9) / 12)

BPM = 104
BEAT = 60 / BPM
BARS = 8
LENGTH = int(SR * BEAT * 4 * BARS)
buf = [0.0] * LENGTH


def add(beat_pos, samples):
    """疊到音軌上；超出結尾的部分繞回開頭，循環接縫才不會斷音。"""
    o = int(beat_pos * BEAT * SR)
    for i, v in enumerate(samples):
        buf[(o + i) % LENGTH] += v


def env(i, attack, decay):
    t = i / SR
    return min(1, t / attack) * math.exp(-decay * t)


def uke(freq, dur, vol):
    """烏克麗麗感的撥弦：短而亮。"""
    n = int(SR * min(dur, 1.2))
    return [vol * env(i, 0.002, 5.0) * (math.sin(2 * math.pi * freq * i / SR)
                                        + 0.5 * math.sin(4 * math.pi * freq * i / SR) * math.exp(-4 * i / SR)
                                        + 0.25 * math.sin(6 * math.pi * freq * i / SR) * math.exp(-9 * i / SR))
            for i in range(n)]


def soft_bass(freq, dur, vol):
    n = int(SR * dur)
    return [vol * min(1, (i / SR) / 0.02) * math.exp(-1.2 * i / SR)
            * (math.sin(2 * math.pi * freq * i / SR) + 0.2 * math.sin(4 * math.pi * freq * i / SR)) for i in range(n)]


def clap(vol):
    n = int(SR * 0.12)
    return [vol * (math.exp(-40 * i / SR) + 0.6 * math.exp(-40 * max(0, i / SR - 0.012))) * (random.random() * 2 - 1)
            for i in range(n)]


def shaker(vol):
    n = int(SR * 0.05)
    return [vol * math.sin(math.pi * i / n) * (random.random() * 2 - 1) for i in range(n)]


random.seed(4)

# 旋律：(拍數, 音)；None 是休止。每小節 4 拍，共 8 小節。
melody = [
    (1, 'G4'), (0.5, 'A4'), (0.5, 'B4'), (1, 'D5'), (1, 'B4'),
    (1, 'C5'), (0.5, 'B4'), (0.5, 'A4'), (2, 'G4'),
    (1, 'E4'), (0.5, 'G4'), (0.5, 'A4'), (1, 'B4'), (1, 'A4'),
    (1, 'G4'), (1, 'E4'), (2, 'D4'),
    (1, 'G4'), (0.5, 'A4'), (0.5, 'B4'), (1, 'D5'), (1, 'E5'),
    (1, 'D5'), (0.5, 'B4'), (0.5, 'A4'), (2, 'B4'),
    (1, 'C5'), (1, 'B4'), (1, 'A4'), (1, 'D4'),
    (3, 'G4'), (1, None),
]
assert sum(b for b, _ in melody) == BARS * 4
t = 0.0
for beats, n in melody:
    if n:
        add(t, uke(NOTES[n], beats * BEAT + 0.2, 0.26))
    t += beats

# 刷和弦（每小節五下）和低音
chord_bars = [['G3', 'B3', 'D4'], ['C4', 'E4', 'G4'], ['E3', 'G3', 'B3'], ['D3', 'F#3', 'A3'],
              ['G3', 'B3', 'D4'], ['C4', 'E4', 'G4'], ['A3', 'C4', 'E4'], ['G3', 'B3', 'D4']]
for bar, ch in enumerate(chord_bars):
    for k, pos in enumerate([0, 1, 1.5, 2.5, 3]):
        for j, n in enumerate(ch):
            add(bar * 4 + pos + j * 0.02, uke(NOTES[n], BEAT, 0.08 if k % 2 == 0 else 0.05))
    add(bar * 4, soft_bass(NOTES[ch[0]] / 2, 2 * BEAT, 0.2))
    add(bar * 4 + 2, soft_bass(NOTES[ch[0]] / 2, 2 * BEAT, 0.15))

# 拍手在第 2、4 拍，沙鈴在反拍
for beat in range(BARS * 4):
    if beat % 2 == 1:
        add(beat, clap(0.12))
    add(beat + 0.5, shaker(0.04))

peak = max(abs(v) for v in buf)
with wave.open(f"{OUT}/bgm.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(v / peak * 0.72 * 32767)) for v in buf))
print(f"done: {LENGTH / SR:.1f}s")
