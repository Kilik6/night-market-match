import 'package:shared_preferences/shared_preferences.dart';

import '../game/card_skins.dart';

/// 存在手機裡的遊戲進度與設定。key 名稱上架後不要改，否則玩家的存檔會讀不到。
class ProgressStore {
  ProgressStore._(this._prefs);

  static Future<ProgressStore> load() async => ProgressStore._(await SharedPreferences.getInstance());

  static const _coinsKey = 'coins';
  static const _unlockedKey = 'unlocked';
  static const _clearsKey = 'clears';
  static const _adsRemovedKey = 'ads_removed';
  static const _mutedKey = 'muted';
  static const _musicOnKey = 'music_on';
  static const _ownedSkinsKey = 'owned_skins';
  static const _equippedSkinKey = 'equipped_skin';
  static String _starsKey(int level) => 'stars_$level';

  final SharedPreferences _prefs;

  int get coins => _prefs.getInt(_coinsKey) ?? 0;
  int get unlocked => _prefs.getInt(_unlockedKey) ?? 1;
  int get clears => _prefs.getInt(_clearsKey) ?? 0;

  /// 之後做「移除廣告」付費項目時會把這個設成 true。
  bool get adsRemoved => _prefs.getBool(_adsRemovedKey) ?? false;

  /// 音效靜音。
  bool get muted => _prefs.getBool(_mutedKey) ?? false;
  Future<void> setMuted(bool value) => _prefs.setBool(_mutedKey, value);

  /// 背景音樂開關，預設開。
  bool get musicOn => _prefs.getBool(_musicOnKey) ?? true;
  Future<void> setMusicOn(bool value) => _prefs.setBool(_musicOnKey, value);

  Future<void> addCoins(int amount) => _prefs.setInt(_coinsKey, coins + amount);

  Future<void> unlockUpTo(int count) async {
    if (count > unlocked) await _prefs.setInt(_unlockedKey, count);
  }

  /// 累計過關次數加一，回傳新的次數。
  Future<int> addClear() async {
    final next = clears + 1;
    await _prefs.setInt(_clearsKey, next);
    return next;
  }

  /// 每一攤的最佳星數（0 表示還沒過關）。
  int bestStars(int level) => _prefs.getInt(_starsKey(level)) ?? 0;

  /// 記錄星數，只有比之前好才更新。回傳是否刷新紀錄。
  Future<bool> recordStars(int level, int stars) async {
    if (stars <= bestStars(level)) return false;
    await _prefs.setInt(_starsKey(level), stars);
    return true;
  }

  Set<String> get ownedSkins => {defaultSkinId, ...?_prefs.getStringList(_ownedSkinsKey)};
  String get equippedSkin {
    final id = _prefs.getString(_equippedSkinKey) ?? defaultSkinId;
    return ownedSkins.contains(id) ? id : defaultSkinId;
  }

  /// 用金幣買卡背。金幣不夠或已經擁有就回傳 false。
  Future<bool> buySkin(CardSkin skin) async {
    if (ownedSkins.contains(skin.id) || coins < skin.price) return false;
    await _prefs.setInt(_coinsKey, coins - skin.price);
    await _prefs.setStringList(_ownedSkinsKey, [...ownedSkins.where((id) => id != defaultSkinId), skin.id]);
    return true;
  }

  Future<void> equipSkin(String id) async {
    if (ownedSkins.contains(id)) await _prefs.setString(_equippedSkinKey, id);
  }

  /// 重置遊戲進度。保留音樂／音效設定，以及用真錢買的「移除廣告」。
  Future<void> resetProgress() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('stars_')).toList();
    for (final k in [_coinsKey, _unlockedKey, _clearsKey, _ownedSkinsKey, _equippedSkinKey, ...keys]) {
      await _prefs.remove(k);
    }
  }
}
