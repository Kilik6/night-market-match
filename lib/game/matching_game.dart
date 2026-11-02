import 'dart:math';

import 'night_market_data.dart';

/// 一局夜市翻牌的純邏輯，不含任何畫面，方便寫單元測試。
class MatchingGame {
  MatchingGame({required this.level, List<Food> pool = foods, Random? random})
      : _pool = pool,
        _random = random ?? Random() {
    reset();
  }

  static const pointsPerMatch = 100;
  static const maxCombo = 5;
  static const bonusPerSecond = 10;

  final Level level;
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

  /// 看廣告「+15 秒繼續」：每局一次。
  bool revived = false;
  static const reviveSeconds = 15;

  /// 最近一次配對成功的小吃與得分，給畫面顯示提示。
  Food? lastMatched;
  int lastPoints = 0;
  int lastCombo = 1;

  /// 兩張翻錯、等待蓋回去的期間為 true，這段時間不能再翻牌。
  bool get isLocked => secondPickedIndex != null || isPeeking;

  bool get canPeek => !hintUsed && !isEnded;
  bool get canRevive => isEnded && !isWon && !revived;

  int get matchedPairs => isMatched.where((m) => m).length ~/ 2;
  int get pairsLeft => level.pairs - matchedPairs;

  /// 過關星數：剩餘時間超過一半 3 星、超過 1/4 兩星，其餘 1 星。
  int get stars {
    if (!isWon) return 0;
    final ratio = timeLeft / level.seconds;
    if (ratio > 0.5) return 3;
    if (ratio > 0.25) return 2;
    return 1;
  }

  int get coinsEarned => isWon ? (score / 10).round() : 0;

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
    timeLeft = level.seconds;
    timeBonus = 0;
    isEnded = false;
    isWon = false;
    hintUsed = false;
    isPeeking = false;
    revived = false;
    lastMatched = null;
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
      isMatched[first] = true;
      isMatched[index] = true;
      firstPickedIndex = null;
      lastMatched = cards[index];
      lastCombo = combo;
      lastPoints = pointsPerMatch * combo;
      score += lastPoints;
      combo = min(combo + 1, maxCombo);

      if (pairsLeft == 0) {
        isEnded = true;
        isWon = true;
        timeBonus = timeLeft * bonusPerSecond;
        score += timeBonus;
        return PickResult.finished;
      }
      return PickResult.matched;
    }

    secondPickedIndex = index;
    combo = 1;
    return PickResult.mismatched;
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
  bool isFaceUp(int index) => isPeeking || isOpen[index];

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
    if (isEnded) return false;
    timeLeft = max(0, timeLeft - 1);
    if (timeLeft == 0) {
      isEnded = true;
      return true;
    }
    return false;
  }
}

enum PickResult { ignored, firstPicked, matched, mismatched, finished }
