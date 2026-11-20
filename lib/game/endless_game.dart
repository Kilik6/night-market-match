import 'dart:math';

import 'items.dart';
import 'matching_game.dart' show MatchingGame, PickResult;
import 'night_market_data.dart';

/// 「夜市大胃王」無盡模式的純邏輯：沒有時間限制，老闆一直上菜，桌子塞滿就收攤，比最高分。
///
/// - 桌子固定 [columns]×[rows] = [capacity] 格，開局先上一組並翻開讓玩家記。
/// - 老闆一直上菜：每翻一次牌（兩張）累積 [serveRate] 組，滿一組就蓋著上桌；每吃一組，上菜就再快一點。
/// - 每翻錯 [missesPerPenalty] 次，老闆多加一組菜。
/// - 要上菜但桌子已經塞滿，遊戲結束（可以看廣告「吃胃藥」收掉幾組繼續，每輪一次）。
/// - 連續配對拿連擊；連續配對 [feverAt] 組進入「大胃王時間」，接下來 [feverMatches] 組分數 ×[feverMultiplier]。
/// - 把桌上全部吃光拿獎勵（[allClearBonusFor]），下一波一次上好幾組並翻開讓玩家記。
class EndlessGame {
  EndlessGame({
    List<Food> pool = foods,
    Random? random,
    this.comboCap = MatchingGame.defaultComboCap,
    this.coinMultiplier = 1,
    this.comboKeepOnMiss = false,
    this.firstMissForgiven = false,
    this.clearBonusMultiplier = 1,
    this.bossHintCooldown = bossHintCooldownMatches,
    this.turnLimit,
    this.feverThreshold = feverAt,
    this.bossHints = true,
  })  : assert(pool.length >= capacity ~/ 2, '小吃種類至少要 ${capacity ~/ 2} 種，桌上的每一組才會都不一樣'),
        _pool = pool,
        _random = random ?? Random() {
    reset();
  }

  /// 桌子的大小：5 欄 × 4 列，最多 20 張。直式手機上橫向排滿，小螢幕的牌也比較大。
  static const columns = 5;
  static const rows = 4;
  static const capacity = columns * rows;

  static const pointsPerMatch = 100;
  static const luckyCatMultiplier = 1.5;

  /// 上菜速度：一開始每翻一次牌累積 [serveRateStart] 組（約翻 5 次上一組），
  /// 每吃一組再快 [serveRateStep]，最快每翻一次就上一組。
  static const serveRateStart = 0.2;
  static const serveRateStep = 0.003;

  /// 連續配對幾組進入「大胃王時間」。
  static const feverAt = 5;

  /// 「大胃王時間」持續幾組。
  static const feverMatches = 5;
  static const feverMultiplier = 2;

  /// 全部吃光的獎勵：[allClearBonus] × 第幾次吃光。
  static const allClearBonus = 500;

  /// 吃光後下一波最多一次上幾組。
  static const maxWavePairs = 4;

  /// 看廣告「吃胃藥」：收掉桌上幾組牌繼續吃。
  static const reviveRemovePairs = 5;

  /// 每翻錯幾次，老闆多加一組菜（不用連續）。
  static const missesPerPenalty = 3;

  /// 連續翻錯幾次就給老闆提示。
  static const bossHintAfterMisses = 2;

  /// 老闆提示後至少要再配對幾組才會再提示，避免故意亂翻拿答案。
  static const bossHintCooldownMatches = 3;

  /// 每多少分換 1 枚金幣。大胃王以挑戰高分為主，想賺金幣主要靠夜市走透透。
  static const scorePerCoin = 200;

  /// 第幾次吃光拿多少分。
  static int allClearBonusFor(int clears) => allClearBonus * clears;

  /// 第幾波上幾組：第 1 波 1 組、第 2 波 2 組……最多 [maxWavePairs] 組。
  static int pairsForWave(int wave) => min(wave, maxWavePairs);

  /// 裝備「攤車」提高後的連擊上限。
  final int comboCap;

  /// 裝備「算盤」的金幣倍率。
  final double coinMultiplier;

  /// 裝備「保溫便當袋」：翻錯時連擊只少 1 段，不會歸零。
  final bool comboKeepOnMiss;

  /// 裝備「保溫便當袋」Lv.2：每局第一次翻錯不扣連擊。
  final bool firstMissForgiven;

  /// 這一局已經用掉「第一次翻錯不扣」了。
  bool firstMissUsed = false;

  /// 裝備「大胃王背包」：全部吃光的獎勵倍率。
  final double clearBonusMultiplier;

  /// 老闆提示的冷卻組數（裝備「老闆的人情」會減少），至少 1 組。
  final int bossHintCooldown;

  /// 每日挑戰：最多翻幾次（翻兩張算一次），翻完就結束。null 是沒有限制（大胃王）。
  final int? turnLimit;

  /// 連續配對幾組進入大胃王時間（每日挑戰「大胃王日」會降低）。
  final int feverThreshold;

  /// 有沒有老闆提示（每日挑戰「老闆休假日」沒有）。
  final bool bossHints;

  /// 翻了幾次（翻兩張算一次，放大鏡不算）。
  int turns = 0;

  /// 翻牌次數用完而結束（不是桌子塞滿）。
  bool outOfTurns = false;

  /// 還剩幾翻；沒有限制時是 null。
  int? get turnsLeft => turnLimit == null ? null : max(0, turnLimit! - turns);

  final List<Food> _pool;
  final Random _random;

  /// 桌上 [capacity] 格，null 是空位。
  late List<Food?> slots;
  late List<bool> isOpen;

  /// 每一格是第幾次上菜放上去的，畫面用來播「上桌」動畫（同一格換了新菜，編號就會變）。
  late List<int> servedId;
  int _serveCounter = 0;

  /// 第幾波（開局是第 1 波，每吃光一次 +1）。
  int wave = 1;

  /// 這一局吃光了幾次。
  int allClears = 0;

  /// 桌上剛被吃光，等畫面放完慶祝動畫呼叫 [nextWave]。這段時間不能翻牌。
  bool boardCleared = false;

  /// 上菜的進度，滿 1 就上一組。
  double serveProgress = 0;

  /// 上次加菜之後翻錯了幾次，滿 [missesPerPenalty] 次老闆就加一組。
  int missesSincePenalty = 0;

  /// 最近一次翻錯有沒有讓老闆加菜。
  bool lastMissPenalty = false;

  /// 再翻錯幾次老闆就會加菜。
  int get missesUntilPenalty => missesPerPenalty - missesSincePenalty;

  /// 連續翻錯幾次，配對成功就歸零。
  int consecutiveMisses = 0;

  /// 上次老闆提示之後配對了幾組，用來算冷卻。
  int matchesSinceBossHint = 0;

  int? firstPickedIndex;
  int? secondPickedIndex;
  int steps = 0;
  int score = 0;
  int combo = 1;

  /// 大胃王時間以外連續配對了幾組（翻錯歸零），滿 [feverThreshold] 組進入「大胃王時間」。
  int streak = 0;

  /// 「大胃王時間」還剩幾組；0 表示沒有。
  int feverLeft = 0;

  /// 這一局配對成功的組數。
  int matches = 0;
  bool isEnded = false;

  /// 看廣告「偷看全部」：每局一次，偷看期間不能翻牌。
  bool hintUsed = false;
  bool isPeeking = false;

  /// 每一波上菜時翻開全部牌讓玩家記位置，這段時間不能翻牌、不能偷看。
  bool isPreviewing = false;

  /// 看廣告「吃胃藥」：每局一次。
  bool revived = false;

  /// 這一局翻錯的次數。
  int mistakes = 0;

  /// 這一局達到的最高連擊。
  int bestCombo = 0;

  /// 這一局用過的道具，每種限用一次。
  Set<ItemType> usedItems = {};

  /// 護身符生效中：下一次翻錯不中斷連擊。
  bool charmActive = false;

  /// 招財貓生效中：這一局金幣 ×1.5。
  bool luckyCatActive = false;

  /// 最近一次配對成功的小吃、兩張牌、得分，給畫面顯示提示和特效。
  Food? lastMatched;
  List<int> lastMatchedCards = const [];
  int lastPoints = 0;
  int lastCombo = 1;

  /// 最近一次配對是不是在「大胃王時間」裡（分數有加倍）。
  bool lastFever = false;

  /// 最近一次配對剛好開啟「大胃王時間」。
  bool feverJustStarted = false;

  /// 最近一次吃光拿到的分數。
  int lastClearBonus = 0;

  /// 最近一個回合老闆上了幾組菜（翻錯加的也算），給畫面顯示提示。
  int lastServedPairs = 0;

  bool get feverActive => feverLeft > 0;

  /// 桌上有幾張牌。
  int get cardCount => slots.where((f) => f != null).length;

  /// 桌上還有幾組。
  int get pairsLeft => cardCount ~/ 2;

  /// 目前每翻一次牌累積幾組上菜。
  double get serveRate => min(1.0, serveRateStart + matches * serveRateStep);

  /// 再翻幾次牌老闆就會上菜。
  int get turnsUntilServe => max(1, ((1 - serveProgress) / serveRate - 1e-9).ceil());

  /// 翻錯等待蓋回去、偷看、翻牌記憶、吃光的慶祝動畫期間不能翻牌。
  bool get isLocked => secondPickedIndex != null || isPeeking || isPreviewing || boardCleared;

  bool get canPeek => !hintUsed && !isEnded && !isPreviewing && !boardCleared;
  bool get canRevive => isEnded && !revived && !outOfTurns;

  /// 結算金幣：遊戲結束後才有。
  int get coinsEarned {
    if (!isEnded) return 0;
    return (score / scorePerCoin * coinMultiplier * (luckyCatActive ? luckyCatMultiplier : 1)).round();
  }

  void reset() {
    slots = List.filled(capacity, null);
    isOpen = List.filled(capacity, false);
    servedId = List.filled(capacity, 0);
    _serveCounter = 0;
    wave = 1;
    allClears = 0;
    boardCleared = false;
    serveProgress = 0;
    missesSincePenalty = 0;
    lastMissPenalty = false;
    consecutiveMisses = 0;
    matchesSinceBossHint = bossHintCooldown; // 第一次不用等冷卻
    firstPickedIndex = null;
    secondPickedIndex = null;
    steps = 0;
    turns = 0;
    outOfTurns = false;
    score = 0;
    combo = 1;
    streak = 0;
    feverLeft = 0;
    matches = 0;
    isEnded = false;
    hintUsed = false;
    isPeeking = false;
    isPreviewing = false;
    revived = false;
    mistakes = 0;
    bestCombo = 0;
    usedItems = {};
    charmActive = false;
    luckyCatActive = false;
    firstMissUsed = false;
    lastMatched = null;
    lastMatchedCards = const [];
    lastPoints = 0;
    lastCombo = 1;
    lastFever = false;
    feverJustStarted = false;
    lastClearBonus = 0;
    lastServedPairs = 0;
    _serveWave();
  }

  /// 上一波菜：[pairsForWave] 組，畫面會翻開讓玩家記。
  void _serveWave() {
    for (var i = 0; i < pairsForWave(wave); i++) {
      _servePair();
    }
  }

  /// 上一組菜到隨機的兩個空位，挑桌上還沒有的小吃（每一組都不一樣）。沒有兩個空位時回傳 false。
  bool _servePair() {
    final empty = [
      for (var i = 0; i < capacity; i++)
        if (slots[i] == null) i
    ];
    if (empty.length < 2) return false;
    final onTable = slots.whereType<Food>().toSet();
    final choices = _pool.where((f) => !onTable.contains(f)).toList();
    final food = choices[_random.nextInt(choices.length)];
    empty.shuffle(_random);
    _serveCounter++;
    for (final i in empty.take(2)) {
      slots[i] = food;
      isOpen[i] = false;
      servedId[i] = _serveCounter;
    }
    return true;
  }

  /// 吃光的慶祝動畫放完後呼叫：上下一波菜（畫面會先翻開讓玩家記）。
  void nextWave() {
    if (!boardCleared) return;
    boardCleared = false;
    wave++;
    _serveWave();
  }

  /// 一個回合（翻兩張）結束：翻錯滿 [missesPerPenalty] 次多加一組，再依上菜速度上菜。桌子塞滿上不了菜就結束。
  void _endTurn({required bool missed}) {
    lastServedPairs = 0;
    lastMissPenalty = false;
    turns++;
    if (turnLimit != null && turns >= turnLimit!) {
      // 每日挑戰翻完了：最後這一翻照樣算分，不再上菜
      isEnded = true;
      outOfTurns = true;
      return;
    }
    if (boardCleared) return; // 吃光了，等下一波
    var pairs = 0;
    if (missed && ++missesSincePenalty >= missesPerPenalty) {
      missesSincePenalty = 0;
      lastMissPenalty = true;
      pairs++;
    }
    serveProgress += serveRate;
    while (serveProgress >= 1) {
      serveProgress -= 1;
      pairs++;
    }
    for (var i = 0; i < pairs; i++) {
      if (!_servePair()) {
        isEnded = true;
        return;
      }
      lastServedPairs++;
    }
  }

  PickResult pick(int index) {
    if (isEnded || isLocked || slots[index] == null || isOpen[index]) return PickResult.ignored;

    isOpen[index] = true;
    steps++;

    final first = firstPickedIndex;
    if (first == null) {
      firstPickedIndex = index;
      return PickResult.firstPicked;
    }

    if (slots[first] == slots[index]) {
      final result = _match(first, index);
      _endTurn(missed: false);
      return result;
    }

    secondPickedIndex = index;
    mistakes++;
    consecutiveMisses++;
    streak = 0;
    if (charmActive) {
      charmActive = false; // 護身符擋下這次翻錯，連擊和大胃王時間都不中斷
    } else {
      feverLeft = 0;
      if (firstMissForgiven && !firstMissUsed) {
        firstMissUsed = true; // 保溫便當袋 Lv.2：每局第一次翻錯不扣連擊
      } else if (comboKeepOnMiss) {
        combo = max(1, combo - 1); // 保溫便當袋：連擊只少 1 段
      } else {
        combo = 1;
      }
    }
    return PickResult.mismatched;
  }

  /// 配對成功；桌上吃光時回傳 [PickResult.finished]。
  PickResult _match(int a, int b) {
    final food = slots[b]!;
    slots[a] = null;
    slots[b] = null;
    isOpen[a] = false;
    isOpen[b] = false;
    firstPickedIndex = null;
    lastMatched = food;
    lastMatchedCards = [a, b];
    lastCombo = combo;
    bestCombo = max(bestCombo, combo);
    lastFever = feverActive;
    lastPoints = pointsPerMatch * combo * (lastFever ? feverMultiplier : 1);
    score += lastPoints;
    combo = min(combo + 1, comboCap);
    matches++;
    consecutiveMisses = 0;
    matchesSinceBossHint++;

    // 大胃王時間：用完一組少一組；結束後要重新連續配對滿 [feverAt] 組才會再開始
    feverJustStarted = false;
    if (feverActive) {
      feverLeft--;
    } else if (++streak >= feverThreshold) {
      feverLeft = feverMatches;
      feverJustStarted = true;
      streak = 0;
    }

    if (cardCount > 0) return PickResult.matched;
    boardCleared = true;
    allClears++;
    lastClearBonus = (allClearBonusFor(allClears) * clearBonusMultiplier).round();
    score += lastClearBonus;
    return PickResult.finished;
  }

  bool canUseItem(ItemType type) {
    if (isEnded || usedItems.contains(type)) return false;
    return switch (type) {
      ItemType.magnifier => !isLocked,
      ItemType.hourglass => false, // 大胃王沒有時間限制，沙漏留給走透透
      _ => true,
    };
  }

  /// 使用道具。不能用時回傳 false。放大鏡吃到最後一組時會吃光，要看 [boardCleared]。
  bool useItem(ItemType type) {
    if (!canUseItem(type)) return false;
    usedItems.add(type);
    switch (type) {
      case ItemType.magnifier:
        lastServedPairs = 0; // 用道具不算翻牌，老闆不上菜
        // 已經翻開一張就配那一張，否則配第一組（桌上每一組都不一樣，一定找得到另一半）
        final a = firstPickedIndex ?? slots.indexWhere((f) => f != null);
        final b = List.generate(capacity, (i) => i).firstWhere((i) => i != a && slots[i] == slots[a]);
        _match(a, b);
      case ItemType.hourglass:
        break;
      case ItemType.charm:
        charmActive = true;
      case ItemType.luckyCat:
        luckyCatActive = true;
    }
    return true;
  }

  /// 翻錯後把兩張牌蓋回去（畫面會在延遲後呼叫），這時老闆加菜、上菜。
  void hideMismatched() {
    final first = firstPickedIndex;
    final second = secondPickedIndex;
    if (first == null || second == null) return;
    isOpen[first] = false;
    isOpen[second] = false;
    firstPickedIndex = null;
    secondPickedIndex = null;
    _endTurn(missed: true);
  }

  /// 每一波上菜時翻開全部牌讓玩家記位置，倒數結束畫面呼叫 [endPreview] 蓋回去。不會用掉偷看的機會。
  void startPreview() => isPreviewing = true;

  void endPreview() => isPreviewing = false;

  /// 開始偷看：先把翻錯等待中的牌蓋回去，再讓畫面顯示全部牌面。
  bool startPeek() {
    if (!canPeek) return false;
    hideMismatched();
    if (isEnded) return false; // 蓋回去時剛好塞滿
    hintUsed = true;
    isPeeking = true;
    return true;
  }

  void endPeek() => isPeeking = false;

  /// 連續翻錯 [bossHintAfterMisses] 次、而且過了冷卻，就挑桌上一組對子告訴玩家（畫面在翻錯的牌蓋回去後呼叫）。
  /// 回傳那兩張牌的位置；不符合條件回傳 null。
  List<int>? takeBossHint() {
    if (!bossHints || isEnded || isLocked) return null;
    if (consecutiveMisses < bossHintAfterMisses || matchesSinceBossHint < max(1, bossHintCooldown)) return null;
    final pairs = <List<int>>[];
    for (var a = 0; a < capacity; a++) {
      if (slots[a] == null || isOpen[a]) continue;
      for (var b = a + 1; b < capacity; b++) {
        if (slots[b] == slots[a] && !isOpen[b]) pairs.add([a, b]);
      }
    }
    if (pairs.isEmpty) return null;
    // 不用 _random 挑，免得打亂之後上菜的結果；用配對和翻錯次數輪流挑，每次提示的位置不一樣
    final hint = pairs[(matches + mistakes) % pairs.length];
    consecutiveMisses = 0;
    matchesSinceBossHint = 0;
    return hint;
  }

  /// 畫面要不要顯示這張牌的正面。
  bool isFaceUp(int index) => slots[index] != null && (isPeeking || isPreviewing || isOpen[index]);

  /// 桌子塞滿之後看廣告「吃胃藥」：收掉 [reviveRemovePairs] 組，上菜進度歸零，繼續吃。
  bool revive() {
    if (!canRevive) return false;
    revived = true;
    isEnded = false;
    firstPickedIndex = null;
    secondPickedIndex = null;
    for (var i = 0; i < capacity; i++) {
      isOpen[i] = false;
    }
    final onTable = slots.whereType<Food>().toSet().toList()..shuffle(_random);
    for (final food in onTable.take(reviveRemovePairs)) {
      for (var i = 0; i < capacity; i++) {
        if (slots[i] == food) slots[i] = null;
      }
    }
    serveProgress = 0;
    return true;
  }
}
