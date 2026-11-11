import 'dart:math';

import 'items.dart';
import 'matching_game.dart' show MatchingGame, PickResult;
import 'night_market_data.dart';

/// 「夜市大胃王」無盡模式的純邏輯：配對成功的兩張牌消掉後補上新牌，一直玩到時間用完，比最高分。
///
/// 補牌規則（防止玩家鑽漏洞、也不會卡死）：
/// - 同一批補上的牌，彼此一定不是一對。否則玩家看到哪兩格剛補牌，就知道它們是一對。
/// - 桌上隨時至少有 [minPairsOnBoard] 組完整的對子，不會出現每張都落單、怎麼翻都配不到的死局。
/// - 同一種小吃在桌上最多兩張。
/// - 補上的牌可能是桌上落單牌的另一半，也可能是新的小吃（它的另一半之後才會出現），
///   所以玩家要一直記住還沒配到的牌。
///
/// 配對成功的牌先留在桌上（[isMatched]）讓畫面放特效，畫面要呼叫 [refill] 才會補新牌，
/// 做法和翻錯後由畫面呼叫 [hideMismatched] 一樣。
class EndlessGame {
  EndlessGame({
    List<Food> pool = foods,
    Random? random,
    this.boardSize = 16,
    this.bonusSeconds = 0,
    this.comboCap = MatchingGame.defaultComboCap,
    this.coinMultiplier = 1,
  })  : assert(boardSize.isEven),
        assert(boardSize ~/ 2 + 2 <= startKinds, '開局的小吃種類要比棋盤一半多 2 種，補牌才一定有新小吃可放'),
        assert(pool.length >= startKinds, '小吃種類至少要 $startKinds 種'),
        _pool = pool,
        _random = random ?? Random() {
    reset();
  }

  static const pointsPerMatch = 100;
  static const startSeconds = 60;
  static const reviveSeconds = 15;
  static const hourglassSeconds = 10;
  static const luckyCatMultiplier = 1.5;

  /// 桌上至少要有幾組完整的對子。
  static const minPairsOnBoard = 2;

  /// 一開始用幾種小吃。至少要比棋盤一半多 2 種，補牌時才一定有新小吃可以放。
  static const startKinds = 10;

  /// 每配對幾組，多加一種小吃。
  static const matchesPerNewKind = 8;

  /// 桌上落單牌的目標數量上限。
  static const maxTargetSingles = 6;

  /// 連續翻錯幾次就給老闆提示。
  static const bossHintAfterMisses = 2;

  /// 老闆提示後至少要再配對幾組才會再提示，避免故意亂翻拿答案。
  static const bossHintCooldownMatches = 3;

  /// 補牌時有這個機率不照目標走，讓補牌不會太好預測。
  static const surpriseChance = 0.2;

  /// 棋盤張數。
  final int boardSize;

  /// 裝備「老闆的帽子」多出來的秒數，起始時間和時間上限都會加。
  final int bonusSeconds;

  /// 裝備「攤車」提高後的連擊上限。
  final int comboCap;

  /// 裝備「算盤」的金幣倍率。
  final double coinMultiplier;

  final List<Food> _pool;
  final Random _random;

  /// 這一局小吃出場的順序，前 [activeKinds] 種是目前會出現的。
  late List<Food> _kindOrder;

  late List<Food> cards;
  late List<bool> isOpen;

  /// 已配對、等待 [refill] 補新牌的格子。
  late List<bool> isMatched;

  /// 這張牌玩家看過了沒（翻過、開局翻牌、偷看、老闆提示都算）。沒看過的牌卡背會標「新」。
  late List<bool> isSeen;

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
  int timeLeft = 0;
  bool isEnded = false;

  /// 看廣告「偷看全部」：每局一次，偷看期間不能翻牌。
  bool hintUsed = false;
  bool isPeeking = false;

  /// 開局翻開全部牌讓玩家記位置，這段時間不能翻牌、不倒數、不能偷看。
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

  /// 最近一次 [refill] 補上新牌的格子（畫面放發牌動畫用）。
  List<int> lastRefilled = const [];

  /// 兩張翻錯、等待蓋回去的期間為 true，這段時間不能再翻牌。
  bool get isLocked => secondPickedIndex != null || isPeeking || isPreviewing;

  bool get canPeek => !hintUsed && !isEnded && !isPreviewing;
  bool get canRevive => isEnded && !revived;

  /// 時間上限。配對加秒數不會超過這個值（沙漏可以超過）。
  int get maxSeconds => startSeconds + bonusSeconds;

  /// 目前會出現幾種小吃。
  int get activeKinds => min(_pool.length, startKinds + matches ~/ matchesPerNewKind);

  /// 下一次配對成功會加幾秒：前 20 組 +3 秒，第 21～50 組 +2 秒，之後 +1 秒。
  int get nextTimeGain => timeGainFor(matches);

  static int timeGainFor(int matchesSoFar) {
    if (matchesSoFar < 20) return 3;
    if (matchesSoFar < 50) return 2;
    return 1;
  }

  /// 補牌時希望桌上有幾張落單牌，越後面越多，要記的東西越多。
  int get targetSingles => min(maxTargetSingles, 2 + matches ~/ 10);

  /// 每多少分換 1 枚金幣。比關卡（÷10）少一半，避免無盡模式被拿來刷金幣。
  static const scorePerCoin = 20;

  /// 結算金幣：遊戲結束後才有。
  int get coinsEarned {
    if (!isEnded) return 0;
    return (score / scorePerCoin * coinMultiplier * (luckyCatActive ? luckyCatMultiplier : 1)).round();
  }

  /// 還在桌上（未配對）的各種小吃張數。
  Map<Food, int> get _counts {
    final counts = <Food, int>{};
    for (var i = 0; i < cards.length; i++) {
      if (!isMatched[i]) counts.update(cards[i], (c) => c + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  /// 桌上有幾組完整的對子。
  int get pairsOnBoard => _counts.values.where((c) => c == 2).length;

  /// 桌上有幾張落單的牌（另一半還沒出現）。
  int get singlesOnBoard => _counts.values.where((c) => c == 1).length;

  void reset() {
    _kindOrder = _pool.toList()..shuffle(_random);
    // 開局跟一般關卡一樣全是成對的牌，從一開始的 startKinds 種裡挑
    final pairs = (_kindOrder.take(startKinds).toList()..shuffle(_random)).take(boardSize ~/ 2).toList();
    cards = [...pairs, ...pairs]..shuffle(_random);
    isOpen = List.filled(boardSize, false);
    isMatched = List.filled(boardSize, false);
    isSeen = List.filled(boardSize, false);
    consecutiveMisses = 0;
    matchesSinceBossHint = bossHintCooldownMatches; // 第一次不用等冷卻
    firstPickedIndex = null;
    secondPickedIndex = null;
    steps = 0;
    score = 0;
    combo = 1;
    matches = 0;
    timeLeft = maxSeconds;
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
    lastMatched = null;
    lastMatchedCards = const [];
    lastPoints = 0;
    lastCombo = 1;
    lastTimeGain = 0;
    lastRefilled = const [];
  }

  PickResult pick(int index) {
    if (isEnded || isLocked || isMatched[index] || isOpen[index]) return PickResult.ignored;

    isOpen[index] = true;
    isSeen[index] = true;
    steps++;

    final first = firstPickedIndex;
    if (first == null) {
      firstPickedIndex = index;
      return PickResult.firstPicked;
    }

    if (cards[first] == cards[index]) {
      _match(first, index);
      return PickResult.matched;
    }

    secondPickedIndex = index;
    mistakes++;
    consecutiveMisses++;
    if (charmActive) {
      charmActive = false; // 護身符擋下這次翻錯，連擊不中斷
    } else {
      combo = 1;
    }
    return PickResult.mismatched;
  }

  void _match(int a, int b) {
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
    // 加秒數不超過上限，但沙漏加超過上限的時間也不會被扣回去
    timeLeft = max(timeLeft, min(maxSeconds, timeLeft + lastTimeGain));
    matches++;
    consecutiveMisses = 0;
    matchesSinceBossHint++;
  }

  /// 把已配對的格子補上新牌（畫面放完配對特效後呼叫）。回傳補了哪些格子。
  List<int> refill() {
    final slots = [for (var i = 0; i < boardSize; i++) if (isMatched[i]) i]..shuffle(_random);
    final batch = <Food>{};
    for (final i in slots) {
      final food = _chooseRefill(batch);
      cards[i] = food;
      isMatched[i] = false;
      isOpen[i] = false;
      isSeen[i] = false;
      batch.add(food);
    }
    lastRefilled = slots..sort();
    return lastRefilled;
  }

  /// 選一張要補上的牌。[batch] 是這一批已經補上的小吃，它們的另一半這一批不能出現。
  Food _chooseRefill(Set<Food> batch) {
    final counts = _counts;
    final pairs = counts.values.where((c) => c == 2).length;
    final singles = counts.values.where((c) => c == 1).length;

    // 可以補成一對的：桌上落單、而且不是這一批剛補上的
    final partners = [
      for (final e in counts.entries)
        if (e.value == 1 && !batch.contains(e.key)) e.key,
    ];
    // 可以當新小吃的：目前會出現、桌上一張都沒有的
    final fresh = [
      for (final f in _kindOrder.take(activeKinds))
        if (!counts.containsKey(f)) f,
    ];

    Food pickFrom(List<Food> list) => list[_random.nextInt(list.length)];

    // 對子不夠就先補成對，避免死局
    if (pairs < minPairsOnBoard && partners.isNotEmpty) return pickFrom(partners);

    var wantFresh = singles < targetSingles;
    if (_random.nextDouble() < surpriseChance) wantFresh = !wantFresh;

    if (wantFresh && fresh.isNotEmpty) return pickFrom(fresh);
    if (partners.isNotEmpty) return pickFrom(partners);
    if (fresh.isNotEmpty) return pickFrom(fresh);
    // 依 startKinds 和棋盤大小的設定不會走到這裡，測試會檢查
    throw StateError('沒有可以補的牌');
  }

  bool canUseItem(ItemType type) {
    if (isEnded || usedItems.contains(type)) return false;
    return type != ItemType.magnifier || !isLocked;
  }

  /// 使用道具。不能用時回傳 false。放大鏡配對後畫面要呼叫 [refill]。
  bool useItem(ItemType type) {
    if (!canUseItem(type)) return false;
    usedItems.add(type);
    switch (type) {
      case ItemType.magnifier:
        _magnify();
      case ItemType.hourglass:
        timeLeft += hourglassSeconds;
      case ItemType.charm:
        charmActive = true;
      case ItemType.luckyCat:
        luckyCatActive = true;
    }
    return true;
  }

  /// 放大鏡：已經翻開一張、而且另一半在桌上就配那一張；
  /// 否則把翻開的那張蓋回去，配桌上任一組完整的對子。
  void _magnify() {
    int? partnerOf(int a) {
      for (var i = 0; i < boardSize; i++) {
        if (i != a && !isMatched[i] && cards[i] == cards[a]) return i;
      }
      return null;
    }

    final first = firstPickedIndex;
    if (first != null) {
      final partner = partnerOf(first);
      if (partner != null) {
        _match(first, partner);
        return;
      }
      isOpen[first] = false;
      firstPickedIndex = null;
    }
    for (var a = 0; a < boardSize; a++) {
      if (isMatched[a]) continue;
      final b = partnerOf(a);
      if (b != null) {
        _match(a, b);
        return;
      }
    }
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
  void startPreview() {
    isPreviewing = true;
    _seeAll();
  }

  void endPreview() => isPreviewing = false;

  /// 開始偷看：先把翻錯等待中的牌蓋回去，再讓畫面顯示全部牌面。
  bool startPeek() {
    if (!canPeek) return false;
    hideMismatched();
    hintUsed = true;
    isPeeking = true;
    _seeAll();
    return true;
  }

  void _seeAll() {
    for (var i = 0; i < boardSize; i++) {
      isSeen[i] = true;
    }
  }

  /// 這張牌要不要標「新」：還在桌上、玩家還沒看過。
  bool isNew(int index) => !isMatched[index] && !isSeen[index];

  /// 連續翻錯 [bossHintAfterMisses] 次、而且過了冷卻，就挑桌上一組對子告訴玩家（畫面在翻錯的牌蓋回去後呼叫）。
  /// 回傳那兩張牌的位置；不符合條件回傳 null。
  List<int>? takeBossHint() {
    if (isEnded || isLocked) return null;
    if (consecutiveMisses < bossHintAfterMisses || matchesSinceBossHint < bossHintCooldownMatches) return null;
    final pairs = <List<int>>[];
    for (var a = 0; a < boardSize; a++) {
      if (isMatched[a] || isOpen[a]) continue;
      for (var b = a + 1; b < boardSize; b++) {
        if (!isMatched[b] && !isOpen[b] && cards[a] == cards[b]) pairs.add([a, b]);
      }
    }
    if (pairs.isEmpty) return null;
    // 不用 _random 挑，免得打亂之後補牌的順序；用配對和翻錯次數輪流挑，每次提示的位置不一樣
    final hint = pairs[(matches + mistakes) % pairs.length];
    consecutiveMisses = 0;
    matchesSinceBossHint = 0;
    isSeen[hint[0]] = true;
    isSeen[hint[1]] = true;
    return hint;
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
