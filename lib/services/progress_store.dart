import 'package:shared_preferences/shared_preferences.dart';

/// 存在手機裡的遊戲進度：金幣、已解鎖的夜市數、累計過關次數、是否已移除廣告。
class ProgressStore {
  ProgressStore._(this._prefs);

  static Future<ProgressStore> load() async => ProgressStore._(await SharedPreferences.getInstance());

  static const _coinsKey = 'coins';
  static const _unlockedKey = 'unlocked';
  static const _clearsKey = 'clears';
  static const _adsRemovedKey = 'ads_removed';
  static const _mutedKey = 'muted';

  final SharedPreferences _prefs;

  int get coins => _prefs.getInt(_coinsKey) ?? 0;
  int get unlocked => _prefs.getInt(_unlockedKey) ?? 1;
  int get clears => _prefs.getInt(_clearsKey) ?? 0;

  /// 之後做「移除廣告」付費項目時會把這個設成 true。
  bool get adsRemoved => _prefs.getBool(_adsRemovedKey) ?? false;

  bool get muted => _prefs.getBool(_mutedKey) ?? false;
  Future<void> setMuted(bool value) => _prefs.setBool(_mutedKey, value);

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
}
