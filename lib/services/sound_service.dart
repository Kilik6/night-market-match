import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 遊戲音效。檔案在 assets/sounds/，由 tools/make_sounds.py 合成；
/// 背景音樂 bgm.wav 由 tools/make_music.py 合成。
///
/// [countdown] 是開局記牌時每秒的倒數聲；剩最後 [hurrySeconds] 秒時，每秒交替播 [hurry]（滴）和 [hurryTock]（答）。
enum Sfx { flip, match, combo, miss, win, lose, coin, countdown, hurry, hurryTock }

/// 剩幾秒開始播 [Sfx.hurry]。
const hurrySeconds = 5;

/// 畫面只依賴這個介面，測試時可以換成假的。
abstract class SoundService {
  /// 音效靜音。
  bool get muted;
  set muted(bool value);
  void play(Sfx sfx);

  /// 背景音樂開關。關掉會停止播放，打開會從頭播放。
  bool get musicOn;
  set musicOn(bool value);

  /// 背景音樂音量（設定頁的滑桿，0～1），調整後馬上生效。
  double get musicVolume;
  set musicVolume(double value);

  /// 音效音量（設定頁的滑桿，0～1）。
  double get sfxVolume;
  set sfxVolume(double value);

  /// 暫時暫停／恢復背景音樂（播廣告、App 切到背景時用），不影響開關設定。
  void pauseMusic();
  void resumeMusic();
}

/// 滑桿的預設值：背景音樂在中間（實際音量 0.35，和加滑桿前一樣），音效開到最大。
const defaultMusicVolume = 0.5;
const defaultSfxVolume = 1.0;

/// 用 audioplayers 播放。每種音效建一個小型播放池，連續快速翻牌也不會卡。
class AudioSoundService implements SoundService {
  AudioSoundService({
    bool muted = false,
    bool musicOn = true,
    double musicVolume = defaultMusicVolume,
    double sfxVolume = defaultSfxVolume,
  })  : _muted = muted,
        _musicOn = musicOn,
        _musicVolume = musicVolume.clamp(0, 1),
        _sfxVolume = sfxVolume.clamp(0, 1);

  /// 背景音樂滑桿拉到最大時的播放音量。背景音樂要比音效小聲，滑桿中間就是原本的 0.35。
  static const maxMusicVolume = 0.7;

  final Map<Sfx, AudioPool> _pools = {};
  final AudioPlayer _music = AudioPlayer();
  bool _muted;
  bool _musicOn;
  double _musicVolume;
  double _sfxVolume;
  bool _musicReady = false;
  bool _musicPaused = false;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  @override
  double get musicVolume => _musicVolume;

  @override
  set musicVolume(double value) {
    _musicVolume = value.clamp(0, 1);
    if (_musicReady) _music.setVolume(_musicVolume * maxMusicVolume);
  }

  @override
  double get sfxVolume => _sfxVolume;

  @override
  set sfxVolume(double value) => _sfxVolume = value.clamp(0, 1);

  @override
  bool get musicOn => _musicOn;

  @override
  set musicOn(bool value) {
    _musicOn = value;
    if (value) {
      _startMusic();
    } else {
      _music.stop();
    }
  }

  @override
  void pauseMusic() {
    _musicPaused = true;
    if (_musicReady) _music.pause();
  }

  @override
  void resumeMusic() {
    _musicPaused = false;
    if (!_musicReady || !_musicOn) return;
    if (_music.state == PlayerState.paused) {
      _music.resume();
    } else if (_music.state != PlayerState.playing) {
      _startMusic();
    }
  }

  void _startMusic() {
    if (!_musicReady || !_musicOn || _musicPaused) return;
    _music.play(AssetSource('sounds/bgm.wav'), volume: _musicVolume * maxMusicVolume).catchError((Object e) {
      debugPrint('背景音樂播放失敗：$e');
    });
  }

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
          path: 'sounds/${sfx == Sfx.hurryTock ? 'hurry_tock' : sfx.name}.wav',
          maxPlayers: sfx == Sfx.flip ? 4 : 2,
          playerMode: PlayerMode.lowLatency,
        );
      } catch (e) {
        debugPrint('音效 ${sfx.name} 載入失敗：$e');
      }
    }
    try {
      await _music.setReleaseMode(ReleaseMode.loop);
      _musicReady = true;
      _startMusic();
    } catch (e) {
      debugPrint('背景音樂載入失敗：$e');
    }
  }

  @override
  void play(Sfx sfx) {
    if (_muted || _sfxVolume <= 0) return;
    _pools[sfx]?.start(volume: _sfxVolume).catchError((Object e) {
      debugPrint('音效 ${sfx.name} 播放失敗：$e');
      return () async {};
    });
  }
}
