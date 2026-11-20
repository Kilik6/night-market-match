import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/achievements.dart';
import '../game/card_skins.dart';
import '../game/daily_challenge.dart';
import '../game/items.dart';
import '../game/night_market_data.dart';
import '../game/wheel.dart';
import 'purchase_service.dart';

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
  static const _musicVolumeKey = 'music_volume';
  static const _monthCardEndKey = 'month_card_end';
  static const _starterPackKey = 'starter_pack';
  static const _reminderOnKey = 'reminder_on';
  static const _reminderAskedKey = 'reminder_asked';
  static const _monthCardClaimedKey = 'month_card_claimed';
  static const _sfxVolumeKey = 'sfx_volume';
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
  static const _challengeStreakKey = 'daily_challenge_streak';
  static const _challengeLastKey = 'daily_challenge_last';
  static const _challengeBestStreakKey = 'stat_challenge_best_streak';
  static String _starsKey(int level) => 'stars_$level';
  static String _bestScoreKey(int level) => 'best_score_$level';
  static String _itemKey(ItemType type) => 'item_${type.name}';
  static String _gearKey(GearType type) => 'gear_${type.name}';
  static String _dailyProgressKey(String id) => 'daily_p_$id';

  /// 重置進度時要清掉的 key 前綴。
  static const _resetPrefixes = ['stars_', 'best_score_', 'item_', 'gear_', 'stat_', 'daily_', 'checkin_'];

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  int get coins => _prefs.getInt(_coinsKey) ?? 0;
  int get unlocked => _prefs.getInt(_unlockedKey) ?? 1;
  int get clears => _prefs.getInt(_clearsKey) ?? 0;

  /// 買了「永久移除廣告」：不再播插頁廣告（獎勵廣告保留，玩家可以自己選擇看）。
  bool get adsRemoved => _prefs.getBool(_adsRemovedKey) ?? false;
  Future<void> setAdsRemoved(bool value) => _prefs.setBool(_adsRemovedKey, value);

  /// 音效靜音。
  bool get muted => _prefs.getBool(_mutedKey) ?? false;
  Future<void> setMuted(bool value) => _prefs.setBool(_mutedKey, value);

  /// 背景音樂開關，預設開。
  bool get musicOn => _prefs.getBool(_musicOnKey) ?? true;
  Future<void> setMusicOn(bool value) => _prefs.setBool(_musicOnKey, value);

  /// 設定頁的音量滑桿（0～1）。沒存過時用預設值。重置進度不會清掉。
  double musicVolume(double fallback) => _prefs.getDouble(_musicVolumeKey) ?? fallback;
  Future<void> setMusicVolume(double value) => _prefs.setDouble(_musicVolumeKey, value);
  double sfxVolume(double fallback) => _prefs.getDouble(_sfxVolumeKey) ?? fallback;
  Future<void> setSfxVolume(double value) => _prefs.setDouble(_sfxVolumeKey, value);

  /// 每日提醒（晚上 8 點的通知）開關，預設關；玩家同意後才打開。重置進度不會清掉。
  bool get reminderOn => _prefs.getBool(_reminderOnKey) ?? false;
  Future<void> setReminderOn(bool value) => _prefs.setBool(_reminderOnKey, value);

  /// 已經問過要不要每日提醒了（只在第一次簽到後問一次）。
  bool get reminderAsked => _prefs.getBool(_reminderAskedKey) ?? false;
  Future<void> setReminderAsked() => _prefs.setBool(_reminderAskedKey, true);

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

  /// 這一攤的最高分（走透透重玩時只有破紀錄才發金幣）。
  int bestScore(int level) => _prefs.getInt(_bestScoreKey(level)) ?? 0;

  /// 記錄這一攤的分數，回傳原本的最高分。
  Future<int> recordScore(int level, int score) async {
    final before = bestScore(level);
    if (score > before) await _prefs.setInt(_bestScoreKey(level), score);
    return before;
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

  /// 用金幣買卡背。金幣不夠、已經擁有或只能靠成就、禮包取得就回傳 false。
  Future<bool> buySkin(CardSkin skin) async {
    if (!skin.buyable || ownedSkins.contains(skin.id) || coins < skin.price) return false;
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
    _bumpDaily('match100');
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
    // 吃胃藥後會再呼叫一次，所以這個任務只記一次
    if (score >= 10000 && dailyProgress('endless_score') == 0) _bumpDaily('endless_score');
    if (matches > endlessBestMatches) await _prefs.setInt(_endlessBestMatchesKey, matches);
    if (score <= endlessBest) return false;
    await _prefs.setInt(_endlessBestKey, score);
    return true;
  }

  /// 每一輪只呼叫一次，累積玩了幾輪。
  Future<void> recordEndlessRound() async {
    _bumpDaily('endless_round');
    await _prefs.setInt(_endlessRoundsKey, endlessRounds + 1);
  }

  /// 把桌上全部吃光（大胃王、每日挑戰）。
  void recordAllClear() => _bumpDaily('all_clear');

  /// 進入大胃王時間（大胃王、每日挑戰）。
  void recordFever() => _bumpDaily('fever');

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
        Metric.dailyBestStreak => dailyBestStreak,
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

  /// 今天的 [dailyTaskCount] 個任務：依日期固定抽選，同一天重開 App 不會變。
  /// 只能在走透透或只能在大胃王完成的任務各最多 [maxTasksPerMode] 個。
  List<DailyTask> get todayTasks {
    final now = _clock();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final picked = <DailyTask>[];
    for (final task in dailyTaskPool.toList()..shuffle(Random(seed))) {
      if (picked.length == dailyTaskCount) break;
      if (task.mode != TaskMode.any && picked.where((t) => t.mode == task.mode).length >= maxTasksPerMode) continue;
      picked.add(task);
    }
    return picked;
  }

  Set<String> get _claimedDaily {
    _rollDaily();
    return (_prefs.getStringList(_dailyClaimedKey) ?? const []).toSet();
  }

  bool isDailyDone(DailyTask t) => dailyProgress(t.id) >= t.target;
  bool isDailyClaimed(DailyTask t) => _claimedDaily.contains(t.id);

  /// 領每日任務的金幣；[doubled] 是看廣告領雙倍。
  Future<bool> claimDaily(DailyTask t, {bool doubled = false}) async {
    if (!isDailyDone(t) || isDailyClaimed(t)) return false;
    await _prefs.setStringList(_dailyClaimedKey, {..._claimedDaily, t.id}.toList());
    await addCoins(t.coins * (doubled ? 2 : 1));
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

  /// 今天簽到後，可以看廣告再領一次簽到獎勵（每天一次）。
  bool get canDoubleCheckIn => !canCheckIn && todayCount('checkin') == 0;

  /// 看完廣告：再領一次今天的簽到獎勵，回傳領到的金幣。
  Future<int> doubleCheckIn() async {
    if (!canDoubleCheckIn) return 0;
    await bumpToday('checkin');
    final reward = checkInRewards[checkInStreak - 1];
    await addCoins(reward);
    return reward;
  }

  bool get hasClaimableDaily =>
      canCheckIn ||
      canClaimMonthCard ||
      wheelFreeAvailable ||
      todayTasks.any((t) => isDailyDone(t) && !isDailyClaimed(t)) ||
      canOpenDailyChest;

  /// 今天的任務領了幾個（寶箱的進度）。
  int get dailyTasksClaimed => todayTasks.where(isDailyClaimed).length;

  /// 寶箱今天開過了（跟任務的領取紀錄存在一起，換日自動清掉）。
  bool get dailyChestOpened => _claimedDaily.contains(_chestId);
  static const _chestId = 'chest';

  /// 今天的任務全部領完、寶箱還沒開。
  bool get canOpenDailyChest => !dailyChestOpened && dailyTasksClaimed == todayTasks.length;

  /// 開寶箱：[dailyChestCoins] 金幣（[doubled] 看廣告 ×2）和一個招財貓。不能開回傳 false。
  Future<bool> openDailyChest({bool doubled = false}) async {
    if (!canOpenDailyChest) return false;
    await _prefs.setStringList(_dailyClaimedKey, {..._claimedDaily, _chestId}.toList());
    await addCoins(dailyChestCoins * (doubled ? 2 : 1));
    await addItem(ItemType.luckyCat);
    return true;
  }

  // ---------- 新手禮包 ----------

  /// 買過新手禮包了（每個人只能買一次；重置遊戲進度也不會清掉）。
  bool get starterPackBought => _prefs.getBool(_starterPackKey) ?? false;

  /// 付款成功後呼叫：發金幣、每種道具和限定卡背。
  Future<void> grantStarterPack() async {
    await _prefs.setBool(_starterPackKey, true);
    await addCoins(starterPackCoins);
    for (final type in ItemType.values) {
      await addItem(type, starterPackItemsEach);
    }
    await _grantSkin(starterPackSkinId);
  }

  /// 換手機後恢復購買：只拿回限定卡背和「買過了」的紀錄。
  Future<void> restoreStarterPack() async {
    await _prefs.setBool(_starterPackKey, true);
    await _grantSkin(starterPackSkinId);
  }

  // ---------- 每日挑戰 ----------

  /// 今天的每日挑戰用的亂數種子：同一天每個人都一樣（例如 20261120）。
  int get dailyChallengeSeed {
    final now = _clock();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  /// 今天每日挑戰的最高分（換日歸零）。
  int get dailyChallengeBest => todayCount('challenge_best');

  /// 今天玩過每日挑戰了沒。每日挑戰一天只能玩一次，開始就算玩過（中途離開、關掉 App 都不能重來）。
  bool get dailyChallengePlayed => todayCount('challenge_played') > 0;

  /// 今天的特殊規則。
  DailyRule get dailyRule => dailyRuleFor(_clock());

  /// 目前連續挑戰幾天（今天或昨天有玩才算連續，斷掉是 0）。
  int get dailyStreak {
    final last = _prefs.getString(_challengeLastKey);
    if (last != _today && last != _yesterday) return 0;
    return _prefs.getInt(_challengeStreakKey) ?? 0;
  }

  /// 最長連續挑戰天數（成就用，斷掉也不會變少）。
  int get dailyBestStreak => _prefs.getInt(_challengeBestStreakKey) ?? 0;

  String get _yesterday {
    final now = _clock();
    return _dateKey(DateTime(now.year, now.month, now.day - 1));
  }

  /// 開始今天的每日挑戰：記下今天玩過，連續天數 +1（昨天沒玩就從 1 開始）。
  Future<void> startDailyChallenge() async {
    if (dailyChallengePlayed) return;
    await bumpToday('challenge_played');
    _bumpDaily('challenge');
    final streak = dailyStreak + 1;
    await _prefs.setString(_challengeLastKey, _today);
    await _prefs.setInt(_challengeStreakKey, streak);
    if (streak > dailyBestStreak) await _prefs.setInt(_challengeBestStreakKey, streak);
  }

  /// 記錄每日挑戰的分數，回傳原本今天的最高分。
  Future<int> recordDailyChallenge(int score) async {
    final before = dailyChallengeBest;
    if (score > before) await _prefs.setString('daily_ad_challenge_best', '$_today|$score');
    return before;
  }

  // ---------- 每天看廣告的次數 ----------

  /// 今天做了幾次（名稱前面加 daily_ad_，重置進度會清掉）。存成「日期|次數」，換日自動歸零。
  int todayCount(String name) {
    final saved = _prefs.getString('daily_ad_$name');
    if (saved == null) return 0;
    final parts = saved.split('|');
    return parts[0] == _today ? int.parse(parts[1]) : 0;
  }

  Future<void> bumpToday(String name) => _prefs.setString('daily_ad_$name', '$_today|${todayCount(name) + 1}');

  /// 夜市轉盤：今天的免費轉還沒用。
  bool get wheelFreeAvailable => todayCount('wheel_free') == 0;

  /// 夜市轉盤：今天還能看廣告轉幾次。
  int get wheelAdSpinsLeft => max(0, wheelAdSpinsPerDay - todayCount('wheel_ad'));

  /// 轉盤停下來後發獎（[byAd] 是看廣告轉的）。
  Future<void> claimWheel(int index, {required bool byAd}) async {
    await bumpToday(byAd ? 'wheel_ad' : 'wheel_free');
    _bumpDaily('wheel');
    final prize = wheelPrizes[index];
    if (prize.coins > 0) await addCoins(prize.coins);
    if (prize.item != null) await addItem(prize.item!);
  }

  /// 商店：今天還能看廣告領幾次金幣。
  int get shopAdCoinsLeft => max(0, shopAdCoinsPerDay - todayCount('shop_coins'));

  /// 商店看完廣告：領金幣，回傳領到的數量；今天次數用完回傳 0。
  Future<int> claimShopAdCoins() async {
    if (shopAdCoinsLeft == 0) return 0;
    await bumpToday('shop_coins');
    await addCoins(shopAdCoins);
    return shopAdCoins;
  }

  // ---------- 夜市月卡 ----------

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// 月卡最後一天（含）；沒買過是 null。
  DateTime? get _monthCardEnd {
    final s = _prefs.getString(_monthCardEndKey);
    return s == null ? null : DateTime.parse('${s}T00:00:00Z');
  }

  /// 月卡還剩幾天（含今天）；沒有月卡或過期是 0。
  int get monthCardDaysLeft {
    final end = _monthCardEnd;
    if (end == null) return 0;
    return max(0, end.difference(_day(_clock())).inDays + 1);
  }

  bool get monthCardActive => monthCardDaysLeft > 0;

  /// 剩不到 [monthCardDays] 天才能再買，最多預先囤兩期，也避免不小心連買好幾張。
  bool get canBuyMonthCard => monthCardDaysLeft <= monthCardDays;

  bool get canClaimMonthCard => monthCardActive && _prefs.getString(_monthCardClaimedKey) != _today;

  /// 付款成功後呼叫：天數接在目前的月卡後面（過期就從今天算），並給立即金幣。
  Future<void> activateMonthCard() async {
    final today = _day(_clock());
    final start = monthCardActive ? _monthCardEnd!.add(const Duration(days: 1)) : today;
    final end = start.add(const Duration(days: monthCardDays - 1));
    await _prefs.setString(_monthCardEndKey, _dateKey(end));
    await addCoins(monthCardInstantCoins);
  }

  /// 領今天的月卡金幣，回傳領到的數量；今天領過或沒有月卡回傳 0。
  Future<int> claimMonthCard() async {
    if (!canClaimMonthCard) return 0;
    await _prefs.setString(_monthCardClaimedKey, _today);
    await addCoins(monthCardDailyCoins);
    return monthCardDailyCoins;
  }

  // ---------- 重置 ----------

  /// 重置遊戲進度。保留音樂／音效設定，以及用真錢買的「移除廣告」、月卡和新手禮包的卡背。
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
    // 新手禮包是真錢買的，限定卡背保留
    if (starterPackBought) await _grantSkin(starterPackSkinId);
  }
}
