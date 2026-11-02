import 'dart:math';

/// 翻牌遊戲的純邏輯，不含任何畫面，方便寫單元測試。
/// 對應 React Native 版 App.tsx 裡的 state 與 cardPressHandler / calculateGameResult。
class MatchingGame {
  MatchingGame({List<String>? symbols, Random? random})
      : symbols = symbols ?? defaultSymbols,
        _random = random ?? Random() {
    reset();
  }

  static const defaultSymbols = ['😡', '😛', '😍', '🥶', '😈', '💀', '🐥', '🍎'];

  final List<String> symbols;
  final Random _random;

  /// 洗好的牌（每個符號兩張）。
  late List<String> cards;

  /// 每張牌是否翻開。
  late List<bool> isOpen;

  int? firstPickedIndex;
  int? secondPickedIndex;
  int steps = 0;
  bool isEnded = false;

  /// 兩張翻錯、等待蓋回去的期間為 true，這段時間不能再翻牌。
  /// （修正 RN 版：等待期間點牌，牌不會翻開但步數照樣增加）
  bool get isLocked => secondPickedIndex != null;

  void reset() {
    cards = [...symbols, ...symbols]..shuffle(_random);
    isOpen = List.filled(cards.length, false);
    firstPickedIndex = null;
    secondPickedIndex = null;
    steps = 0;
    isEnded = false;
  }

  /// 翻開一張牌。回傳結果讓畫面決定要不要延遲蓋牌。
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
      firstPickedIndex = null;
      if (isOpen.every((open) => open)) isEnded = true;
      return isEnded ? PickResult.finished : PickResult.matched;
    }

    secondPickedIndex = index;
    return PickResult.mismatched;
  }

  /// 翻錯後把兩張牌蓋回去（畫面會在 1 秒後呼叫）。
  void hideMismatched() {
    final first = firstPickedIndex;
    final second = secondPickedIndex;
    if (first == null || second == null) return;
    isOpen[first] = false;
    isOpen[second] = false;
    firstPickedIndex = null;
    secondPickedIndex = null;
  }
}

enum PickResult { ignored, firstPicked, matched, mismatched, finished }
