import 'dart:math';

import 'items.dart';
import 'night_market_data.dart';

/// 一局夜市翻牌的純邏輯，不含任何畫面，方便寫單元測試。
class MatchingGame {
  MatchingGame({
    required this.level,
    List<Food> pool = foods,
    Random? random,
    this.bonusSeconds = 0,
    this.comboCap = defaultComboCap,
    this.coinMultiplier = 1,
  })  : _pool = pool,
        _random = random ?? Random() {
    reset();
  }

  static const pointsPerMatch = 100;
  static const defaultComboCap = 5;
  static const bonusPerSecond = 10;
  static const hourglassSeconds = 10;
  static const luckyCatMultiplier = 1.5;

  final Level level;

  /// 裝備「老闆的帽子」多出來的秒數。
  final int bonusSeconds;

  /// 裝備「攤車」提高後的連擊上限。
  final int comboCap;

  /// 裝備「算盤」的金幣倍率。
  final double coinMultiplier;

  final List<Food> _pool;
  final Random _random;

  late List<Food> cards;
  late List<bool> isOpen;
  late List<bool> isMatched;

  int? firstPickedIndex;
  int? secondPickedIndex;
  int steps = 0;
  int score = 0;
  int combo = 1;
  int timeLeft = 0;
  int timeBonus = 0;
  bool isEnded = false;
  bool isWon = false;

  /// 看廣告「偷看全部」：每局一次，偷看期間不能翻牌。
  bool hintUsed = false;
  bool isPeeking = false;

  /// 開局翻開全部牌讓玩家記位置，這段時間不能翻牌、不倒數、不能偷看。
  bool isPreviewing = false;

  /// 看廣告「+15 秒繼續」：每局一次。
  bool revived = false;
  static const reviveSeconds = 15;

  /// 這一局翻錯的次數（零失誤成就用）。
  int mistakes = 0;

  /// 這一局達到的最高連擊。
  int bestCombo = 0;

  /// 這一局用過的道具，每種限用一次。
  Set<ItemType> usedItems = {};

  /// 護身符生效中：下一次翻錯不中斷連擊。
  bool charmActive = false;

  /// 招財貓生效中：這一局金幣 ×1.5。
  bool luckyCatActive = false;

  /// 最近一次配對成功的小吃與得分，給畫面顯示提示。
  Food? lastMatched;

  /// 最近一次配對成功的兩張牌（畫面放特效用）。
  List<int> lastMatchedCards = const [];
  int lastPoints = 0;
  int lastCombo = 1;

  /// 兩張翻錯、等待蓋回去的期間為 true，這段時間不能再翻牌。
  bool get isLocked => secondPickedIndex != null || isPeeking || isPreviewing;

  bool get canPeek => !hintUsed && !isEnded && !isPreviewing;
  bool get canRevive => isEnded && !isWon && !revived;

  int get matchedPairs => isMatched.where((m) => m).length ~/ 2;
  int get pairsLeft => level.pairs - matchedPairs;

  int get totalSeconds => level.seconds + bonusSeconds;

  /// 過關星數：剩餘時間超過一半 3 星、超過 1/4 兩星，其餘 1 星。
  int get stars {
    if (!isWon) return 0;
    final ratio = timeLeft / totalSeconds;
    if (ratio > 0.5) return 3;
    if (ratio > 0.25) return 2;
    return 1;
  }

  int get coinsEarned {
    if (!isWon) return 0;
    return (score / 10 * coinMultiplier * (luckyCatActive ? luckyCatMultiplier : 1)).round();
  }

  void reset() {
    final picks = (_pool.toList()..shuffle(_random)).take(level.pairs).toList();
    cards = [...picks, ...picks]..shuffle(_random);
    isOpen = List.filled(cards.length, false);
    isMatched = List.filled(cards.length, false);
    firstPickedIndex = null;
    secondPickedIndex = null;
    steps = 0;
    score = 0;
    combo = 1;
    timeLeft = totalSeconds;
    timeBonus = 0;
    isEnded = false;
    isWon = false;
    hintUsed = false;
    isPeeking = false;
    isPreviewing = false;
    revived = false;
    mistakes = 0;
    bestCombo = 0;
    usedItems = {};
    charmActive = false;
    luckyCatActive = false;
    lastMatched = null;
    lastMatchedCards = const [];
    lastPoints = 0;
    lastCombo = 1;
  }

  PickResult pick(int index) {
    if (isEnded || isLocked || isOpen[index]) return PickResult.ignored;

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
    if (charmActive) {
      charmActive = false; // 護身符擋下這次翻錯，連擊不中斷
    } else {
      combo = 1;
    }
    return PickResult.mismatched;
  }

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

    if (pairsLeft == 0) {
      isEnded = true;
      isWon = true;
      timeBonus = timeLeft * bonusPerSecond;
      score += timeBonus;
      return PickResult.finished;
    }
    return PickResult.matched;
  }

  bool canUseItem(ItemType type) {
    if (isEnded || usedItems.contains(type)) return false;
    return type != ItemType.magnifier || !isLocked;
  }

  /// 使用道具。不能用時回傳 false。放大鏡用完要看 [isWon] 判斷是否過關。
  bool useItem(ItemType type) {
    if (!canUseItem(type)) return false;
    usedItems.add(type);
    switch (type) {
      case ItemType.magnifier:
        // 已經翻開一張就配那一張，否則配第一組還沒配對的牌
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

  /// 開局翻開全部牌讓玩家記位置，倒數結束畫面呼叫 [endPreview] 蓋回去。不會用掉偷看的機會。
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

  /// 每秒呼叫一次。時間到回傳 true。
  bool tick() {
    if (isEnded || isPreviewing) return false;
    timeLeft = max(0, timeLeft - 1);
    if (timeLeft == 0) {
      isEnded = true;
      return true;
    }
    return false;
  }
}

enum PickResult { ignored, firstPicked, matched, mismatched, finished }
