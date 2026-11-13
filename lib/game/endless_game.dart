import 'dart:math';

import 'items.dart';
import 'matching_game.dart' show MatchingGame, PickResult;
import 'night_market_data.dart';

/// 「夜市大胃王」無盡模式的純邏輯：一桌一桌清，清完一桌拿清桌獎勵、發下一桌，一直吃到時間用完，比最高分。
///
/// - 配對成功的牌消掉，位置空著，不補牌。
/// - 整桌清空時加清桌獎勵（[clearBonusFor]）和 [clearBonusSeconds] 秒，並暫停計時，
///   畫面放完清桌動畫後呼叫 [nextTable] 發下一桌。
/// - 越後面的桌牌越多（[cardsForTable]），最多 16 張。
class EndlessGame {
  EndlessGame({
    List<Food> pool = foods,
    Random? random,
    this.bonusSeconds = 0,
    this.comboCap = MatchingGame.defaultComboCap,
    this.coinMultiplier = 1,
    this.comboKeepOnMiss = false,
    this.firstMissForgiven = false,
    this.clearBonusMultiplier = 1,
    this.bossHintCooldown = bossHintCooldownMatches,
  })  : assert(pool.length >= maxCards ~/ 2, '小吃種類至少要 ${maxCards ~/ 2} 種'),
        _pool = pool,
        _random = random ?? Random() {
    reset();
  }

  static const pointsPerMatch = 100;
  static const startSeconds = 60;
  static const reviveSeconds = 15;
  static const hourglassSeconds = 10;
  static const luckyCatMultiplier = 1.5;

  /// 每一桌最多幾張牌。
  static const maxCards = 16;

  /// 清桌獎勵：每一桌 [clearBonusPerTable] × 第幾桌，再加 [clearBonusSeconds] 秒。
  static const clearBonusPerTable = 500;
  static const clearBonusSeconds = 5;

  /// 連續翻錯幾次就給老闆提示。
  static const bossHintAfterMisses = 2;

  /// 老闆提示後至少要再配對幾組才會再提示，避免故意亂翻拿答案。
  static const bossHintCooldownMatches = 3;

  /// 每多少分換 1 枚金幣。大胃王以挑戰高分為主，金幣給得少（100000 分約 500 枚），
  /// 想賺金幣主要靠夜市走透透。
  static const scorePerCoin = 200;

  /// 第幾桌有幾張牌：第 1～2 桌 2×2、第 3～5 桌 3×2、第 6～9 桌 4×2、第 10 桌起 4×4。
  static int cardsForTable(int table) {
    if (table <= 2) return 4;
    if (table <= 5) return 6;
    if (table <= 9) return 8;
    return maxCards;
  }

  /// 第幾桌排成幾欄。
  static int columnsForTable(int table) => switch (cardsForTable(table)) {
        4 => 2,
        6 => 3,
        _ => 4,
      };

  static int clearBonusFor(int table) => clearBonusPerTable * table;

  /// 配對成功會加幾秒：前 20 組 +3 秒，第 21～50 組 +2 秒，之後 +1 秒。
  static int timeGainFor(int matchesSoFar) {
    if (matchesSoFar < 20) return 3;
    if (matchesSoFar < 50) return 2;
    return 1;
  }

  /// 裝備「老闆的帽子」多出來的秒數，起始時間和時間上限都會加。
  final int bonusSeconds;

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

  /// 裝備「大胃王背包」：清桌獎勵倍率。
  final double clearBonusMultiplier;

  /// 老闆提示的冷卻組數（裝備「老闆的人情」會減少），至少 1 組。
  final int bossHintCooldown;

  final List<Food> _pool;
  final Random _random;

  /// 第幾桌（從 1 開始）。
  int table = 1;

  late List<Food> cards;
  late List<bool> isOpen;

  /// 已配對（消掉）的格子，位置空著。
  late List<bool> isMatched;

  /// 這一桌清空了，等畫面放完清桌動畫呼叫 [nextTable]。這段時間不能翻牌、不倒數。
  bool tableCleared = false;

  /// 連續翻錯幾次，配對成功就歸零。
  int consecutiveMisses = 0;

  /// 上次老闆提示之後配對了幾組，用來算冷卻。
  int matchesSinceBossHint = 0;

  int? firstPickedIndex;
  int? secondPickedIndex;
  int steps = 0;
  int score = 0;
  int combo = 1;

  /// 這一局配對成功的組數。
  int matches = 0;

  /// 這一局清了幾桌。
  int tablesCleared = 0;
  int timeLeft = 0;
  bool isEnded = false;

  /// 看廣告「偷看全部」：每局一次，偷看期間不能翻牌。
  bool hintUsed = false;
  bool isPeeking = false;

  /// 每一桌開始時翻開全部牌讓玩家記位置，這段時間不能翻牌、不倒數、不能偷看。
  bool isPreviewing = false;

  /// 看廣告「+15 秒繼續」：每局一次。
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

  /// 最近一次配對成功的小吃、兩張牌、得分與加的秒數，給畫面顯示提示和特效。
  Food? lastMatched;
  List<int> lastMatchedCards = const [];
  int lastPoints = 0;
  int lastCombo = 1;
  int lastTimeGain = 0;

  /// 最近一次清桌拿到的分數。
  int lastClearBonus = 0;

  int get boardSize => cards.length;
  int get columns => columnsForTable(table);

  /// 翻錯等待蓋回去、偷看、翻牌記憶、清桌動畫期間不能翻牌。
  bool get isLocked => secondPickedIndex != null || isPeeking || isPreviewing || tableCleared;

  bool get canPeek => !hintUsed && !isEnded && !isPreviewing && !tableCleared;
  bool get canRevive => isEnded && !revived;

  /// 時間上限。配對、清桌加的秒數不會超過這個值（沙漏可以超過）。
  int get maxSeconds => startSeconds + bonusSeconds;

  /// 下一次配對成功會加幾秒。
  int get nextTimeGain => timeGainFor(matches);

  /// 這一桌還剩幾組沒配。
  int get pairsLeft => isMatched.where((m) => !m).length ~/ 2;

  /// 結算金幣：遊戲結束後才有。
  int get coinsEarned {
    if (!isEnded) return 0;
    return (score / scorePerCoin * coinMultiplier * (luckyCatActive ? luckyCatMultiplier : 1)).round();
  }

  void reset() {
    table = 1;
    _dealTable();
    consecutiveMisses = 0;
    matchesSinceBossHint = bossHintCooldown; // 第一次不用等冷卻
    steps = 0;
    score = 0;
    combo = 1;
    matches = 0;
    tablesCleared = 0;
    timeLeft = maxSeconds;
    isEnded = false;
    hintUsed = false;
    isPeeking = false;
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
    lastTimeGain = 0;
    lastClearBonus = 0;
  }

  /// 依目前的 [table] 發一桌全新的牌，全部成對。
  void _dealTable() {
    final picks = (_pool.toList()..shuffle(_random)).take(cardsForTable(table) ~/ 2).toList();
    cards = [...picks, ...picks]..shuffle(_random);
    isOpen = List.filled(cards.length, false);
    isMatched = List.filled(cards.length, false);
    firstPickedIndex = null;
    secondPickedIndex = null;
    isPreviewing = false;
    isPeeking = false;
    tableCleared = false;
  }

  /// 清桌動畫放完後呼叫：發下一桌，計時繼續（畫面會先翻牌讓玩家記）。
  void nextTable() {
    if (!tableCleared) return;
    table++;
    _dealTable();
  }

  PickResult pick(int index) {
    if (isEnded || isLocked || isMatched[index] || isOpen[index]) return PickResult.ignored;

    isOpen[index] = true;
    steps++;

    final first = firstPickedIndex;
    if (first == null) {
      firstPickedIndex = index;
      return PickResult.firstPicked;
    }

    if (cards[first] == cards[index]) {
      return _match(first, index);
    }

    secondPickedIndex = index;
    mistakes++;
    consecutiveMisses++;
    if (charmActive) {
      charmActive = false; // 護身符擋下這次翻錯，連擊不中斷
    } else if (firstMissForgiven && !firstMissUsed) {
      firstMissUsed = true; // 保溫便當袋 Lv.2：每局第一次翻錯不扣連擊
    } else if (comboKeepOnMiss) {
      combo = max(1, combo - 1); // 保溫便當袋：連擊只少 1 段
    } else {
      combo = 1;
    }
    return PickResult.mismatched;
  }

  /// 配對成功；最後一組時清桌並回傳 [PickResult.finished]。
  PickResult _match(int a, int b) {
    isOpen[a] = true;
    isOpen[b] = true;
    isMatched[a] = true;
    isMatched[b] = true;
    firstPickedIndex = null;
    lastMatched = cards[b];
    lastMatchedCards = [a, b];
    lastCombo = combo;
    bestCombo = max(bestCombo, combo);
    lastPoints = pointsPerMatch * combo;
    score += lastPoints;
    combo = min(combo + 1, comboCap);

    lastTimeGain = nextTimeGain;
    _addTime(lastTimeGain);
    matches++;
    consecutiveMisses = 0;
    matchesSinceBossHint++;

    if (pairsLeft > 0) return PickResult.matched;
    tableCleared = true;
    tablesCleared++;
    lastClearBonus = (clearBonusFor(table) * clearBonusMultiplier).round();
    score += lastClearBonus;
    _addTime(clearBonusSeconds);
    return PickResult.finished;
  }

  /// 加秒數不超過上限，但沙漏加超過上限的時間也不會被扣回去。
  void _addTime(int seconds) => timeLeft = max(timeLeft, min(maxSeconds, timeLeft + seconds));

  bool canUseItem(ItemType type) {
    if (isEnded || usedItems.contains(type)) return false;
    return type != ItemType.magnifier || !isLocked;
  }

  /// 使用道具。不能用時回傳 false。放大鏡配到最後一組時會清桌，要看 [tableCleared]。
  bool useItem(ItemType type) {
    if (!canUseItem(type)) return false;
    usedItems.add(type);
    switch (type) {
      case ItemType.magnifier:
        // 已經翻開一張就配那一張，否則配第一組還沒配對的牌（每一桌都是成對的，一定找得到）
        final a = firstPickedIndex ?? isMatched.indexOf(false);
        final b = List.generate(cards.length, (i) => i)
            .firstWhere((i) => i != a && !isMatched[i] && cards[i] == cards[a]);
        _match(a, b);
      case ItemType.hourglass:
        timeLeft += hourglassSeconds;
      case ItemType.charm:
        charmActive = true;
      case ItemType.luckyCat:
        luckyCatActive = true;
    }
    return true;
  }

  /// 翻錯後把兩張牌蓋回去（畫面會在延遲後呼叫）。
  void hideMismatched() {
    final first = firstPickedIndex;
    final second = secondPickedIndex;
    if (first == null || second == null) return;
    isOpen[first] = false;
    isOpen[second] = false;
    firstPickedIndex = null;
    secondPickedIndex = null;
  }

  /// 每一桌開始時翻開全部牌讓玩家記位置，倒數結束畫面呼叫 [endPreview] 蓋回去。不會用掉偷看的機會。
  void startPreview() => isPreviewing = true;

  void endPreview() => isPreviewing = false;

  /// 開始偷看：先把翻錯等待中的牌蓋回去，再讓畫面顯示全部牌面。
  bool startPeek() {
    if (!canPeek) return false;
    hideMismatched();
    hintUsed = true;
    isPeeking = true;
    return true;
  }

  void endPeek() => isPeeking = false;

  /// 連續翻錯 [bossHintAfterMisses] 次、而且過了冷卻，就挑桌上一組對子告訴玩家（畫面在翻錯的牌蓋回去後呼叫）。
  /// 回傳那兩張牌的位置；不符合條件回傳 null。
  List<int>? takeBossHint() {
    if (isEnded || isLocked) return null;
    if (consecutiveMisses < bossHintAfterMisses || matchesSinceBossHint < max(1, bossHintCooldown)) return null;
    final pairs = <List<int>>[];
    for (var a = 0; a < boardSize; a++) {
      if (isMatched[a] || isOpen[a]) continue;
      for (var b = a + 1; b < boardSize; b++) {
        if (!isMatched[b] && !isOpen[b] && cards[a] == cards[b]) pairs.add([a, b]);
      }
    }
    if (pairs.isEmpty) return null;
    // 不用 _random 挑，免得打亂之後發牌的結果；用配對和翻錯次數輪流挑，每次提示的位置不一樣
    final hint = pairs[(matches + mistakes) % pairs.length];
    consecutiveMisses = 0;
    matchesSinceBossHint = 0;
    return hint;
  }

  /// 畫面要不要顯示這張牌的正面。
  bool isFaceUp(int index) => isPeeking || isPreviewing || isOpen[index];

  /// 時間到之後看廣告，多給 15 秒繼續。
  bool revive() {
    if (!canRevive) return false;
    revived = true;
    isEnded = false;
    timeLeft = reviveSeconds;
    hideMismatched();
    return true;
  }

  /// 每秒呼叫一次。時間到回傳 true。翻牌記憶、清桌動畫期間不倒數。
  bool tick() {
    if (isEnded || isPreviewing || tableCleared) return false;
    timeLeft = max(0, timeLeft - 1);
    if (timeLeft == 0) {
      isEnded = true;
      return true;
    }
    return false;
  }
}
