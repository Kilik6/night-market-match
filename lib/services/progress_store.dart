import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/achievements.dart';
import '../game/card_skins.dart';
import '../game/items.dart';
import '../game/night_market_data.dart';

/// 存在手機裡的遊戲進度與設定。key 名稱上架後不要改，否則玩家的存檔會讀不到。
class ProgressStore {
  ProgressStore._(this._prefs, this._clock);

  /// [clock] 讓測試可以指定「今天」。
  static Future<ProgressStore> load({DateTime Function()? clock}) async =>
      ProgressStore._(await SharedPreferences.getInstance(), clock ?? DateTime.now);

  static const _coinsKey = 'coins';
  static const _unlockedKey = 'unlocked';
  static const _clearsKey = 'clears';
  static const _adsRemovedKey = 'ads_removed';
  static const _mutedKey = 'muted';
  static const _musicOnKey = 'music_on';
  static const _ownedSkinsKey = 'owned_skins';
  static const _equippedSkinKey = 'equipped_skin';
  static const _bestComboKey = 'stat_best_combo';
  static const _perfectRunsKey = 'stat_perfect_runs';
  static const _foodsKey = 'foods';
  static const _achievementsKey = 'ach_claimed';
  static const _dailyDateKey = 'daily_date';
  static const _dailyClaimedKey = 'daily_claimed';
  static const _checkInDateKey = 'checkin_last';
  static const _checkInStreakKey = 'checkin_streak';
  static const _endlessBestKey = 'endless_best_score';
  static const _endlessBestMatchesKey = 'stat_endless_best_matches';
  static const _endlessRoundsKey = 'stat_endless_rounds';
  static String _starsKey(int level) => 'stars_$level';
  static String _itemKey(ItemType type) => 'item_${type.name}';
  static String _gearKey(GearType type) => 'gear_${type.name}';
  static String _dailyProgressKey(String id) => 'daily_p_$id';

  /// 重置進度時要清掉的 key 前綴。
  static const _resetPrefixes = ['stars_', 'item_', 'gear_', 'stat_', 'daily_', 'checkin_'];

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

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

  // ---------- 星數 ----------

  /// 每一攤的最佳星數（0 表示還沒過關）。
  int bestStars(int level) => _prefs.getInt(_starsKey(level)) ?? 0;

  /// 記錄星數，只有比之前好才更新。回傳是否刷新紀錄。
  Future<bool> recordStars(int level, int stars) async {
    if (stars <= bestStars(level)) return false;
    await _prefs.setInt(_starsKey(level), stars);
    return true;
  }

  int get totalStars => List.generate(levels.length, bestStars).reduce((a, b) => a + b);
  int get levelsCleared => List.generate(levels.length, bestStars).where((s) => s > 0).length;

  // ---------- 卡背 ----------

  Set<String> get ownedSkins => {defaultSkinId, ...?_prefs.getStringList(_ownedSkinsKey)};
  String get equippedSkin {
    final id = _prefs.getString(_equippedSkinKey) ?? defaultSkinId;
    return ownedSkins.contains(id) ? id : defaultSkinId;
  }

  Future<void> _grantSkin(String id) =>
      _prefs.setStringList(_ownedSkinsKey, {...ownedSkins, id}.where((s) => s != defaultSkinId).toList());

  /// 用金幣買卡背。金幣不夠、已經擁有或只能靠成就取得就回傳 false。
  Future<bool> buySkin(CardSkin skin) async {
    if (skin.achievementOnly || ownedSkins.contains(skin.id) || coins < skin.price) return false;
    await _prefs.setInt(_coinsKey, coins - skin.price);
    await _grantSkin(skin.id);
    return true;
  }

  Future<void> equipSkin(String id) async {
    if (ownedSkins.contains(id)) await _prefs.setString(_equippedSkinKey, id);
  }

  // ---------- 道具 ----------

  int itemCount(ItemType type) => _prefs.getInt(_itemKey(type)) ?? 0;

  Future<void> addItem(ItemType type, [int amount = 1]) => _prefs.setInt(_itemKey(type), itemCount(type) + amount);

  Future<bool> buyItem(ItemType type) async {
    if (coins < type.price) return false;
    await _prefs.setInt(_coinsKey, coins - type.price);
    await addItem(type);
    return true;
  }

  /// 用掉一個道具，並計入每日任務。
  Future<bool> consumeItem(ItemType type) async {
    if (itemCount(type) <= 0) return false;
    await addItem(type, -1);
    _bumpDaily('item');
    return true;
  }

  // ---------- 裝備 ----------

  int gearLevel(GearType type) => _prefs.getInt(_gearKey(type)) ?? 0;

  /// 下一級的費用，已滿級回傳 null。
  int? upgradeCost(GearType type) {
    final level = gearLevel(type);
    return level >= type.maxLevel ? null : type.costs[level];
  }

  Future<bool> upgradeGear(GearType type) async {
    final cost = upgradeCost(type);
    if (cost == null || coins < cost) return false;
    await _prefs.setInt(_coinsKey, coins - cost);
    await _prefs.setInt(_gearKey(type), gearLevel(type) + 1);
    return true;
  }

  // ---------- 遊戲紀錄（圖鑑、成就、每日任務的來源） ----------

  int get bestCombo => _prefs.getInt(_bestComboKey) ?? 0;
  int get perfectRuns => _prefs.getInt(_perfectRunsKey) ?? 0;
  Set<String> get discoveredFoods => (_prefs.getStringList(_foodsKey) ?? const []).toSet();

  /// 每配對成功一組就呼叫。回傳這次是否收錄了新的小吃。
  Future<bool> recordMatch(Food food, int combo) async {
    final found = discoveredFoods;
    final isNew = found.add(food.name);
    if (isNew) await _prefs.setStringList(_foodsKey, found.toList());
    if (combo > bestCombo) await _prefs.setInt(_bestComboKey, combo);
    _bumpDaily('match');
    if (combo >= 5) _bumpDaily('combo5');
    return isNew;
  }

  /// 過關時呼叫（在 [addClear] 之外，記錄這一局的表現）。
  Future<void> recordWin({required int stars, required int mistakes}) async {
    _bumpDaily('clear');
    if (stars >= 3) _bumpDaily('stars3');
    if (mistakes == 0) {
      await _prefs.setInt(_perfectRunsKey, perfectRuns + 1);
      _bumpDaily('perfect');
    }
  }

  // ---------- 夜市大胃王（無盡模式） ----------

  int get endlessBest => _prefs.getInt(_endlessBestKey) ?? 0;
  int get endlessBestMatches => _prefs.getInt(_endlessBestMatchesKey) ?? 0;
  int get endlessRounds => _prefs.getInt(_endlessRoundsKey) ?? 0;

  /// 時間到時呼叫（續命後再次時間到也要呼叫）。記錄單輪最高分和最多組數，回傳是否刷新最高分。
  Future<bool> recordEndlessScore(int score, {int matches = 0}) async {
    if (matches > endlessBestMatches) await _prefs.setInt(_endlessBestMatchesKey, matches);
    if (score <= endlessBest) return false;
    await _prefs.setInt(_endlessBestKey, score);
    return true;
  }

  /// 每一輪只呼叫一次，累積玩了幾輪。
  Future<void> recordEndlessRound() => _prefs.setInt(_endlessRoundsKey, endlessRounds + 1);

  // ---------- 成就 ----------

  int metricValue(Metric metric) => switch (metric) {
        Metric.clears => clears,
        Metric.bestCombo => bestCombo,
        Metric.perfectRuns => perfectRuns,
        Metric.totalStars => totalStars,
        Metric.foods => discoveredFoods.length,
        Metric.levelsCleared => levelsCleared,
        Metric.endlessBest => endlessBest,
        Metric.endlessBestMatches => endlessBestMatches,
        Metric.endlessRounds => endlessRounds,
      };

  bool isAchieved(Achievement a) => metricValue(a.metric) >= a.target;

  Set<String> get _claimedAchievements => (_prefs.getStringList(_achievementsKey) ?? const []).toSet();
  bool isClaimed(Achievement a) => _claimedAchievements.contains(a.id);

  bool get hasClaimableAchievement => achievements.any((a) => isAchieved(a) && !isClaimed(a));

  /// 領取成就獎勵。還沒達成或已經領過回傳 false。
  Future<bool> claimAchievement(Achievement a) async {
    if (!isAchieved(a) || isClaimed(a)) return false;
    await _prefs.setStringList(_achievementsKey, {..._claimedAchievements, a.id}.toList());
    if (a.coins > 0) await addCoins(a.coins);
    if (a.skinId != null) await _grantSkin(a.skinId!);
    return true;
  }

  // ---------- 每日任務與簽到 ----------

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _today => _dateKey(_clock());

  /// 換日時清掉昨天的任務進度。SharedPreferences 會立刻更新記憶體，所以可以不等寫入。
  void _rollDaily() {
    if (_prefs.getString(_dailyDateKey) == _today) return;
    _prefs.setString(_dailyDateKey, _today);
    _prefs.remove(_dailyClaimedKey);
    for (final task in dailyTaskPool) {
      _prefs.remove(_dailyProgressKey(task.id));
    }
  }

  void _bumpDaily(String id) {
    _rollDaily();
    _prefs.setInt(_dailyProgressKey(id), dailyProgress(id) + 1);
  }

  int dailyProgress(String id) {
    _rollDaily();
    return _prefs.getInt(_dailyProgressKey(id)) ?? 0;
  }

  /// 今天的 3 個任務：依日期固定抽選，同一天重開 App 不會變。
  List<DailyTask> get todayTasks {
    final now = _clock();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    return (dailyTaskPool.toList()..shuffle(Random(seed))).take(3).toList();
  }

  Set<String> get _claimedDaily {
    _rollDaily();
    return (_prefs.getStringList(_dailyClaimedKey) ?? const []).toSet();
  }

  bool isDailyDone(DailyTask t) => dailyProgress(t.id) >= t.target;
  bool isDailyClaimed(DailyTask t) => _claimedDaily.contains(t.id);

  Future<bool> claimDaily(DailyTask t) async {
    if (!isDailyDone(t) || isDailyClaimed(t)) return false;
    await _prefs.setStringList(_dailyClaimedKey, {..._claimedDaily, t.id}.toList());
    await addCoins(t.coins);
    return true;
  }

  bool get canCheckIn => _prefs.getString(_checkInDateKey) != _today;

  /// 連續簽到天數（1～7）。
  int get checkInStreak => _prefs.getInt(_checkInStreakKey) ?? 0;

  /// 下一次簽到是連續第幾天。
  int get nextCheckInDay {
    final now = _clock();
    final yesterday = _dateKey(DateTime(now.year, now.month, now.day - 1));
    final last = _prefs.getString(_checkInDateKey);
    if (last == _today) return checkInStreak; // 今天已簽到
    if (last != yesterday) return 1; // 斷掉了，重新開始
    return checkInStreak % checkInRewards.length + 1;
  }

  /// 簽到並領金幣，回傳領到的金幣；今天簽過回傳 0。
  Future<int> checkIn() async {
    if (!canCheckIn) return 0;
    final day = nextCheckInDay;
    final reward = checkInRewards[day - 1];
    await _prefs.setString(_checkInDateKey, _today);
    await _prefs.setInt(_checkInStreakKey, day);
    await addCoins(reward);
    return reward;
  }

  bool get hasClaimableDaily => canCheckIn || todayTasks.any((t) => isDailyDone(t) && !isDailyClaimed(t));

  // ---------- 重置 ----------

  /// 重置遊戲進度。保留音樂／音效設定，以及用真錢買的「移除廣告」。
  Future<void> resetProgress() async {
    final prefixed = _prefs.getKeys().where((k) => _resetPrefixes.any(k.startsWith)).toList();
    for (final k in [
      _coinsKey,
      _unlockedKey,
      _clearsKey,
      _ownedSkinsKey,
      _equippedSkinKey,
      _foodsKey,
      _achievementsKey,
      _endlessBestKey,
      ...prefixed,
    ]) {
      await _prefs.remove(k);
    }
  }
}
