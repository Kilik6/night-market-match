import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 遊戲音效。檔案在 assets/sounds/，由 tools/make_sounds.py 合成。
enum Sfx { flip, match, combo, miss, win, lose, coin }

/// 畫面只依賴這個介面，測試時可以換成假的。
abstract class SoundService {
  bool get muted;
  set muted(bool value);
  void play(Sfx sfx);
}

/// 用 audioplayers 播放。每種音效建一個小型播放池，連續快速翻牌也不會卡。
class AudioSoundService implements SoundService {
  AudioSoundService({bool muted = false}) : _muted = muted;

  final Map<Sfx, AudioPool> _pools = {};
  bool _muted;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  Future<void> init() async {
    // iOS 用 ambient 類別：會遵守靜音開關，也不打斷玩家正在聽的音樂
    // （通用的 AudioContextConfig 不允許 respectSilence 和 mixWithOthers 同時設定）
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build().android,
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
    } catch (e) {
      debugPrint('音訊設定失敗：$e');
    }
    for (final sfx in Sfx.values) {
      try {
        _pools[sfx] = await AudioPool.createFromAsset(
          path: 'sounds/${sfx.name}.wav',
          maxPlayers: sfx == Sfx.flip ? 4 : 2,
          playerMode: PlayerMode.lowLatency,
        );
      } catch (e) {
        debugPrint('音效 ${sfx.name} 載入失敗：$e');
      }
    }
  }

  @override
  void play(Sfx sfx) {
    if (_muted) return;
    _pools[sfx]?.start().catchError((Object e) {
      debugPrint('音效 ${sfx.name} 播放失敗：$e');
      return () async {};
    });
  }
}
