import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/achievements.dart';
import 'package:night_market_match/game/card_skins.dart';
import 'package:night_market_match/game/daily_challenge.dart';
import 'package:night_market_match/game/endless_game.dart';
import 'package:night_market_match/game/gear_advice.dart';
import 'package:night_market_match/game/items.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/game/night_market_data.dart';
import 'package:night_market_match/game/wheel.dart';
import 'package:night_market_match/screens/endless_screen.dart';
import 'package:night_market_match/screens/game_screen.dart';
import 'package:night_market_match/screens/home_screen.dart';
import 'package:night_market_match/screens/settings_screen.dart';
import 'package:night_market_match/screens/shop_screen.dart';
import 'package:night_market_match/screens/splash_screen.dart';
import 'package:night_market_match/services/ad_service.dart';
import 'package:night_market_match/services/leaderboard_service.dart';
import 'package:night_market_match/services/progress_store.dart';
import 'package:night_market_match/screens/achievements_screen.dart';
import 'package:night_market_match/screens/daily_screen.dart';
import 'package:night_market_match/services/purchase_service.dart';
import 'package:night_market_match/services/reminder_service.dart';
import 'package:night_market_match/services/share_service.dart';
import 'package:night_market_match/services/sound_service.dart';
import 'package:night_market_match/theme.dart';
import 'package:night_market_match/widgets/card_widget.dart';
import 'package:night_market_match/widgets/coin.dart';
import 'package:night_market_match/widgets/game_widgets.dart';
import 'package:night_market_match/widgets/match_effects.dart';
import 'package:night_market_match/widgets/prize_wheel.dart';
import 'package:night_market_match/widgets/rolling_number.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 找含有金幣圖示的文字（畫面上 🪙 會換成金幣圖示，所以用原本的文字比對）。
Finder findCoinText(String text) => find.byWidgetPredicate((w) => w is CoinText && w.text == text);

/// 測試遊戲機制用的固定關卡（牌數 12～24 張、時間寬鬆），連擊、道具、結算等測試都用這一組，
/// 這樣調整正式關卡的牌數和時間時，不會影響遊戲機制的測試。正式關卡另外在「內容資料」測試。
const testLevels = <Level>[
  Level(name: '南機場夜市', city: '台北', pairs: 6, seconds: 60),
  Level(name: '城隍廟夜市', city: '新竹', pairs: 8, seconds: 70),
  Level(name: '中壢觀光夜市', city: '桃園', pairs: 10, seconds: 85),
  Level(name: '樂華夜市', city: '新北', pairs: 10, seconds: 70),
  Level(name: '華西街夜市', city: '台北', pairs: 12, seconds: 95),
  Level(name: '大東夜市', city: '台南', pairs: 12, seconds: 80),
  Level(name: '文化路夜市', city: '嘉義', pairs: 8, seconds: 45),
  Level(name: '東大門夜市', city: '花蓮', pairs: 10, seconds: 60),
  Level(name: '一中街', city: '台中', pairs: 12, seconds: 75),
  Level(name: '瑞豐夜市', city: '高雄', pairs: 10, seconds: 50),
  Level(name: '寧夏夜市', city: '台北', pairs: 12, seconds: 70),
  Level(name: '羅東夜市', city: '宜蘭', pairs: 12, seconds: 65),
  Level(name: '基隆廟口夜市', city: '基隆', pairs: 12, seconds: 62),
  Level(name: '花園夜市', city: '台南', pairs: 12, seconds: 58),
  Level(name: '六合夜市', city: '高雄', pairs: 12, seconds: 55),
  Level(name: '饒河街夜市', city: '台北', pairs: 12, seconds: 52),
  Level(name: '逢甲夜市', city: '台中', pairs: 12, seconds: 50),
  Level(name: '士林夜市', city: '台北', pairs: 12, seconds: 48),
];

/// 假的廣告服務：記錄被呼叫幾次，並可決定獎勵型廣告是否成功。
class FakeAdService implements AdService {
  bool rewardSucceeds = true;
  int rewardedShown = 0;
  int interstitialShown = 0;

  @override
  Future<bool> showRewarded() async {
    rewardedShown++;
    return rewardSucceeds;
  }

  @override
  Future<void> showInterstitial() async => interstitialShown++;
}

class FakeAdPrivacy implements AdPrivacy {
  bool required = false;
  int shown = 0;

  @override
  bool get privacyOptionsRequired => required;

  @override
  Future<void> showPrivacyOptions() async => shown++;
}

int pairOf(MatchingGame g, int i) =>
    List.generate(g.cards.length, (j) => j).firstWhere((j) => j != i && g.cards[j] == g.cards[i]);
int differentFrom(MatchingGame g, int i) =>
    List.generate(g.cards.length, (j) => j).firstWhere((j) => g.cards[j] != g.cards[i]);

/// 依序把所有牌配對完。
void solve(MatchingGame g) {
  for (var i = 0; i < g.cards.length; i++) {
    if (g.isMatched[i]) continue;
    g.pick(i);
    g.pick(pairOf(g, i));
  }
}

// ---------- 夜市大胃王：從畫面讀出桌上的牌 ----------

/// 畫面上桌的牌：格子位置 → 小吃（蓋著的牌也讀得到是什麼）。相撞動畫裡的牌沒有 key，不算。
Map<int, Food> tableOnScreen(WidgetTester tester) => {
      for (final e in find
          .byWidgetPredicate((w) =>
              w is CardWidget && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('card_'))
          .evaluate())
        int.parse(((e.widget as CardWidget).key! as ValueKey<String>).value.substring(5)):
            (e.widget as CardWidget).food,
    };

/// 桌上的一組對子。
(int, int) pairOnScreen(WidgetTester tester) {
  final table = tableOnScreen(tester);
  for (final a in table.keys) {
    for (final b in table.keys) {
      if (b > a && table[a] == table[b]) return (a, b);
    }
  }
  throw StateError('桌上沒有對子');
}

/// 桌上兩張不一樣的牌；只剩一組時回傳 null。
(int, int)? mismatchOnScreen(WidgetTester tester) {
  final table = tableOnScreen(tester);
  for (final a in table.keys) {
    for (final b in table.keys) {
      if (b > a && table[a] != table[b]) return (a, b);
    }
  }
  return null;
}

/// 大胃王畫面上某個 key 的文字；總分是拉霸數字，讀它目前顯示的數字。
String endlessText(WidgetTester tester, String key) {
  final widget = tester.widget(find.byKey(ValueKey(key)));
  return widget is RollingNumber ? '${widget.value}' : (widget as Text).data!;
}

/// 點一組對子（只點，不等動畫）。
Future<void> tapEndlessPair(WidgetTester tester) async {
  final (a, b) = pairOnScreen(tester);
  await tester.tap(find.byKey(ValueKey('card_$a')));
  await tester.tap(find.byKey(ValueKey('card_$b')));
  await tester.pump();
}

/// 等相撞動畫（吃光的話，相撞完新的一波直接上桌）。
Future<void> settleEndlessEat(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 950));
  await tester.pump(const Duration(milliseconds: 700)); // 加分數字飛到總分（吃光的獎勵最晚，約 1.6 秒）
}

/// 吃一組。
Future<void> eatEndlessPair(WidgetTester tester) async {
  await tapEndlessPair(tester);
  await settleEndlessEat(tester);
}

/// 翻錯一次，等牌蓋回去（滿 3 次老闆會加菜）。桌上只剩一組時先吃掉（會吃光、上下一波）。
Future<void> missEndlessPair(WidgetTester tester) async {
  var pair = mismatchOnScreen(tester);
  if (pair == null) {
    await eatEndlessPair(tester);
    pair = mismatchOnScreen(tester)!;
  }
  final (a, b) = pair;
  await tester.tap(find.byKey(ValueKey('card_$a')));
  await tester.tap(find.byKey(ValueKey('card_$b')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 桌子塞滿了嗎（訊息列顯示吃不下了）。
bool endlessFull() => find.text('桌子塞滿了，吃不下了！').evaluate().isNotEmpty;

/// 一直翻錯到桌子塞滿；[showDialog] 為 true 時再等結算視窗跳出來。
Future<void> fillEndlessTable(WidgetTester tester, {bool showDialog = true}) async {
  while (!endlessFull()) {
    await missEndlessPair(tester);
  }
  if (!showDialog) return;
  await tester.pump(EndlessScreenState.fullPause);
  await tester.pump(const Duration(milliseconds: 400));
}

/// 假的排行榜：記錄送出的分數和打開過哪個排行榜。
class FakeLeaderboardService implements LeaderboardService {
  final submitted = <(Leaderboard, int)>[];
  final shown = <Leaderboard>[];

  @override
  bool get available => true;

  @override
  Future<void> submit(Leaderboard board, int score) async => submitted.add((board, score));

  @override
  Future<void> show(Leaderboard board) async => shown.add(board);
}

/// 假的分享：記錄分享了什麼。
class FakeShareService implements ScoreShareService {
  final shared = <ScoreCard>[];

  @override
  Future<void> share(ScoreCard card, {Rect? origin}) async => shared.add(card);
}

/// 假的每日提醒：記錄有沒有排程、取消。
class FakeReminderService implements ReminderService {
  FakeReminderService({this.allow = true});

  bool allow;
  int asked = 0;
  int scheduled = 0;
  int cancelled = 0;

  @override
  Future<bool> requestPermission() async {
    asked++;
    return allow;
  }

  @override
  Future<void> reschedule(ProgressStore store) async => scheduled++;

  @override
  Future<void> cancelAll() async => cancelled++;
}

/// 每次都回傳「玩家取消」的假商店。
class _CancelPurchases implements PurchaseService {
  @override
  Future<PurchaseResult> buy(String productId) async => PurchaseResult.cancelled;

  @override
  Future<Set<String>?> restore() async => {};

  @override
  String? price(String productId) => null;

  @override
  bool get deliversContent => false;
}

/// 假的音效服務：只記錄播了哪些音效。
class FakeSoundService implements SoundService {
  final played = <Sfx>[];

  @override
  bool muted = false;

  @override
  void play(Sfx sfx) {
    if (!muted) played.add(sfx);
  }

  @override
  bool musicOn = true;

  @override
  double musicVolume = defaultMusicVolume;

  @override
  double sfxVolume = defaultSfxVolume;

  /// 背景音樂的暫停／恢復紀錄。
  final musicEvents = <String>[];

  @override
  void pauseMusic() => musicEvents.add('pause');

  @override
  void resumeMusic() => musicEvents.add('resume');
}

void main() {
  group('MatchingGame', () {
    test('每一關的牌數 = 組數 × 2，每種小吃各 2 張', () {
      for (final level in levels) {
        final g = MatchingGame(level: level, random: Random(1));
        expect(g.cards.length, level.pairs * 2);
        for (final f in g.cards.toSet()) {
          expect(g.cards.where((c) => c == f).length, 2);
        }
        expect(g.timeLeft, level.seconds);
      }
    });

    test('連續配對累積連擊與分數，最高 ×5', () {
      final g = MatchingGame(level: testLevels[2], random: Random(1));
      final expected = [100, 200, 300, 400, 500, 500];
      var total = 0;
      for (final points in expected) {
        final i = List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j]);
        g.pick(i);
        g.pick(pairOf(g, i));
        total += points;
        expect(g.lastPoints, points);
        expect(g.score, total);
      }
      expect(g.combo, 5);
    });

    test('翻錯會中斷連擊並鎖住，蓋回後才能再翻', () {
      final g = MatchingGame(level: testLevels[0], random: Random(1));
      g.pick(0);
      g.pick(pairOf(g, 0));
      expect(g.combo, 2);

      final a = List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j]);
      final b = List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j] && g.cards[j] != g.cards[a]);
      g.pick(a);
      expect(g.pick(b), PickResult.mismatched);
      expect(g.combo, 1);
      expect(g.isLocked, isTrue);

      final other = List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isOpen[j]);
      expect(g.pick(other), PickResult.ignored);
      expect(g.steps, 4);

      g.hideMismatched();
      expect(g.isOpen[a], isFalse);
      expect(g.isOpen[b], isFalse);
      expect(g.isLocked, isFalse);
    });

    test('全部配對完成：過關、加時間獎勵、算星數和金幣', () {
      final g = MatchingGame(level: testLevels[0], random: Random(1));
      for (var s = 0; s < 10; s++) {
        g.tick();
      }
      solve(g);
      expect(g.isWon, isTrue);
      expect(g.timeLeft, 50);
      expect(g.timeBonus, 500);
      // 6 組連續配對：100+200+300+400+500+500 = 2000，加時間獎勵 500
      expect(g.score, 2500);
      expect(g.stars, 3);
      expect(g.coinsEarned, 250);
    });

    test('星數依剩餘時間比例', () {
      int starsWith(int secondsUsed) {
        final g = MatchingGame(level: testLevels[0], random: Random(1));
        for (var s = 0; s < secondsUsed; s++) {
          g.tick();
        }
        solve(g);
        return g.stars;
      }

      expect(starsWith(20), 3); // 剩 40/60
      expect(starsWith(35), 2); // 剩 25/60
      expect(starsWith(50), 1); // 剩 10/60
    });

    test('時間到就結束，不能再翻牌，也沒有金幣', () {
      final g = MatchingGame(level: testLevels[0], random: Random(1));
      var timeUp = false;
      for (var s = 0; s < 60; s++) {
        timeUp = g.tick();
      }
      expect(timeUp, isTrue);
      expect(g.isEnded, isTrue);
      expect(g.isWon, isFalse);
      expect(g.pick(0), PickResult.ignored);
      expect(g.coinsEarned, 0);
    });

    test('偷看：每局一次，偷看期間不能翻牌，翻錯等待中的牌會先蓋回', () {
      final g = MatchingGame(level: testLevels[0], random: Random(1));
      g.pick(0);
      g.pick(differentFrom(g, 0));
      expect(g.startPeek(), isTrue);
      expect(g.isOpen.where((o) => o).length, 0);
      expect(List.generate(g.cards.length, g.isFaceUp).every((f) => f), isTrue);
      expect(g.pick(1), PickResult.ignored);

      g.endPeek();
      expect(g.isFaceUp(1), isFalse);
      expect(g.pick(1), PickResult.firstPicked);
      expect(g.startPeek(), isFalse); // 已經用過
    });

    test('時間到可以看廣告 +15 秒繼續，每局一次', () {
      final g = MatchingGame(level: testLevels[0], random: Random(1));
      expect(g.revive(), isFalse); // 還沒時間到
      for (var s = 0; s < 60; s++) {
        g.tick();
      }
      expect(g.revive(), isTrue);
      expect(g.isEnded, isFalse);
      expect(g.timeLeft, 15);
      expect(g.pick(0), PickResult.firstPicked);

      for (var s = 0; s < 15; s++) {
        g.tick();
      }
      expect(g.isEnded, isTrue);
      expect(g.revive(), isFalse);
    });
  });

  group('道具與裝備', () {
    test('保溫便當袋：走透透翻錯時連擊只少 1 段，最低 1', () {
      final g = MatchingGame(level: testLevels[0], random: Random(1), comboKeepOnMiss: true);
      for (var i = 0; i < 3; i++) {
        final a = List.generate(g.cards.length, (k) => k).firstWhere((k) => !g.isMatched[k]);
        g.pick(a);
        g.pick(pairOf(g, a));
      }
      expect(g.combo, 4);
      final x = List.generate(g.cards.length, (k) => k).firstWhere((k) => !g.isMatched[k]);
      g.pick(x);
      g.pick(List.generate(g.cards.length, (k) => k).firstWhere((k) => !g.isMatched[k] && g.cards[k] != g.cards[x]));
      expect(g.combo, 3);
      g.hideMismatched();
      final plain = MatchingGame(level: testLevels[0], random: Random(1), comboKeepOnMiss: true);
      final y = 0;
      plain.pick(y);
      plain.pick(differentFrom(plain, y));
      expect(plain.combo, 1, reason: '連擊最低 1');
    });

    MatchingGame newGame({int level = 0, int bonus = 0, int cap = 5, double multiplier = 1}) => MatchingGame(
          level: testLevels[level],
          random: Random(1),
          bonusSeconds: bonus,
          comboCap: cap,
          coinMultiplier: multiplier,
        );

    test('放大鏡：配對已翻開的那張，沒翻牌就配第一組；每局一次', () {
      final g = newGame();
      g.pick(3);
      final partner = pairOf(g, 3);
      expect(g.useItem(ItemType.magnifier), isTrue);
      expect(g.isMatched[3] && g.isMatched[partner], isTrue);
      expect(g.firstPickedIndex, isNull);
      expect(g.score, 100);
      expect(g.useItem(ItemType.magnifier), isFalse);

      final g2 = newGame();
      g2.useItem(ItemType.magnifier);
      expect(g2.isMatched[0], isTrue);
      expect(g2.matchedPairs, 1);
    });

    test('放大鏡：翻錯等待中不能用；配完最後一組會過關', () {
      final g = newGame();
      g.pick(0);
      g.pick(differentFrom(g, 0));
      expect(g.canUseItem(ItemType.magnifier), isFalse);
      g.hideMismatched();
      expect(g.canUseItem(ItemType.magnifier), isTrue);

      final g2 = newGame();
      final lastPair = g2.cards.last;
      for (var i = 0; i < g2.cards.length; i++) {
        if (g2.isMatched[i] || g2.cards[i] == lastPair) continue;
        g2.pick(i);
        g2.pick(pairOf(g2, i));
      }
      expect(g2.pairsLeft, 1);
      g2.useItem(ItemType.magnifier);
      expect(g2.isWon, isTrue);
    });

    test('沙漏 +10 秒，時間到之後不能用', () {
      final g = newGame();
      g.tick();
      g.useItem(ItemType.hourglass);
      expect(g.timeLeft, 69);

      final g2 = newGame();
      for (var s = 0; s < 60; s++) {
        g2.tick();
      }
      expect(g2.useItem(ItemType.hourglass), isFalse);
    });

    test('護身符擋一次翻錯：連擊不中斷，但翻錯次數照算', () {
      final g = newGame(level: 1);
      g.pick(0);
      g.pick(pairOf(g, 0));
      expect(g.combo, 2);
      g.useItem(ItemType.charm);

      int unmatched() => List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j]);
      int other(int a) =>
          List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j] && g.cards[j] != g.cards[a]);

      var a = unmatched();
      g.pick(a);
      g.pick(other(a));
      expect(g.combo, 2);
      expect(g.mistakes, 1);
      expect(g.charmActive, isFalse);
      g.hideMismatched();

      a = unmatched();
      g.pick(a);
      g.pick(other(a));
      expect(g.combo, 1);
      expect(g.mistakes, 2);
    });

    test('招財貓和算盤都會增加金幣，可以疊加', () {
      final plain = newGame();
      solve(plain);
      expect(plain.coinsEarned, 260);

      final g = newGame(multiplier: 1.2);
      g.useItem(ItemType.luckyCat);
      solve(g);
      expect(g.coinsEarned, (260 * 1.2 * 1.5).round());
    });

    test('裝備：帽子加時間，攤車提高連擊上限', () {
      final g = newGame(level: 2, bonus: 6, cap: 7);
      expect(g.timeLeft, 91);
      expect(g.totalSeconds, 91);
      solve(g);
      expect(g.bestCombo, 7);
      expect(g.combo, 7);
    });

    test('裝備效果換算與費用', () {
      expect(GearEffects.bonusSeconds(3), 6);
      expect(GearEffects.coinMultiplier(3), closeTo(1.3, 0.001));
      expect(GearEffects.comboCap(2), 7);
      expect(GearType.hat.maxLevel, 3);
      expect(GearType.cart.maxLevel, 2);
    });
  });

  group('內容資料', () {
    test('18 攤夜市，難度遞增，小吃種類夠最大的一攤用', () {
      expect(levels.length, 18);
      expect(levels.map((l) => l.name).toSet().length, 18);
      // 牌數由少到多：2 → 4 → 6 → 8 → 10 → 12 → 16 → 20 張，最多 20 張
      expect([for (final l in levels) l.pairs * 2], [2, 4, 4, 6, 6, 6, 8, 8, 8, 10, 10, 12, 12, 16, 16, 20, 20, 20]);
      // 最後一攤的時間最緊（平均每組可用秒數最少）
      double perPair(Level l) => l.seconds / l.pairs;
      expect(levels.map(perPair).reduce(min), perPair(levels.last));
      final maxPairs = levels.map((l) => l.pairs).reduce(max);
      expect(foods.length, greaterThanOrEqualTo(maxPairs));
      expect(foods.map((f) => f.name).toSet().length, foods.length);
      expect(foods.map((f) => f.emoji).toSet().length, foods.length);
      for (var i = 1; i < levels.length; i++) {
        final prev = levels[i - 1], cur = levels[i];
        // 牌更多，或牌一樣多但時間更少
        expect(cur.pairs > prev.pairs || cur.seconds < prev.seconds, isTrue, reason: cur.name);
      }
    });

    test('新卡背：夜市遊戲攤四款可以買，小吃王和火眼金睛只能靠成就', () {
      expect({
        for (final id in ['goldfish', 'balloon', 'ringtoss', 'lantern_fest']) id: skinById(id).price
      }, {
        'goldfish': 3000,
        'balloon': 5000,
        'ringtoss': 7000,
        'lantern_fest': 12000
      });
      for (final id in ['foodking', 'eagle_eye']) {
        expect(skinById(id).id, id);
        expect(skinById(id).achievementOnly, isTrue);
      }
      expect(achievements.firstWhere((a) => a.id == 'foods20').skinId, 'foodking');
      final perfect10 = achievements.firstWhere((a) => a.id == 'perfect10');
      expect(perfect10.skinId, 'eagle_eye');
      expect(perfect10.target, 10);
    });

    test('卡背：紅燈籠維持單色，其他都有花紋；摸麻將、戳戳樂取代青草茶、珍奶控；火眼金睛是貓頭鷹', () {
      expect(skinById(defaultSkinId).pattern, CardPattern.plain);
      expect(cardSkins.where((s) => s.id != defaultSkinId).every((s) => s.pattern != CardPattern.plain), isTrue);
      expect(cardSkins.map((s) => s.id), isNot(contains('jade')));
      expect(cardSkins.map((s) => s.id), isNot(contains('boba')));
      final mahjong = skinById('mahjong');
      expect((mahjong.name, mahjong.price, mahjong.mark, mahjong.pattern), ('摸麻將', 6000, '發', CardPattern.mahjong));
      final poke = skinById('pokepoke');
      expect((poke.name, poke.price, poke.pattern), ('戳戳樂', 9000, CardPattern.poke));
      expect(skinById('eagle_eye').mark, '🦉');
      expect(cardSkins.length, 16);
    });

    test('商店排列：道具、裝備、卡背都依價格由便宜到貴，成就卡背排最後', () {
      expect(ShopScreen.sortedItems.map((t) => t.price), [200, 250, 300, 600]);
      expect(ShopScreen.sortedGear.map((t) => t.name),
          ['hat', 'abacus', 'backpack', 'favor', 'glasses', 'cart', 'lunchBag']);
      final paid = ShopScreen.sortedSkins.where((s) => s.buyable).map((s) => s.price).toList();
      expect(paid, [...paid]..sort());
      expect(ShopScreen.sortedSkins.first.id, defaultSkinId);
      expect(ShopScreen.sortedSkins.skipWhile((s) => !s.achievementOnly).every((s) => s.achievementOnly), isTrue);
      expect(ShopScreen.sortedSkins.length, cardSkins.length);
    });

    test('裝備：7 件，大胃王限定的有標示', () {
      expect(GearType.values.map((g) => g.name), ['hat', 'abacus', 'cart', 'glasses', 'lunchBag', 'backpack', 'favor']);
      expect(GearType.values.where((g) => g.endlessOnly), {GearType.backpack, GearType.favor});
    });

    test('卡背 id 不重複，預設卡背免費', () {
      expect(cardSkins.map((s) => s.id).toSet().length, cardSkins.length);
      expect(skinById(defaultSkinId).price, 0);
      expect(skinById('不存在').id, defaultSkinId);
    });

    test('20 種小吃都有專屬圖片，檔案都存在', () {
      for (final food in foods.where((f) => f.image != null)) {
        expect(File(food.image!).existsSync(), isTrue, reason: food.name);
      }
      expect(foods.every((f) => f.image != null), isTrue);
      expect(foods.map((f) => f.image).toSet().length, foods.length);
    });

    test('每日任務：每天 5 個，只能在走透透或只能在大胃王完成的各最多 2 個；一年內每天都抽得滿', () async {
      SharedPreferences.setMockInitialValues({});
      var today = DateTime(2026, 1, 1);
      final store = await ProgressStore.load(clock: () => today);
      final seen = <String>{};
      for (var d = 0; d < 365; d++) {
        today = DateTime(2026, 1, 1 + d);
        final tasks = store.todayTasks;
        expect(tasks.length, 5, reason: '$today');
        for (final mode in [TaskMode.tour, TaskMode.endless]) {
          expect(tasks.where((t) => t.mode == mode).length, lessThanOrEqualTo(maxTasksPerMode), reason: '$today $mode');
        }
        seen.addAll(tasks.map((t) => t.id));
      }
      expect(seen, dailyTaskPool.map((t) => t.id).toSet(), reason: '每個任務都抽得到');
    });

    test('每日任務的進度：大胃王輪數、單輪 10000 分（只記一次）、吃光、大胃王時間、每日挑戰、轉盤、配對 100 組', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load(clock: () => DateTime(2026, 11, 20, 12));
      await store.recordEndlessRound();
      await store.recordEndlessScore(12000);
      await store.recordEndlessScore(15000);
      store.recordAllClear();
      store.recordFever();
      await store.startDailyChallenge();
      await store.startDailyChallenge();
      await store.claimWheel(0, byAd: false);
      await store.recordMatch(foods[0], 1);
      expect(
        {for (final id in ['endless_round', 'endless_score', 'all_clear', 'fever', 'challenge', 'wheel', 'match100']) id: store.dailyProgress(id)},
        {'endless_round': 1, 'endless_score': 1, 'all_clear': 1, 'fever': 1, 'challenge': 1, 'wheel': 1, 'match100': 1},
      );
    });

    test('今日任務排序：可領的在上、沒完成的中間、領過的最下面', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load(clock: () => DateTime(2026, 11, 20, 12));
      final tasks = store.todayTasks;
      store.dailyProgress(tasks[0].id); // 先換日，免得等一下設的進度被清掉
      // 第 1 個完成並領掉、第 3 個完成沒領
      for (final t in [tasks[0], tasks[2]]) {
        await SharedPreferences.getInstance().then((p) => p.setInt('daily_p_${t.id}', t.target));
      }
      await store.claimDaily(tasks[0]);
      final ordered = DailyScreen.orderedTasks(store).map((t) => t.id).toList();
      expect(ordered.first, tasks[2].id);
      expect(ordered.last, tasks[0].id);
      expect(ordered.sublist(1, 4), [tasks[1].id, tasks[3].id, tasks[4].id]);
    });

    test('20 種小吃都有介紹；成就的卡背獎勵都存在，id 不重複', () {
      expect(foods.every((f) => f.description.isNotEmpty), isTrue);
      expect(achievements.map((a) => a.id).toSet().length, achievements.length);
      expect(dailyTaskPool.map((t) => t.id).toSet().length, dailyTaskPool.length);
      for (final a in achievements.where((a) => a.skinId != null)) {
        expect(cardSkins.any((s) => s.id == a.skinId && s.achievementOnly), isTrue, reason: a.id);
      }
      // 達成條件要對得上目前的關卡和小吃數量
      expect(achievements.firstWhere((a) => a.id == 'tour').target, levels.length);
      expect(achievements.firstWhere((a) => a.id == 'god').target, levels.length * 3);
      expect(achievements.firstWhere((a) => a.id == 'foods20').target, foods.length);
    });
  });

  group('ProgressStore', () {
    test('買卡背：金幣不夠買不了，買了會扣金幣並可換上', () async {
      final starry = skinById('starry');
      final fortune = skinById('fortune');
      final start = fortune.price + 100; // 買得起招財金，買不起夜空藍
      expect(start, lessThan(starry.price));
      SharedPreferences.setMockInitialValues({'coins': start});
      final store = await ProgressStore.load();
      expect(await store.buySkin(starry), isFalse);
      expect(store.coins, start);

      expect(await store.buySkin(fortune), isTrue);
      expect(store.coins, 100);
      expect(store.ownedSkins, {defaultSkinId, 'fortune'});
      expect(await store.buySkin(fortune), isFalse); // 不能重複買

      expect(store.equippedSkin, defaultSkinId);
      await store.equipSkin('fortune');
      expect(store.equippedSkin, 'fortune');
      await store.equipSkin('starry'); // 沒買的不能換
      expect(store.equippedSkin, 'fortune');
    });

    test('最佳星數只會往上更新', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load();
      expect(store.bestStars(2), 0);
      expect(await store.recordStars(2, 2), isTrue);
      expect(await store.recordStars(2, 1), isFalse);
      expect(store.bestStars(2), 2);
      expect(await store.recordStars(2, 3), isTrue);
      expect(store.bestStars(2), 3);
    });

    test('道具：買、用、數量不夠不能用', () async {
      SharedPreferences.setMockInitialValues({'coins': ItemType.hourglass.price + 50});
      final store = await ProgressStore.load();
      expect(await store.buyItem(ItemType.hourglass), isTrue);
      expect(store.coins, 50);
      expect(await store.buyItem(ItemType.hourglass), isFalse);
      expect(store.itemCount(ItemType.hourglass), 1);
      expect(await store.consumeItem(ItemType.hourglass), isTrue);
      expect(await store.consumeItem(ItemType.hourglass), isFalse);
      expect(store.itemCount(ItemType.hourglass), 0);
    });

    test('裝備升級：扣金幣、滿級後不能再升', () async {
      final costs = GearType.cart.costs;
      SharedPreferences.setMockInitialValues({'coins': costs[0] + costs[1] + 300});
      final store = await ProgressStore.load();
      expect(store.upgradeCost(GearType.cart), costs[0]);
      expect(await store.upgradeGear(GearType.cart), isTrue);
      expect(store.upgradeCost(GearType.cart), costs[1]);
      expect(await store.upgradeGear(GearType.cart), isTrue);
      expect(store.upgradeCost(GearType.cart), isNull);
      expect(await store.upgradeGear(GearType.cart), isFalse);
      expect(store.gearLevel(GearType.cart), 2);
      expect(store.coins, 300);
    });

    test('成就：要達成才能領，只能領一次，卡背獎勵不能用金幣買', () async {
      SharedPreferences.setMockInitialValues({'coins': 9999});
      final store = await ProgressStore.load();
      final god = achievements.firstWhere((a) => a.id == 'god');
      final combo = achievements.firstWhere((a) => a.id == 'combo5');
      expect(await store.buySkin(skinById('god')), isFalse);
      expect(await store.claimAchievement(combo), isFalse);

      await store.recordMatch(foods[0], 5);
      expect(store.isAchieved(combo), isTrue);
      expect(store.hasClaimableAchievement, isTrue);
      expect(await store.claimAchievement(combo), isTrue);
      expect(await store.claimAchievement(combo), isFalse);
      expect(store.coins, 10099);

      for (var i = 0; i < levels.length; i++) {
        await store.recordStars(i, 3);
      }
      expect(await store.claimAchievement(god), isTrue);
      expect(store.ownedSkins, contains('god'));
    });

    test('夜市大胃王紀錄：最高分、最多組數、輪數都計入成就，重置會清掉', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load();
      Achievement byId(String id) => achievements.firstWhere((a) => a.id == id);

      expect(await store.recordEndlessScore(24000, matches: 20), isTrue);
      expect(await store.recordEndlessScore(18000, matches: 85), isFalse, reason: '分數沒破紀錄');
      expect(store.endlessBest, 24000);
      expect(store.endlessBestMatches, 85, reason: '組數各自比較，沒破分數紀錄也會更新');
      await store.recordEndlessRound();
      await store.recordEndlessRound();
      expect(store.endlessRounds, 2);

      expect(store.isAchieved(byId('endless_first')), isTrue);
      expect(store.isAchieved(byId('endless_50000')), isFalse, reason: '24000 分還不到 50000');
      expect(store.isAchieved(byId('endless_100000')), isFalse);
      expect(store.isAchieved(byId('endless_pairs200')), isFalse, reason: '85 組還不到 200 組');
      await store.recordEndlessScore(0, matches: 200);
      expect(store.isAchieved(byId('endless_pairs200')), isTrue);
      expect(store.isAchieved(byId('endless_rounds20')), isFalse);

      expect(await store.claimAchievement(byId('endless_200000')), isFalse, reason: '還不到 200000 分');
      await store.recordEndlessScore(150000);
      expect(store.isAchieved(byId('endless_50000')), isTrue);
      expect(store.isAchieved(byId('endless_100000')), isTrue);
      expect(await store.claimAchievement(byId('endless_200000')), isFalse, reason: '150000 分還不夠');
      await store.recordEndlessScore(200000);
      expect(await store.claimAchievement(byId('endless_200000')), isTrue);
      expect(store.ownedSkins, contains('gourmet'));
      expect(await store.buySkin(skinById('gourmet')), isFalse, reason: '成就限定卡背不能用金幣買');

      await store.resetProgress();
      expect(store.endlessBest, 0);
      expect(store.endlessBestMatches, 0);
      expect(store.endlessRounds, 0);
    });

    test('圖鑑：同一種小吃只收錄一次', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load();
      expect(await store.recordMatch(foods[0], 1), isTrue);
      expect(await store.recordMatch(foods[0], 1), isFalse);
      expect(store.discoveredFoods, {foods[0].name});
    });

    test('每日任務：同一天任務固定，換日後進度和領取都重來', () async {
      SharedPreferences.setMockInitialValues({});
      var today = DateTime(2026, 11, 7);
      final store = await ProgressStore.load(clock: () => today);
      final tasks = store.todayTasks;
      expect(tasks.length, dailyTaskCount);
      expect(tasks.map((t) => t.id).toSet().length, dailyTaskCount);
      expect(store.todayTasks.map((t) => t.id), tasks.map((t) => t.id));

      const task = DailyTask(id: 'match', description: '', target: 2, coins: 40);
      await store.recordMatch(foods[0], 1);
      expect(await store.claimDaily(task), isFalse); // 還沒完成
      await store.recordMatch(foods[0], 1);
      expect(await store.claimDaily(task), isTrue);
      expect(await store.claimDaily(task), isFalse); // 不能重複領
      expect(store.coins, 40);

      today = DateTime(2026, 11, 8);
      expect(store.dailyProgress('match'), 0);
      expect(store.isDailyClaimed(task), isFalse);
    });

    test('簽到：連續天數遞增，斷掉重來，滿 7 天循環', () async {
      SharedPreferences.setMockInitialValues({});
      var today = DateTime(2026, 11, 28); // 跨月份也要算連續
      final store = await ProgressStore.load(clock: () => today);
      final got = <int>[];
      for (var i = 0; i < 8; i++) {
        got.add(await store.checkIn());
        expect(await store.checkIn(), 0); // 同一天不能簽兩次
        today = today.add(const Duration(days: 1));
      }
      expect(got, [...checkInRewards, checkInRewards.first]);

      today = today.add(const Duration(days: 3)); // 斷掉
      expect(store.nextCheckInDay, 1);
    });

    test('月卡：買下給立即金幣，含購買當天共 30 天每天領一次，續購接在後面，剩超過 30 天不能買', () async {
      SharedPreferences.setMockInitialValues({});
      var today = DateTime(2026, 12, 20, 23, 50); // 跨年也要算對
      final store = await ProgressStore.load(clock: () => today);
      expect(store.monthCardActive, isFalse);
      expect(await store.claimMonthCard(), 0);
      expect(store.canBuyMonthCard, isTrue);

      await store.activateMonthCard();
      expect(store.coins, monthCardInstantCoins);
      expect(store.monthCardDaysLeft, monthCardDays);
      expect(store.hasClaimableDaily, isTrue);

      // 每天領一次，同一天不能領兩次
      var claimed = 0;
      for (var day = 0; day < monthCardDays; day++) {
        expect(await store.claimMonthCard(), monthCardDailyCoins, reason: '第 ${day + 1} 天');
        expect(await store.claimMonthCard(), 0);
        claimed++;
        today = today.add(const Duration(days: 1));
      }
      expect(claimed, monthCardDays);
      expect(store.coins, monthCardTotalCoins);
      expect(store.monthCardActive, isFalse, reason: '第 31 天到期');
      expect(await store.claimMonthCard(), 0);

      // 到期後再買：從今天重新算
      await store.activateMonthCard();
      expect(store.monthCardDaysLeft, monthCardDays);
      // 續購：接在後面變 60 天，之後剩超過 30 天不能再買
      expect(store.canBuyMonthCard, isTrue);
      await store.activateMonthCard();
      expect(store.monthCardDaysLeft, monthCardDays * 2);
      expect(store.canBuyMonthCard, isFalse);
      today = today.add(const Duration(days: monthCardDays));
      expect(store.monthCardDaysLeft, monthCardDays);
      expect(store.canBuyMonthCard, isTrue);

      // 重置遊戲進度不會清掉月卡（真錢買的）
      await store.resetProgress();
      expect(store.monthCardDaysLeft, monthCardDays);
    });

    test('月卡數值：每 NT\$1 拿到的金幣是一般方案的兩倍左右', () {
      expect(monthCardTotalCoins, 10500);
      final normal = coinPacks.first.coins / coinPacks.first.priceNtd;
      expect(monthCardTotalCoins / monthCardPriceNtd / normal, closeTo(2.1, 0.1));
    });

    test('過關紀錄：零失誤、三星計入成就和每日任務', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load();
      await store.recordWin(stars: 3, mistakes: 0);
      await store.recordWin(stars: 2, mistakes: 4);
      expect(store.perfectRuns, 1);
      expect(store.dailyProgress('clear'), 2);
      expect(store.dailyProgress('stars3'), 1);
      expect(store.dailyProgress('perfect'), 1);
    });

    test('重置進度：清掉金幣、解鎖、星數、卡背，保留聲音設定和移除廣告', () async {
      SharedPreferences.setMockInitialValues({
        'coins': 900,
        'unlocked': 4,
        'clears': 7,
        'stars_0': 3,
        'stars_2': 1,
        'owned_skins': ['fortune'],
        'equipped_skin': 'fortune',
        'muted': true,
        'music_on': false,
        'ads_removed': true,
        'item_hourglass': 3,
        'gear_hat': 2,
        'stat_best_combo': 5,
        'foods': ['雞排'],
        'ach_claimed': ['combo5'],
        'checkin_streak': 4,
      });
      final store = await ProgressStore.load();
      await store.resetProgress();
      expect(store.coins, 0);
      expect(store.unlocked, 1);
      expect(store.clears, 0);
      expect(store.bestStars(0), 0);
      expect(store.bestStars(2), 0);
      expect(store.ownedSkins, {defaultSkinId});
      expect(store.equippedSkin, defaultSkinId);
      expect(store.itemCount(ItemType.hourglass), 0);
      expect(store.gearLevel(GearType.hat), 0);
      expect(store.bestCombo, 0);
      expect(store.discoveredFoods, isEmpty);
      expect(store.isClaimed(achievements.firstWhere((a) => a.id == 'combo5')), isFalse);
      expect(store.checkInStreak, 0);
      expect(store.muted, isTrue);
      expect(store.musicOn, isFalse);
      expect(store.adsRemoved, isTrue);
    });
  });

  late FakeAdService ads;
  late FakeSoundService sounds;
  late ProgressStore store;

  Future<void> setUpStore(WidgetTester tester, Map<String, Object> saved) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(saved);
    store = await ProgressStore.load();
    ads = FakeAdService();
    sounds = FakeSoundService()
      ..muted = store.muted
      ..musicOn = store.musicOn;
  }

  /// 直接打開某一攤的遊戲畫面。
  Future<void> pumpGame(WidgetTester tester, {Map<String, Object> saved = const {}, int level = 0}) async {
    await setUpStore(tester, saved);
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
          levelIndex: level,
          store: store,
          ads: ads,
          sounds: sounds,
          random: Random(1),
          previewSeconds: 0,
          levelList: testLevels),
    ));
  }

  /// 從首頁開始。
  Future<void> pumpHome(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
    await setUpStore(tester, saved);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
    ));
  }

  /// 等換頁動畫跑完。畫面上有燈籠動畫，所以不能用 pumpAndSettle。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  /// 用同樣的種子重建遊戲，得知牌的排列。從首頁進入的畫面用的是正式關卡，要傳 [levels]。
  MatchingGame mirror(int level, [List<Level> levelSet = testLevels]) =>
      MatchingGame(level: levelSet[level], random: Random(1));

  Future<void> solveOnScreen(WidgetTester tester, int level, {List<Level> levelSet = testLevels}) async {
    final g = mirror(level, levelSet);
    for (var i = 0; i < g.cards.length; i++) {
      if (g.isMatched[i]) continue;
      final j = pairOf(g, i);
      g.pick(i);
      g.pick(j);
      await tester.tap(find.byKey(ValueKey('card_$i')));
      await tester.tap(find.byKey(ValueKey('card_$j')));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 1100)); // 最後一組的特效放完才跳過關視窗
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('GameScreen', () {
    testWidgets('開局：南機場夜市 12 張蓋著的牌', (tester) async {
      await pumpGame(tester);
      expect(find.text('南機場夜市'), findsOneWidget);
      expect(find.text('第 1 攤・台北'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(12));
    });

    testWidgets('翻錯 0.7 秒後蓋回，時間每秒倒數', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
      await tester.tap(find.byKey(const ValueKey('card_0')));
      await tester.tap(find.byKey(ValueKey('card_${differentFrom(g, 0)}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('不一樣，連擊中斷'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(10));

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('夜'), findsNWidgets(12));
      expect(find.text('59'), findsOneWidget);
    });

    testWidgets('過關視窗：看廣告金幣 ×2 是黃色實心按鈕（有廣告標籤），前往下一攤是外框按鈕', (tester) async {
      await pumpGame(tester);
      await solveOnScreen(tester, 0);
      final ad = find.byKey(const ValueKey('dialog_ad'));
      expect(find.descendant(of: ad, matching: find.byType(FilledButton)), findsOneWidget, reason: '看廣告是主要按鈕');
      expect(find.descendant(of: ad, matching: find.text('廣告')), findsOneWidget, reason: '保留廣告標籤');
      expect(find.ancestor(of: find.text('前往下一攤：城隍廟夜市'), matching: find.byType(OutlinedButton)), findsOneWidget);
      expect(find.ancestor(of: find.text('前往下一攤：城隍廟夜市'), matching: find.byType(FilledButton)), findsNothing);
      expect(tester.getTopLeft(ad).dy, lessThan(tester.getTopLeft(find.text('前往下一攤：城隍廟夜市')).dy));

      await tester.tap(find.text('前往下一攤：城隍廟夜市'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('重玩沒破紀錄：不給金幣，也沒有看廣告金幣 ×2', (tester) async {
      await pumpGame(tester, saved: {'best_score_0': 99999});
      await solveOnScreen(tester, 0);
      expect(
          find.byWidgetPredicate((w) => w is CoinText && w.text.contains('沒有破紀錄（最高 99999 分），這次沒有金幣')), findsOneWidget);
      expect(find.byKey(const ValueKey('dialog_ad')), findsNothing, reason: '沒有金幣就不用看廣告加倍');
      expect(find.ancestor(of: find.text('前往下一攤：城隍廟夜市'), matching: find.byType(FilledButton)), findsOneWidget,
          reason: '沒有廣告時前往下一攤是黃色實心');
      await tester.tap(find.text('前往下一攤：城隍廟夜市'));
      await tester.pump();
      expect(store.coins, 0);
      expect(store.bestScore(0), 99999, reason: '最高分不變');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('重玩破紀錄：只用比之前多出來的分數換金幣；重置進度會清掉最高分', (tester) async {
      await pumpGame(tester, saved: {'best_score_0': 500});
      await solveOnScreen(tester, 0);
      final line =
          tester.widget<CoinText>(find.byWidgetPredicate((w) => w is CoinText && w.text.startsWith('新紀錄！總分'))).text;
      final numbers = RegExp(r'\d+').allMatches(line).map((m) => int.parse(m[0]!)).toList();
      final (score, gained, coins) = (numbers[0], numbers[1], numbers[2]);
      expect(gained, score - 500);
      expect(coins, (gained / 10).round());
      expect(find.byKey(const ValueKey('dialog_ad')), findsOneWidget);
      await tester.tap(find.text('前往下一攤：城隍廟夜市'));
      await tester.pump();
      expect(store.coins, coins);
      expect(store.bestScore(0), score);
      await tester.pump(const Duration(seconds: 3));

      await store.resetProgress();
      expect(store.bestScore(0), 0);
    });

    testWidgets('過關：金幣、解鎖、星數寫進存檔，可以直接前往下一攤', (tester) async {
      await pumpGame(tester);
      await solveOnScreen(tester, 0);
      expect(find.text('收攤！南機場夜市完成'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);

      await tester.tap(find.text('前往下一攤：城隍廟夜市'));
      await settle(tester);
      expect(find.text('城隍廟夜市'), findsOneWidget);
      expect(findCoinText('🪙 260'), findsOneWidget); // (2000 + 60 秒 × 10) / 10
      expect(find.text('夜'), findsNWidgets(16));
      expect(store.coins, 260);
      expect(store.unlocked, 2);
      expect(store.clears, 1);
      expect(store.bestStars(0), 3);
      expect(ads.rewardedShown, 0);
    });

    testWidgets('過關看廣告，金幣 ×2', (tester) async {
      await pumpGame(tester);
      await solveOnScreen(tester, 0);
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await settle(tester);
      expect(ads.rewardedShown, 1);
      expect(store.coins, 520);
      expect(findCoinText('🪙 520'), findsOneWidget);
    });

    testWidgets('第 3 次過關播插頁式廣告；看過獎勵型廣告的那次不播', (tester) async {
      await pumpGame(tester, saved: {'clears': 2});
      await solveOnScreen(tester, 0);
      await tester.tap(find.text('前往下一攤：城隍廟夜市'));
      await tester.pump();
      expect(ads.interstitialShown, 1);

      await tester.pumpWidget(const SizedBox()); // 清掉畫面，重新開一局
      await pumpGame(tester, saved: {'clears': 2});
      await solveOnScreen(tester, 0);
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      expect(ads.interstitialShown, 0);
    });

    testWidgets('看廣告偷看全部 2 秒，每局只能一次；播廣告時暫停音樂', (tester) async {
      await pumpGame(tester);
      await tester.tap(find.byKey(const ValueKey('peek')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ads.rewardedShown, 1);
      expect(sounds.musicEvents, ['pause', 'resume']);
      expect(find.text('夜'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('夜'), findsNWidgets(12));

      await tester.tap(find.byKey(const ValueKey('peek')));
      await tester.pump();
      expect(ads.rewardedShown, 1);
    });

    testWidgets('時間到看廣告 +15 秒繼續；廣告失敗會回到時間到視窗', (tester) async {
      await pumpGame(tester);
      await tester.pump(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('時間到了'), findsOneWidget);
      // 廣告維持原本的深黃字外框樣式、排第一個，其他兩個是黃色外框
      final adSide = tester
          .widget<OutlinedButton>(
              find.descendant(of: find.byKey(const ValueKey('dialog_ad')), matching: find.byType(OutlinedButton)))
          .style!
          .side!
          .resolve({})!;
      expect(adSide.color, const Color(0xFFA2580A), reason: '廣告按鈕是原本的深黃色');
      final adFill = tester
          .widget<OutlinedButton>(
              find.descendant(of: find.byKey(const ValueKey('dialog_ad')), matching: find.byType(OutlinedButton)))
          .style!
          .backgroundColor!
          .resolve({});
      expect(adFill, ResultDialog.adFill, reason: '廣告按鈕黃色底');
      for (final label in ['重新開始這一攤', '回到夜市列表']) {
        final button = find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton));
        expect(button, findsOneWidget, reason: label);
        final side = tester.widget<OutlinedButton>(button).style!.side!.resolve({})!;
        expect(side.color, NightColors.glow, reason: '$label 黃色外框');
        expect(tester.widget<Text>(find.text(label)).style, AdButton.adLabelStyle, reason: '$label 跟看廣告一樣的字');
      }
      final adTop = tester.getTopLeft(find.byKey(const ValueKey('dialog_ad'))).dy;
      expect(adTop, lessThan(tester.getTopLeft(find.text('重新開始這一攤')).dy), reason: '廣告排第一個');

      ads.rewardSucceeds = false;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('廣告目前無法播放，請稍後再試'), findsOneWidget);
      expect(find.text('時間到了'), findsOneWidget);

      ads.rewardSucceeds = true;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('時間到了'), findsNothing);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('多 15 秒，加油！'), findsOneWidget);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('時間到了'), findsOneWidget);
      expect(find.byKey(const ValueKey('dialog_ad')), findsNothing); // 每局只能一次
      expect(find.ancestor(of: find.text('重新開始這一攤'), matching: find.byType(FilledButton)), findsOneWidget,
          reason: '沒有廣告選項時，重新開始恢復成黃色實心');
      await tester.tap(find.text('重新開始這一攤'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3)); // 讓提示訊息計時結束
    });

    testWidgets('音效：翻牌、翻錯、配對、連擊、過關、金幣各自播放', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
      await tester.tap(find.byKey(const ValueKey('card_0')));
      await tester.tap(find.byKey(ValueKey('card_${differentFrom(g, 0)}')));
      await tester.pump(const Duration(seconds: 1));
      expect(sounds.played, [Sfx.flip, Sfx.miss]);

      sounds.played.clear();
      await solveOnScreen(tester, 0);
      expect(sounds.played.first, Sfx.flip);
      expect(sounds.played, contains(Sfx.match));
      expect(sounds.played, contains(Sfx.combo));
      expect(sounds.played.last, Sfx.win);

      await tester.tap(find.text('前往下一攤：城隍廟夜市'));
      await tester.pump();
      expect(sounds.played.last, Sfx.coin);
    });

    testWidgets('最難的大東夜市 24 張牌也能完整顯示', (tester) async {
      await pumpGame(tester, level: 5);
      expect(find.text('大東夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(24));
      for (var i = 0; i < 24; i++) {
        expect(tester.getRect(find.byKey(ValueKey('card_$i'))).bottom, lessThan(2556 / 3));
      }
    });

    testWidgets('道具列：使用沙漏加時間、扣數量，每局只能用一次', (tester) async {
      await pumpGame(tester, saved: {'item_hourglass': 2});
      await tester.tap(find.byKey(const ValueKey('item_hourglass')));
      await tester.pump();
      expect(find.text('70'), findsOneWidget);
      expect(store.itemCount(ItemType.hourglass), 1);
      expect(find.text('已用'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('item_hourglass')));
      await tester.pump();
      expect(store.itemCount(ItemType.hourglass), 1);
    });

    testWidgets('道具用完：可以看廣告領一個，倒數暫停', (tester) async {
      await pumpGame(tester);
      await tester.tap(find.byKey(const ValueKey('item_magnifier')));
      await settle(tester);
      expect(find.text('🔍 放大鏡用完了'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tapAndSettle(tester, find.byKey(const ValueKey('free_item')));
      expect(ads.rewardedShown, 1);
      expect(store.itemCount(ItemType.magnifier), 1);
      final time = int.parse(tester.widget<Text>(find.byKey(const ValueKey('time'))).data!);
      expect(time, greaterThanOrEqualTo(58));
      await tester.pump(const Duration(seconds: 3)); // 讓提示訊息計時結束
    });

    testWidgets('放大鏡配對一組，並收錄進圖鑑', (tester) async {
      await pumpGame(tester, saved: {'item_magnifier': 1});
      await tester.tap(find.byKey(const ValueKey('item_magnifier')));
      await settle(tester);
      expect(find.text('夜'), findsNWidgets(10));
      expect(store.discoveredFoods.length, 1);
      expect(find.textContaining('收錄圖鑑'), findsOneWidget);
    });

    testWidgets('裝備生效：帽子增加時間、算盤增加金幣', (tester) async {
      await pumpGame(tester, saved: {'gear_hat': 1, 'gear_abacus': 1});
      expect(find.text('62'), findsOneWidget);
      await solveOnScreen(tester, 0);
      // (2000 + 62 秒 × 10) / 10 × 1.1 = 288
      expect(findCoinText('總分 2620，獲得 🪙 288'), findsOneWidget);
    });

    testWidgets('過關時顯示新達成的成就，零失誤和圖鑑都有紀錄', (tester) async {
      await pumpGame(tester);
      await solveOnScreen(tester, 0);
      expect(find.text('🏆 成就達成：初逛夜市'), findsOneWidget);
      expect(find.text('🏆 成就達成：零失誤'), findsOneWidget);
      expect(find.text('🏆 成就達成：連擊高手'), findsOneWidget);
      expect(store.perfectRuns, 1);
      expect(store.discoveredFoods.length, 6);
    });

    testWidgets('配對特效：飄出分數和連擊，放完就消失，不擋住點牌', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
      final second = pairOf(g, 0);
      await tester.tap(find.byKey(const ValueKey('card_0')));
      await tester.tap(find.byKey(ValueKey('card_$second')));
      await tester.pump();
      expect(find.byType(MatchBurst), findsNWidgets(2));

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('+100'), findsOneWidget);

      // 第二組：連擊 2，特效進行中也能繼續點牌
      g.pick(0);
      g.pick(second);
      final next = List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j]);
      await tester.tap(find.byKey(ValueKey('card_$next')));
      await tester.tap(find.byKey(ValueKey('card_${pairOf(g, next)}')));
      await tester.pump();
      expect(find.byType(MatchBurst), findsNWidgets(4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('+200'), findsOneWidget);
      expect(find.text('2 連擊'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(find.byType(MatchBurst), findsNothing);
    });

    testWidgets('卡背：emoji 圖案放大，各種大小都不會超出卡背', (tester) async {
      for (final id in ['pokepoke', 'goldfish', 'tour']) {
        expect(skinById(id).markScale, greaterThan(1), reason: '$id 的圖案要放大');
      }
      expect(skinById('fortune').markScale, 1, reason: '文字卡背維持原本大小');
      for (final width in [36.0, 60.0, 110.0]) {
        for (final skin in cardSkins) {
          await tester.pumpWidget(MaterialApp(
            home:
                Center(child: SizedBox(width: width, height: width * 4 / 3, child: CardBack(skin: skin, width: width))),
          ));
          expect(tester.takeException(), isNull, reason: '${skin.id} 寬 $width');
          final mark = tester.getRect(find.text(skin.mark));
          final card = tester.getRect(find.byType(CardBack));
          expect(card.contains(mark.topLeft) && card.contains(mark.bottomRight - const Offset(0.01, 0.01)), isTrue,
              reason: '${skin.id} 寬 $width 的圖案在卡背裡面');
        }
      }
      // emoji 卡背的字級比文字卡背大
      await tester.pumpWidget(MaterialApp(home: CardBack(skin: skinById('pokepoke'), width: 100)));
      final boba = tester.widget<Text>(find.text('🎁')).style!.fontSize!;
      await tester.pumpWidget(MaterialApp(home: CardBack(skin: skinById('fortune'), width: 100)));
      final fortune = tester.widget<Text>(find.text('福')).style!.fontSize!;
      expect(boba, greaterThan(fortune));
    });

    testWidgets('重新開始：先確認，取消就繼續；確認後從頭開始', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
      final i = 0;
      final j = pairOf(g, i);
      await tester.tap(find.byKey(ValueKey('card_$i')));
      await tester.tap(find.byKey(ValueKey('card_$j')));
      await tester.pump(const Duration(milliseconds: 1100));
      String text(String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;
      expect(text('score'), '100');

      await tapAndSettle(tester, find.byKey(const ValueKey('restart')));
      expect(find.text('重新開始這一攤？'), findsOneWidget);
      final time = text('time');
      await tester.pump(const Duration(seconds: 3));
      await tapAndSettle(tester, find.text('繼續玩'));
      expect(text('score'), '100', reason: '取消就繼續這一局');
      // 視窗開了 3 秒；關掉視窗的 0.6 秒內恢復倒數可能剛好扣 1 秒，沒暫停的話會少 3 秒以上
      expect(int.parse(text('time')), greaterThanOrEqualTo(int.parse(time) - 1), reason: '確認視窗開著時不倒數');

      await tapAndSettle(tester, find.byKey(const ValueKey('restart')));
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_restart')));
      expect(text('score'), '0');
      expect(text('time'), '60');
      expect(tester.widget<CardWidget>(find.byKey(ValueKey('card_$i'))).isMatched, isFalse);
      expect(find.text('南機場夜市'), findsOneWidget, reason: '還是同一攤');
    });

    testWidgets('小螢幕：招牌上的夜市名稱和副標維持一行（多了重新開始按鈕也不會擠成直排）', (tester) async {
      await setUpStore(tester, const {'coins': 99999, 'unlocked': 18});
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      for (var i = 0; i < levels.length; i++) {
        await tester.pumpWidget(MaterialApp(
          // 每一攤給不同的 key，才會重新建立畫面（不然會沿用上一攤的狀態）
          home: GameScreen(
              key: ValueKey(i),
              levelIndex: i,
              store: store,
              ads: ads,
              sounds: sounds,
              random: Random(1),
              previewSeconds: 0),
        ));
        expect(tester.takeException(), isNull, reason: levels[i].name);
        expect(tester.getRect(find.text(levels[i].name)).height, lessThan(40), reason: '${levels[i].name} 一行');
        expect(tester.getRect(find.text('第 ${i + 1} 攤・${levels[i].city}')).height, lessThan(24));
      }
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
      expect(tester.takeException(), isNull, reason: '大胃王上方不跑版');
      expect(tester.getRect(find.byKey(const ValueKey('endless_progress'))).height, lessThan(30));
      expect(tester.getRect(find.byKey(const ValueKey('score'))).right, lessThanOrEqualTo(320), reason: '大分數不超出畫面');
      expect(find.byKey(const ValueKey('restart')), findsOneWidget);
    });

    testWidgets('正式關卡排版：牌少時固定欄數並置中，最多 20 張在小螢幕也放得下', (tester) async {
      await setUpStore(tester, const {'unlocked': 18});
      Future<void> open(int index) async {
        await tester.pumpWidget(MaterialApp(
          home: GameScreen(
              key: ValueKey(index), levelIndex: index, store: store, ads: ads, sounds: sounds, previewSeconds: 0),
        ));
        await tester.pump();
      }

      int columnsOnScreen() {
        final top = tester.getRect(find.byKey(const ValueKey('card_0'))).top;
        var n = 0;
        while (find.byKey(ValueKey('card_$n')).evaluate().isNotEmpty &&
            (tester.getRect(find.byKey(ValueKey('card_$n'))).top - top).abs() < 1) {
          n++;
        }
        return n;
      }

      final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      // 第 1 關 2 張、第 2 關 4 張、第 4 關 6 張、第 7 關 8 張、第 10 關 10 張
      for (final (index, cards, columns) in [(0, 2, 2), (1, 4, 2), (3, 6, 3), (6, 8, 4), (9, 10, 5)]) {
        await open(index);
        expect(find.byKey(ValueKey('card_${cards - 1}')), findsOneWidget, reason: '第 ${index + 1} 關');
        expect(find.byKey(ValueKey('card_$cards')), findsNothing);
        expect(columnsOnScreen(), columns, reason: '第 ${index + 1} 關欄數');
        final first = tester.getRect(find.byKey(const ValueKey('card_0')));
        final last = tester.getRect(find.byKey(ValueKey('card_${columns - 1}')));
        expect(first.width, lessThanOrEqualTo(110.5), reason: '牌少時卡片不要太大');
        expect(((first.left + last.right) / 2 - screenWidth / 2).abs(), lessThan(1), reason: '第 ${index + 1} 關置中');
      }

      // 最多 20 張的關卡在最小的螢幕上不跑版
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      await open(17);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 20; i++) {
        expect(tester.getRect(find.byKey(ValueKey('card_$i'))).bottom, lessThan(568), reason: '第 $i 張超出畫面');
      }
    });

    testWidgets('連續配對時，每組特效都會按時放完，不會因為前面的放完而重播', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
      for (var n = 0; n < 3; n++) {
        final i = List.generate(g.cards.length, (k) => k).firstWhere((k) => !g.isMatched[k]);
        final j = pairOf(g, i);
        g.pick(i);
        g.pick(j);
        await tester.tap(find.byKey(ValueKey('card_$i')));
        await tester.tap(find.byKey(ValueKey('card_$j')));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(MatchBurst), findsWidgets);
      // 每 0.1 秒畫一次，最後一組的特效 1 秒後就該放完
      for (var t = 0; t < 12; t++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MatchBurst), findsNothing);
    });

    testWidgets('手機開了減少動態效果就不放特效', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true, size: Size(393, 852)),
          child: GameScreen(
              levelIndex: 0,
              store: store,
              ads: ads,
              sounds: sounds,
              random: Random(1),
              previewSeconds: 0,
              levelList: testLevels),
        ),
      ));
      final g = mirror(0);
      await tester.tap(find.byKey(const ValueKey('card_0')));
      await tester.tap(find.byKey(ValueKey('card_${pairOf(g, 0)}')));
      await tester.pump();
      expect(find.text('夜'), findsNWidgets(10));
      expect(find.byType(MatchBurst), findsNothing);
    });

    testWidgets('小吃翻開時顯示專屬圖片而不是 emoji', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
      await tester.tap(find.byKey(const ValueKey('card_0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(ValueKey(g.cards[0].image!)), findsWidgets);
      expect(find.text(g.cards[0].emoji), findsNothing);
    });

    testWidgets('買了卡背後，牌桌用新卡背', (tester) async {
      await pumpGame(tester, saved: {
        'owned_skins': ['fortune'],
        'equipped_skin': 'fortune',
      });
      expect(find.text('福'), findsNWidgets(12));
      expect(find.text('夜'), findsNothing);
    });
  });

  group('畫面流程', () {
    group('拉霸數字', () {
      const style = TextStyle(fontSize: 40);
      Future<void> pumpNumber(WidgetTester tester, int value) =>
          tester.pumpWidget(MaterialApp(home: Center(child: RollingNumber(value: value, style: style))));
      List<(String, double)> glyphs(WidgetTester tester) => [
            for (final e in find.descendant(of: find.byType(RollingNumber), matching: find.byType(Text)).evaluate())
              ((e.widget as Text).data!, tester.getTopLeft(find.byWidget(e.widget)).dy),
          ];

      testWidgets('停下來時每一位剛好在新數字上', (tester) async {
        await pumpNumber(tester, 12800);
        await pumpNumber(tester, 13500);
        await tester.pump(const Duration(milliseconds: 300));
        expect(glyphs(tester).map((g) => g.$1).join(), isNot('13500'), reason: '還在滾');
        await tester.pump(const Duration(seconds: 2));
        expect(glyphs(tester).map((g) => g.$1).join(), '13500');
        final tops = glyphs(tester).map((g) => g.$2).toSet();
        expect(tops.length, 1, reason: '每一位都對齊停好');
      });

      testWidgets('滾到一半又加分：從當下的位置接著滾，不會跳格', (tester) async {
        await pumpNumber(tester, 12800);
        await pumpNumber(tester, 13500);
        await tester.pump(const Duration(milliseconds: 350));
        final before = glyphs(tester);
        await pumpNumber(tester, 14000);
        final after = glyphs(tester);
        expect(after.length, before.length);
        for (var i = 0; i < before.length; i++) {
          expect(after[i].$1, before[i].$1, reason: '同一格顯示的數字不變');
          expect(after[i].$2, closeTo(before[i].$2, 0.5), reason: '位置不會跳');
        }
        await tester.pump(const Duration(seconds: 2));
        expect(glyphs(tester).map((g) => g.$1).join(), '14000');
      });
    });

    testWidgets('成就：可以領取的置頂，還沒達成的在中間，已領取的放最下面；領完會移到下面', (tester) async {
      // 過關 1 次（初逛夜市，已經領過）、最高 5 連擊（連擊高手，可以領）、零失誤 1 次（零失誤，可以領）
      await setUpStore(tester, {
        'clears': 1,
        'stat_best_combo': 5,
        'stat_perfect_runs': 1,
        'ach_claimed': ['first_clear'],
      });
      List<String> ids() => AchievementsScreen.ordered(store).map((a) => a.id).toList();
      expect(ids().take(2), ['combo5', 'perfect'], reason: '可以領的在最上面，照原本順序');
      expect(ids().last, 'first_clear', reason: '已領取的在最下面');
      expect(ids().length, achievements.length);

      await tester.pumpWidget(MaterialApp(home: AchievementsScreen(store: store, sounds: sounds)));
      final first = tester.getTopLeft(find.byKey(const ValueKey('claim_combo5'))).dy;
      final second = tester.getTopLeft(find.byKey(const ValueKey('claim_perfect'))).dy;
      expect(first, lessThan(second));
      await tester.tap(find.byKey(const ValueKey('claim_combo5')));
      await tester.pump();
      expect(ids().first, 'perfect', reason: '領完的連擊高手移到下面');
      expect(ids().sublist(ids().length - 2), ['first_clear', 'combo5'], reason: '已領取的照原本順序排在最後');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('首頁：夜市走透透先進選擇夜市再開始，並顯示總星數和金幣', (tester) async {
      await pumpHome(tester, saved: {'unlocked': 2, 'coins': 123, 'stars_0': 3});
      expect(find.text('夜市翻牌'), findsOneWidget);
      expect(find.text('第 2 攤・城隍廟夜市'), findsOneWidget);
      expect(find.text('★ 3 / 54'), findsOneWidget);
      expect(findCoinText('🪙 123'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('coins')), matching: find.byType(CoinIcon)), findsOneWidget,
          reason: '金幣數用畫出來的金幣圖示');
      final rich = tester
          .widget<RichText>(find.descendant(of: find.byKey(const ValueKey('coins')), matching: find.byType(RichText)));
      expect(rich.text.toPlainText(), isNot(contains('🪙')), reason: '不再顯示 🪙 表情符號');

      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      expect(find.text('選擇夜市'), findsOneWidget, reason: '先進選擇夜市，不會直接開始');
      expect(find.text('夜'), findsNothing);
      await tapAndSettle(tester, find.byKey(const ValueKey('level_1')));
      expect(find.text('城隍廟夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(levels[1].pairs * 2));
    });

    testWidgets('首頁在小螢幕上不跑版，招牌卡片也放得下', (tester) async {
      for (final size in const [Size(640, 1136), Size(750, 1334), Size(1170, 2532)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = size.width > 1000 ? 3 : 2;
        await pumpHome(tester);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
        expect(find.text('珍珠奶茶'), findsOneWidget, reason: '$size 招牌卡片要顯示');
      }
      tester.view.reset();
    });

    testWidgets('首頁沒有選擇夜市的格子，6 格排成兩列三格', (tester) async {
      await pumpHome(tester);
      expect(find.byKey(const ValueKey('levels')), findsNothing);
      const keys = ['shop', 'daily', 'achievements', 'guide', 'howto', 'settings'];
      final rects = [for (final k in keys) tester.getRect(find.byKey(ValueKey(k)))];
      for (var i = 0; i < 3; i++) {
        expect(rects[i].top, rects[0].top, reason: '第一列：${keys[i]}');
        expect(rects[i + 3].top, rects[3].top, reason: '第二列：${keys[i + 3]}');
        expect(rects[i + 3].width, closeTo(rects[i].width, 0.5), reason: '兩列格子一樣寬');
      }
      expect(rects[3].top, greaterThan(rects[0].bottom));
    });

    testWidgets('玩法說明：兩種模式和道具都有說明，數值跟遊戲規則一致', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('howto')));
      expect(find.text('玩法說明'), findsOneWidget);
      for (final key in ['howto_basic', 'howto_tour', 'howto_endless']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.textContaining('每組得分 100 × 連擊（最高 ×5）'), findsOneWidget);
      expect(find.text('每一局開始時，所有卡牌會先翻開 $previewMemorizeSeconds 秒讓你記住位置，倒數結束蓋回去後才開始計時。'), findsOneWidget);
      expect(find.textContaining('金幣是分數 ÷ 200'), findsOneWidget);
      expect(find.textContaining('連續翻錯 2 次，老闆會偷偷亮出一組對子'), findsOneWidget);
      // 說明很長，清單是捲到才建立的，所以一段一段捲過去檢查
      await tester.scrollUntilVisible(find.byKey(const ValueKey('howto_items')), 300);
      for (final type in ItemType.values) {
        await tester.scrollUntilVisible(find.text('${type.emoji} ${type.label}：${type.description}'), 100);
      }
      await tester.scrollUntilVisible(find.textContaining('每升一級，每局時間 +2 秒'), 100);
      for (final gear in GearType.values) {
        await tester.scrollUntilVisible(find.textContaining('${gear.emoji} ${gear.label}'), 100);
      }
      await tester.scrollUntilVisible(find.byKey(const ValueKey('howto_more')), 300);
      expect(tester.takeException(), isNull);
    });

    testWidgets('玩法說明在小螢幕上不會跑版', (tester) async {
      await pumpHome(tester);
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      await tapAndSettle(tester, find.byKey(const ValueKey('howto')));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('howto_more')), 300);
      expect(tester.takeException(), isNull);
    });

    testWidgets('遊戲中按返回會先確認；選繼續玩就留下，選離開就回選擇夜市', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      await tapAndSettle(tester, find.byKey(const ValueKey('level_0')));

      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      expect(find.text('離開這一攤？'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // 確認視窗開著時不倒數
      await tapAndSettle(tester, find.text('繼續玩'));
      expect(find.text('南機場夜市'), findsOneWidget);
      final time = int.parse(tester.widget<Text>(find.byKey(const ValueKey('time'))).data!);
      expect(time, greaterThanOrEqualTo(levels[0].seconds - 2), reason: '確認視窗開著時不倒數');

      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_leave')));
      expect(find.text('選擇夜市'), findsOneWidget);
    });

    testWidgets('選擇夜市：上鎖的會提示，過關後回列表星數和解鎖會更新', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      expect(find.text('選擇夜市'), findsOneWidget);
      expect(find.text('南機場夜市・台北'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('level_1')));
      await tester.pump();
      expect(find.text('先通過「南機場夜市」才能解鎖'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('level_0')));
      await solveOnScreen(tester, 0, levelSet: levels); // 從首頁進來的是正式關卡
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_leave')));
      expect(find.text('選擇夜市'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('level_stars_0'))).data, '★★★');

      await tapAndSettle(tester, find.byKey(const ValueKey('level_1')));
      expect(find.text('城隍廟夜市'), findsOneWidget);
    });

    testWidgets('商店：卡背金幣不夠會提示，買了就換上，成就卡背不能買', (tester) async {
      final start = skinById('fortune').price + 100; // 買得起招財金，買不起夜空藍
      await pumpHome(tester, saved: {'coins': start});
      await tapAndSettle(tester, find.byKey(const ValueKey('shop')));
      expect(find.text('夜市商店'), findsOneWidget);
      await tapAndSettle(tester, find.text('卡背'));

      await tester.tap(find.byKey(const ValueKey('skin_starry'))); // 不夠
      await tester.pump();
      expect(findCoinText('金幣不夠，還差 🪙 ${skinById('starry').price - start}'), findsOneWidget);
      expect(store.coins, start);

      await tester.tap(find.byKey(const ValueKey('skin_fortune')));
      await tester.pump();
      expect(store.coins, 100);
      expect(store.equippedSkin, 'fortune');
      expect(sounds.played.last, Sfx.coin);

      await tester.pageBack();
      await settle(tester);
      expect(findCoinText('🪙 100'), findsOneWidget);
      expect(find.text('福'), findsNWidgets(2)); // 首頁扇形卡片的兩張卡背
    });

    testWidgets('商店：買道具、升級裝備', (tester) async {
      final hat = GearType.hat.costs;
      final start = ItemType.hourglass.price + hat[0] + 100;
      await pumpHome(tester, saved: {'coins': start});
      await tapAndSettle(tester, find.byKey(const ValueKey('shop')));

      await tester.tap(find.byKey(const ValueKey('buy_hourglass')));
      await tester.pump();
      expect(store.itemCount(ItemType.hourglass), 1);
      expect(store.coins, start - ItemType.hourglass.price);
      expect(find.text('沙漏（持有 1）'), findsOneWidget);

      await tapAndSettle(tester, find.text('裝備'));
      await tester.tap(find.byKey(const ValueKey('upgrade_hat')));
      await tester.pump();
      expect(store.gearLevel(GearType.hat), 1);
      expect(store.coins, 100);

      await tester.tap(find.byKey(const ValueKey('upgrade_hat'))); // 第二級不夠
      await tester.pump();
      expect(findCoinText('金幣不夠，還差 🪙 ${hat[1] - 100}'), findsOneWidget);
    });

    testWidgets('成就：達成會顯示紅點，領取後拿到金幣', (tester) async {
      await pumpHome(tester, saved: {'clears': 1});
      expect(find.byKey(const ValueKey('achievements_dot')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('achievements')));
      await tapAndSettle(tester, find.byKey(const ValueKey('claim_first_clear')));
      expect(store.coins, 50);
      expect(find.byKey(const ValueKey('claim_first_clear')), findsNothing);
      // 領完移到最下面
      await tester.scrollUntilVisible(find.text('已領取'), 300);
      expect(find.text('已領取'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(find.byKey(const ValueKey('achievements_dot')), findsNothing);
    });

    testWidgets('每日任務：簽到領金幣，今天不能再簽', (tester) async {
      await pumpHome(tester);
      expect(find.byKey(const ValueKey('daily_dot')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('daily')));
      await tapAndSettle(tester, find.byKey(const ValueKey('check_in')));
      expect(store.coins, 20);
      expect(find.text('今天已經簽到了'), findsOneWidget);
    });

    testWidgets('小吃圖鑑：未收錄顯示問號，收錄的可以看介紹', (tester) async {
      await pumpHome(tester, saved: {
        'foods': ['雞排'],
      });
      await tapAndSettle(tester, find.byKey(const ValueKey('guide')));
      expect(find.text('小吃圖鑑 1 / 20'), findsOneWidget);
      expect(find.text('尚未收錄'), findsWidgets);

      await tapAndSettle(tester, find.byKey(const ValueKey('food_0')));
      expect(find.textContaining('撒上胡椒鹽'), findsOneWidget);
    });

    testWidgets('設定：音樂和音效開關會存檔', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('settings')));

      await tester.tap(find.byKey(const ValueKey('music_switch')));
      await tester.pump();
      expect(store.musicOn, isFalse);
      expect(sounds.musicOn, isFalse);

      await tester.tap(find.byKey(const ValueKey('sfx_switch')));
      await tester.pump();
      expect(store.muted, isTrue);
      expect(sounds.muted, isTrue);
    });

    testWidgets('設定：重置進度要先確認，取消就不會清掉', (tester) async {
      await pumpHome(tester, saved: {'coins': 500, 'unlocked': 3});
      await tapAndSettle(tester, find.byKey(const ValueKey('settings')));

      await tapAndSettle(tester, find.byKey(const ValueKey('reset')));
      await tapAndSettle(tester, find.text('取消'));
      expect(store.coins, 500);

      await tapAndSettle(tester, find.byKey(const ValueKey('reset')));
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_reset')));
      expect(store.coins, 0);
      expect(store.unlocked, 1);
      expect(find.text('已重置遊戲進度'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('第 1 攤・南機場夜市'), findsOneWidget);
      expect(findCoinText('🪙 0'), findsOneWidget);
    });

    testWidgets('選擇夜市：打開時在最上面，18 攤可以捲動', (tester) async {
      await pumpHome(tester, saved: {'unlocked': 15});
      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      expect(find.text('南機場夜市・台北'), findsOneWidget, reason: '從第 1 攤開始，不會跳到中間');
      expect(find.text('六合夜市・高雄'), findsNothing);
      await tester.scrollUntilVisible(find.text('六合夜市・高雄'), 300);
      await settle(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('level_14')));
      expect(find.text('六合夜市'), findsOneWidget);
    });

    testWidgets('最後一攤士林夜市過關，顯示逛完所有夜市', (tester) async {
      await pumpGame(tester, saved: {'unlocked': 18}, level: 17);
      expect(find.text('士林夜市'), findsOneWidget);
      await solveOnScreen(tester, 17);
      expect(find.text('恭喜逛完所有夜市！'), findsOneWidget);
      expect(find.text('再玩一次'), findsOneWidget);
    });

    testWidgets('小螢幕（iPhone SE）：首頁和 24 張牌的關卡都不會跑版', (tester) async {
      await pumpHome(tester);
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await pumpGame(tester, level: 5);
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 24; i++) {
        final rect = tester.getRect(find.byKey(ValueKey('card_$i')));
        expect(rect.bottom, lessThan(667));
        expect(rect.width, greaterThan(36), reason: '卡片太小不好點');
      }
    });
  });

  group('開場動畫', () {
    /// 開場動畫，播完後進首頁。images 給空的，測試環境不讀圖片檔。
    Future<void> pumpSplash(WidgetTester tester, {Future<void>? loading}) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          loading: loading,
          images: const [],
          next: (_) => HomeScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
        ),
      ));
    }

    /// 載入完成後還有「開市囉！」停留一秒和淡入，等這段跑完。
    Future<void> finishTransition(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 1050));
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('載入很快時，動畫播完才進首頁', (tester) async {
      await pumpSplash(tester, loading: Future.value());
      expect(find.text('夜市翻牌'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.byKey(const ValueKey('start')), findsNothing, reason: '動畫還沒播完');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('開市囉！'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('開市囉！'), findsOneWidget, reason: '要停留約一秒');
      expect(find.byKey(const ValueKey('start')), findsNothing);
      await finishTransition(tester);
      expect(find.byKey(const ValueKey('start')), findsOneWidget);
      expect(find.byKey(const ValueKey('splash')), findsNothing);
    });

    testWidgets('載入比動畫慢時，停在準備中直到載入完成', (tester) async {
      final loading = Completer<void>();
      await pumpSplash(tester, loading: loading.future);
      await tester.pump(const Duration(milliseconds: 4000));
      expect(find.textContaining('攤位準備中'), findsOneWidget);
      expect(find.byKey(const ValueKey('start')), findsNothing);
      loading.complete();
      await tester.pump();
      await finishTransition(tester);
      expect(find.byKey(const ValueKey('start')), findsOneWidget);
    });

    testWidgets('載入卡住時，最多等 6 秒就進首頁', (tester) async {
      await pumpSplash(tester, loading: Completer<void>().future);
      await tester.pump(const Duration(milliseconds: 5900));
      expect(find.byKey(const ValueKey('start')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await finishTransition(tester);
      expect(find.byKey(const ValueKey('start')), findsOneWidget);
    });

    testWidgets('載入失敗也照樣進首頁', (tester) async {
      final loading = Completer<void>();
      await pumpSplash(tester, loading: loading.future);
      loading.completeError(Exception('音效壞了'));
      await tester.pump(const Duration(milliseconds: 2500));
      await finishTransition(tester);
      expect(find.byKey(const ValueKey('start')), findsOneWidget);
    });

    testWidgets('開啟減少動態效果時直接顯示完整畫面', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SplashScreen(images: const [], next: (_) => const SizedBox()),
        ),
      ));
      await tester.pump();
      expect(find.text('夜市翻牌'), findsOneWidget);
      expect(find.textContaining('攤位準備中'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('小螢幕也不會超出畫面', (tester) async {
      await pumpSplash(tester, loading: Future.value());
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      for (var ms = 0; ms < 2400; ms += 300) {
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '第 $ms 毫秒');
      }
      await finishTransition(tester);
    });
  });

  group('夜市大胃王', () {
    /// 直接打開夜市大胃王（不翻牌，方便測試）。
    Future<void> pumpEndless(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
      await setUpStore(tester, saved);
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
    }

    String textOf(WidgetTester tester, String key) => endlessText(tester, key);
    Finder spots() => find
        .byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('spot_'));

    testWidgets('首頁可以進入夜市大胃王：沒有時間那一格，開局只上 2 張，桌子 20 格', (tester) async {
      await pumpHome(tester);
      expect(find.text('無盡挑戰，吃越多分越高'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      expect(textOf(tester, 'score'), '0', reason: '大大的分數');
      expect(textOf(tester, 'combo'), '×1 連擊');
      expect(tableOnScreen(tester).length, 2);
      expect(spots(), findsNWidgets(18), reason: '其他 18 格是空位');
      expect(find.byKey(const ValueKey('time')), findsNothing, reason: '沒有時間限制');
      expect(textOf(tester, 'table_count'), '2/20');
      expect(textOf(tester, 'next_serve'), '再翻 5 次上菜');
      expect(textOf(tester, 'endless_progress'), '0', reason: '最上面 👑 最高分');
    });

    testWidgets('牌桌上下有空間時牌拉長填滿（最多 3:2），小螢幕不會因此變小', (tester) async {
      for (final size in const [Size(1179, 2556), Size(750, 1334)]) {
        await pumpEndless(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = size.width > 1000 ? 3 : 2;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final card = tester.getSize(find.byKey(ValueKey('card_${tableOnScreen(tester).keys.first}')));
        expect(card.height / card.width, inInclusiveRange(4 / 3 - 0.01, EndlessScreenState.maxCardAspect + 0.01),
            reason: '$size 比例');
        if (size.width > 1000) expect(card.height / card.width, greaterThan(4 / 3 + 0.05), reason: '大螢幕上下有空間，牌拉長');
        final board = tester.getRect(find.byKey(const ValueKey('board')));
        final message = tester.getRect(find.byKey(const ValueKey('message')));
        if (card.height / card.width < EndlessScreenState.maxCardAspect - 0.01) {
          expect(message.top - board.bottom, lessThan(20), reason: '$size 還沒拉到最長，代表上下已經填滿');
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('全部吃光：+500、煙火，沒有過場，相撞完新的一波 2 組直接上桌', (tester) async {
      await pumpEndless(tester);
      await tapEndlessPair(tester);
      expect(textOf(tester, 'score'), '0', reason: '加分數字還沒飛到，總分還沒變');
      await tester.pump(const Duration(milliseconds: 950));
      expect(sounds.played.last, Sfx.win);
      expect(tableOnScreen(tester).length, 4, reason: '相撞完就上第 2 波 2 組');
      expect(textOf(tester, 'table_count'), '4/20');
      expect(find.text('全部吃光 +500！繼續吃'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview_hint')), findsNothing, reason: '不顯示提示框');
      // 煙火一發一發在牌桌各處炸開
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MatchBurst).evaluate().length, greaterThanOrEqualTo(6));
      expect(find.byWidgetPredicate((w) => w is CardWidget && w.key != null && w.isShow).evaluate(), isEmpty,
          reason: '沒有翻牌記憶時直接蓋著');
      await tester.pump(const Duration(seconds: 1));
      expect(textOf(tester, 'score'), '600', reason: '+100 和吃光的 +500 都飛到了');
    });

    testWidgets('加分數字從相撞的地方飛向總分，撞上去才加分，總分像拉霸一樣從個位數開始滾', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester);
      expect(textOf(tester, 'score'), '600');
      final scoreCenter = tester.getCenter(find.byKey(const ValueKey('score')));
      final combo = int.parse(RegExp(r'×(\d+)').firstMatch(textOf(tester, 'combo'))![1]!);
      await tapEndlessPair(tester);
      await tester.pump(const Duration(milliseconds: 600)); // 相撞，數字冒出來
      final label = find.text('+${100 * combo}');
      expect(label, findsOneWidget);
      final y0 = tester.getCenter(label).dy;
      await tester.pump(const Duration(milliseconds: 400));
      final y1 = tester.getCenter(label).dy;
      expect(y1, lessThan(y0), reason: '往上飛');
      expect((tester.getCenter(label) - scoreCenter).distance,
          lessThan((Offset(0, y0) - scoreCenter).distance.abs() + 400));
      expect(textOf(tester, 'score'), '600', reason: '還沒撞到');
      await tester.pump(const Duration(milliseconds: 300));
      expect(label, findsNothing, reason: '撞到總分就消失');
      expect(textOf(tester, 'score'), '${600 + 100 * combo}');

      // 拉霸：個位數先滾、高位數晚一點才開始滾
      final rolling = find.descendant(of: find.byKey(const ValueKey('score')), matching: find.byType(ClipRect));
      expect(rolling, findsNWidgets('${600 + 100 * combo}'.length), reason: '每一位一格');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('配對：兩張牌浮起來往中間飛、相撞後才放特效，原本的位置變回空位', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester); // 吃光第 1 波，桌上有 2 組
      final (a, b) = pairOnScreen(tester);
      final startA = tester.getCenter(find.byKey(ValueKey('card_$a')));
      final startB = tester.getCenter(find.byKey(ValueKey('card_$b')));
      final mid = (startA + startB) / 2;
      final points = '+${100 * int.parse(RegExp(r'×(\d+)').firstMatch(textOf(tester, 'combo'))![1]!)}';
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      await tester.pump();

      final fly = find.byKey(const ValueKey('merge_fly'));
      final flying = find.descendant(of: fly, matching: find.byType(CardWidget));
      double gap() => (tester.getCenter(flying.at(0)) - tester.getCenter(flying.at(1))).distance;

      expect(fly, findsOneWidget);
      expect(flying, findsNWidgets(2));
      expect(find.byKey(ValueKey('spot_$a')), findsOneWidget, reason: '原本的格子變空位，不會同時畫兩張');
      final startGap = gap();

      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getCenter(flying.at(0)).dy, lessThan(startA.dy), reason: '先浮起來');
      expect(find.text(points), findsNothing);

      await tester.pump(const Duration(milliseconds: 330));
      expect(gap(), lessThan(startGap * 0.5));
      expect(
          find.descendant(of: fly, matching: find.byType(Transform)).evaluate().every((e) {
            final m = (e.widget as Transform).transform;
            return m.entry(0, 1).abs() < 1e-9 && m.entry(1, 0).abs() < 1e-9;
          }),
          isTrue,
          reason: '飛行中沒有旋轉');

      await tester.pump(const Duration(milliseconds: 100));
      expect(gap(), lessThan(1), reason: '兩張重疊');
      expect((tester.getCenter(flying.at(0)) - mid).distance, lessThan(14));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(points), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(fly, findsNothing);
      expect(find.byKey(ValueKey('spot_$a')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
    });

    testWidgets('減少動態效果時不飛不撞，配對的牌直接消失；吃光照樣上下一波', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
        ),
      ));
      final (a, _) = pairOnScreen(tester);
      await tapEndlessPair(tester);
      expect(find.byKey(const ValueKey('merge_fly')), findsNothing);
      expect(find.byKey(ValueKey('spot_$a')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(tableOnScreen(tester).length, 4);
      expect(find.byKey(const ValueKey('merge_fly')), findsNothing);
    });

    testWidgets('翻錯：提示再錯幾次老闆就加菜，第 3 次加一組蓋著的菜', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester);
      await missEndlessPair(tester);
      expect(find.textContaining('翻錯了！再錯 2 次老闆就加菜'), findsOneWidget);
      expect(tableOnScreen(tester).length, 4, reason: '還沒加菜');
      expect(textOf(tester, 'combo'), '×1 連擊');
      await missEndlessPair(tester); // 連錯 2 次，訊息會換成老闆提示
      expect(tableOnScreen(tester).length, 4, reason: '翻錯 2 次還不加菜');
      await missEndlessPair(tester);
      expect(find.textContaining('翻錯 3 次，老闆加菜！'), findsOneWidget);
      final count = tableOnScreen(tester).length;
      expect(count, greaterThanOrEqualTo(6), reason: '4 張 + 老闆加的一組');
      expect(textOf(tester, 'table_count'), '$count/20');
      expect(find.byWidgetPredicate((w) => w is CardWidget && w.key != null && w.isShow).evaluate(), isEmpty,
          reason: '新菜是蓋著的，翻錯的牌也蓋回去了');
    });

    testWidgets('上菜：每翻幾次老闆就上一組，「再翻 N 次上菜」和桌面張數跟著變', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester);
      final serves = <String>[textOf(tester, 'next_serve')];
      for (var i = 0; i < 6; i++) {
        await eatEndlessPair(tester);
        serves.add(textOf(tester, 'next_serve'));
        expect(textOf(tester, 'table_count'), '${tableOnScreen(tester).length}/20');
      }
      expect(serves.toSet().length, greaterThan(1), reason: '倒數會變');
      expect(serves.every((s) => RegExp(r'^再翻 [1-5] 次上菜$').hasMatch(s)), isTrue, reason: '$serves');
    });

    testWidgets('連錯兩次：老闆亮出一組對子，過一下再蓋回去', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester);
      await missEndlessPair(tester);
      final (a, b) = mismatchOnScreen(tester)!;
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('老闆偷偷告訴你：這兩張是一對！'), findsOneWidget);
      final shown = [
        for (final e in find.byWidgetPredicate((w) => w is CardWidget && w.key != null && w.isShow).evaluate())
          e.widget as CardWidget
      ];
      expect(shown.length, 2);
      expect(shown[0].food, shown[1].food, reason: '亮出來的是一對');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.byWidgetPredicate((w) => w is CardWidget && w.key != null && w.isShow).evaluate(), isEmpty,
          reason: '提示結束蓋回去');
    });

    testWidgets('大胃王時間：連續配對 5 組開始，接下來分數 ×2，連擊格發光', (tester) async {
      await pumpEndless(tester);
      for (var i = 0; i < 4; i++) {
        await eatEndlessPair(tester);
      }
      await tapEndlessPair(tester); // 第 5 組
      expect(find.text('大胃王時間！接下來 5 組分數 ×2'), findsOneWidget);
      await settleEndlessEat(tester);
      expect(textOf(tester, 'combo'), contains('大胃王時間 ×2'));
      expect(textOf(tester, 'combo'), contains('剩 5 組'));
      final combo = int.parse(RegExp(r'(\d+) 連擊').firstMatch(textOf(tester, 'combo'))![1]!);
      final before = int.parse(textOf(tester, 'score'));
      await tapEndlessPair(tester); // 第 6 組：分數加倍
      expect(find.textContaining('大胃王時間 $combo 連擊 +${100 * combo * 2}'), findsOneWidget);
      await settleEndlessEat(tester);
      final gained = int.parse(textOf(tester, 'score')) - before;
      expect(gained == 100 * combo * 2 || gained > 100 * combo * 2, isTrue, reason: '加倍（吃光的話再加獎勵）');
      expect(textOf(tester, 'combo'), contains('剩 4 組'));
    });

    testWidgets('桌子塞滿：先停一下看滿桌，再跳出結算；破紀錄存最高分，按再吃一輪才發金幣', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester); // 600 分
      await fillEndlessTable(tester, showDialog: false);
      expect(textOf(tester, 'table_count'), '20/20');
      expect(find.text('新紀錄！吃飽收攤'), findsNothing, reason: '先停一下讓玩家看到滿桌');
      await tester.pump(EndlessScreenState.fullPause);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('新紀錄！吃飽收攤'), findsOneWidget);
      expect(find.text('吃了 1 組，最高 1 連擊'), findsOneWidget);
      expect(find.text('全部吃光 1 次'), findsOneWidget);
      expect(find.text('總分 600'), findsOneWidget);
      expect(find.text('刷新最高分！（原本 0）'), findsOneWidget);
      expect(findCoinText('獲得 🪙 3'), findsOneWidget, reason: '600 分 ÷ 200');
      expect(store.endlessBest, 600, reason: '塞滿就先存最高分');
      expect(store.coins, 0, reason: '還沒決定要不要吃胃藥，先不發金幣');
      expect(sounds.played, contains(Sfx.lose));

      await tapAndSettle(tester, find.text('再吃一輪'));
      expect(store.coins, 3);
      expect(textOf(tester, 'score'), '0');
      expect(textOf(tester, 'table_count'), '2/20');
      expect(textOf(tester, 'endless_progress'), '600');
    });

    testWidgets('沒破紀錄時顯示原本的最高分', (tester) async {
      await pumpEndless(tester, saved: {'endless_best_score': 5000});
      await fillEndlessTable(tester);
      expect(find.text('吃飽收攤'), findsOneWidget);
      expect(find.descendant(of: find.byType(ResultDialog), matching: find.text('最高分 5000')), findsOneWidget);
      expect(store.endlessBest, 5000);
    });

    testWidgets('看廣告吃胃藥：收掉 10 張繼續；廣告失敗回到結算；最後才發一次金幣', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);

      expect(find.text('看廣告吃胃藥，收掉 10 張'), findsOneWidget);
      // 廣告維持原本的深黃字外框樣式，再吃一輪、回到首頁是黃色外框
      for (final label in ['再吃一輪', '回到首頁']) {
        expect(find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)), findsOneWidget,
            reason: label);
        expect(tester.widget<Text>(find.text(label)).style, AdButton.adLabelStyle, reason: '$label 跟看廣告一樣的字');
      }

      ads.rewardSucceeds = false;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('廣告目前無法播放，請稍後再試'), findsOneWidget);
      expect(find.text('新紀錄！吃飽收攤'), findsOneWidget);

      ads.rewardSucceeds = true;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('新紀錄！吃飽收攤'), findsNothing);
      expect(textOf(tester, 'table_count'), '10/20');
      expect(tableOnScreen(tester).length, 10);
      expect(find.text('吃了胃藥，桌上收掉 10 張，繼續吃！'), findsOneWidget);
      expect(store.coins, 0);

      await fillEndlessTable(tester);
      expect(find.byKey(const ValueKey('dialog_ad')), findsNothing, reason: '胃藥每輪一次');
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_leave')));
      expect(store.coins, 3, reason: '600 分 ÷ 200，只發一次');
      expect(find.text('最高分 600'), findsOneWidget, reason: '首頁入口顯示最高分');
    });

    testWidgets('結算視窗顯示新達成的成就；吃胃藥和廣告失敗都只算一輪', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);
      expect(find.text('🏆 成就達成：開吃！'), findsOneWidget);
      expect(find.text('🏆 成就達成：吃飽飽'), findsNothing, reason: '還不到 50000 分');
      expect(store.endlessRounds, 1);
      expect(store.endlessBestMatches, 1);

      ads.rewardSucceeds = false;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.endlessRounds, 1, reason: '廣告失敗重開結算視窗不能多算一輪');

      ads.rewardSucceeds = true;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);
      expect(store.endlessRounds, 1, reason: '吃胃藥後再結算還是同一輪');
      expect(store.endlessBestMatches, 2);
      expect(find.textContaining('🏆 成就達成'), findsOneWidget, reason: '開吃！還是這一輪新達成的');

      await tapAndSettle(tester, find.text('再吃一輪'));
      await fillEndlessTable(tester);
      expect(store.endlessRounds, 2);
      expect(find.textContaining('🏆 成就達成'), findsNothing, reason: '已經達成過的不再顯示');
    });

    testWidgets('重新開始：確認後回到開局，分數和金幣都不保存', (tester) async {
      await pumpEndless(tester);
      await eatEndlessPair(tester);
      expect(textOf(tester, 'endless_progress'), '600');
      await tapAndSettle(tester, find.byKey(const ValueKey('restart')));
      expect(find.text('重新開始這一輪？'), findsOneWidget);
      await tapAndSettle(tester, find.text('繼續吃'));
      expect(textOf(tester, 'score'), '600', reason: '取消就繼續這一輪');

      await tapAndSettle(tester, find.byKey(const ValueKey('restart')));
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_restart')));
      expect(textOf(tester, 'score'), '0');
      expect(textOf(tester, 'table_count'), '2/20');
      expect(textOf(tester, 'endless_progress'), '0');
      expect(store.endlessBest, 0);
      expect(store.coins, 0);
    });

    testWidgets('中途離開要確認，分數和金幣都不保存', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      await eatEndlessPair(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      expect(find.text('不吃了嗎？'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_leave')));
      expect(find.byKey(const ValueKey('endless')), findsOneWidget);
      expect(store.endlessBest, 0);
      expect(store.coins, 0);
    });

    testWidgets('沙漏在大胃王不能用，顯示「走透透用」', (tester) async {
      await pumpEndless(tester, saved: {'item_hourglass': 3});
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('item_hourglass'))).onTap, isNull);
      expect(find.text('走透透用'), findsOneWidget);
    });

    testWidgets('小螢幕不會跑版：開局 2 張和塞滿 20 張', (tester) async {
      for (final size in const [Size(640, 1136), Size(750, 1334)]) {
        await pumpEndless(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400)); // 上桌動畫
        expect(tester.takeException(), isNull, reason: '$size 開局');
        await fillEndlessTable(tester, showDialog: false);
        expect(tester.takeException(), isNull, reason: '$size 塞滿');
        final items = tester.getRect(find.byKey(const ValueKey('peek')));
        for (final i in tableOnScreen(tester).keys) {
          final rect = tester.getRect(find.byKey(ValueKey('card_$i')));
          expect(rect.bottom, lessThan(items.top), reason: '$size 第 $i 張壓到道具列');
          expect(rect.right, lessThanOrEqualTo(size.width / 2), reason: '$size 第 $i 張超出畫面');
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('開局翻牌', () {
    bool allFaceUp(WidgetTester tester, int count) => [
          for (var i = 0; i < count; i++) tester.widget<CardWidget>(find.byKey(ValueKey('card_$i'))).isShow
        ].every((up) => up);
    bool anyFaceUp(WidgetTester tester, int count) => [
          for (var i = 0; i < count; i++) tester.widget<CardWidget>(find.byKey(ValueKey('card_$i'))).isShow
        ].any((up) => up);
    String timeText(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('time'))).data!;
    String countdown(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('preview_seconds'))).data!;
    final hint = find.byKey(const ValueKey('preview_hint'));
    const seconds = previewMemorizeSeconds;

    Future<void> pumpLevel(WidgetTester tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home:
            GameScreen(levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1), levelList: testLevels),
      ));
    }

    testWidgets('走透透：一開局就全部翻開，提示框倒數 $seconds 秒，蓋回去才開始計時', (tester) async {
      await pumpLevel(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(allFaceUp(tester, 12), isTrue, reason: '一開局就翻開');
      expect(hint, findsOneWidget);
      expect(find.text('記住所有卡牌！'), findsOneWidget);
      expect(find.byKey(const ValueKey('time')), findsOneWidget, reason: '時間列照常顯示');
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('peek'))).onTap, isNull, reason: '翻牌中不能偷看');

      // 點牌沒反應；倒數 5、4、3、2、1，每秒跳一次
      await tester.tap(find.byKey(const ValueKey('card_0')), warnIfMissed: false);
      for (var n = seconds; n >= 1; n--) {
        expect(countdown(tester), '$n');
        expect(allFaceUp(tester, 12), isTrue);
        expect(timeText(tester), '60', reason: '倒數期間不扣時間');
        if (n > 1) await tester.pump(const Duration(seconds: 1));
      }

      // 倒數結束：蓋牌、提示框消失、開始計時，再過 1 秒才扣第一秒
      await tester.pump(const Duration(milliseconds: 600));
      expect(anyFaceUp(tester, 12), isFalse);
      expect(hint, findsNothing);
      expect(find.text('翻兩張一樣的小吃就能配對'), findsOneWidget);
      expect(timeText(tester), '60');
      await tester.pump(const Duration(seconds: 1));
      expect(timeText(tester), '59');
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('peek'))).onTap, isNotNull, reason: '偷看還能用');
    });

    testWidgets('音效：記牌時每秒「叩」一聲，最後 $hurrySeconds 秒時鐘「滴、答」交替', (tester) async {
      await pumpLevel(tester);
      int count(Sfx sfx) => sounds.played.where((s) => s == sfx).length;
      expect(count(Sfx.countdown), 1, reason: '一開局顯示 5 就叩一聲');
      for (var n = 2; n <= seconds; n++) {
        await tester.pump(const Duration(seconds: 1));
        expect(count(Sfx.countdown), n);
      }
      await tester.pump(const Duration(seconds: 1)); // 蓋牌，不再叩
      expect(count(Sfx.countdown), seconds);
      List<Sfx> ticks() => sounds.played.where((s) => s == Sfx.hurry || s == Sfx.hurryTock).toList();
      expect(ticks(), isEmpty);

      // 60 秒倒數到剩 6 秒都不響；剩 5、4、3、2、1 滴答交替，時間到改播結束音效
      await tester.pump(const Duration(seconds: 54));
      expect(timeText(tester), '6');
      expect(ticks(), isEmpty);
      await tester.pump(const Duration(seconds: hurrySeconds));
      expect(ticks(), [Sfx.hurry, Sfx.hurryTock, Sfx.hurry, Sfx.hurryTock, Sfx.hurry]);
      await tester.pump(const Duration(seconds: 1));
      expect(ticks().length, hurrySeconds);
      expect(sounds.played.last, Sfx.lose);
      expect(count(Sfx.countdown), seconds, reason: '倒數音效只在記牌時播');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('大胃王：提示框在牌桌正中央、半透明，牌不會移位', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      final board = tester.getRect(find.byKey(const ValueKey('board')));
      expect((tester.getRect(hint).center - board.center).distance, lessThan(2), reason: '提示框置中在牌桌上');
      expect(tester.getRect(hint).width, lessThan(board.width), reason: '框比牌桌小');
      final box = tester.widget<Container>(hint).decoration! as BoxDecoration;
      expect(box.color!.a, lessThan(0.7), reason: '半透明，看得到底下的牌');
      final before = {
        for (final i in tableOnScreen(tester).keys) i: tester.getRect(find.byKey(ValueKey('card_$i'))),
      };

      await tester.pump(const Duration(seconds: 3));
      expect(hint, findsNothing);
      for (final MapEntry(key: i, value: rect) in before.entries) {
        expect(tester.getRect(find.byKey(ValueKey('card_$i'))), rect);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('翻牌中按返回，倒數會停住', (tester) async {
      await pumpLevel(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(countdown(tester), '${seconds - 1}');
      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      await tester.pump(const Duration(seconds: seconds + 2));
      await tapAndSettle(tester, find.text('繼續玩'));
      // 沒暫停的話早就倒數完了；關視窗的 0.6 秒內可能剛好跳一秒，所以不寫死數字
      expect(hint, findsOneWidget, reason: '確認視窗開著時不倒數');
      expect(allFaceUp(tester, 12), isTrue);
      await tester.pump(const Duration(seconds: seconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(anyFaceUp(tester, 12), isFalse);
    });

    testWidgets('大胃王：開局翻開倒數 2 秒；吃光後新的一波只翻開 1 秒；吃胃藥不翻，再吃一輪會重來', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      bool shown(int i) => tester.widget<CardWidget>(find.byKey(ValueKey('card_$i'))).isShow;
      bool allUp() => tableOnScreen(tester).keys.every(shown);
      bool anyUp() => tableOnScreen(tester).keys.any(shown);

      await tester.pump(const Duration(milliseconds: 400));
      expect(allUp(), isTrue);
      expect(countdown(tester), '${EndlessScreenState.wavePreviewSeconds(1)}');
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('peek'))).onTap, isNull, reason: '翻牌中不能偷看');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(anyUp(), isFalse);

      // 吃光：下一波直接上桌，翻開 1 秒就蓋回去，不顯示提示框
      await eatEndlessPair(tester);
      expect(tableOnScreen(tester).length, 4);
      expect(hint, findsNothing, reason: '吃光後不顯示提示框');
      expect(allUp(), isTrue);
      expect(find.text('全部吃光 +500！記住新的牌'), findsOneWidget);
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('peek'))).onTap, isNull, reason: '翻開中不能偷看');
      await tester.pump(const Duration(milliseconds: 700)); // 上桌後 1 秒
      await tester.pump(const Duration(milliseconds: 400));
      expect(anyUp(), isFalse, reason: '1 秒後蓋回去');
      expect(find.text('開吃！'), findsOneWidget);

      // 塞滿後吃胃藥：同一輪，不再翻牌
      await fillEndlessTable(tester);
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(anyUp(), isFalse, reason: '吃胃藥是同一輪，不再翻牌');

      // 再吃一輪：重新翻牌倒數
      await fillEndlessTable(tester);
      await tester.tap(find.text('再吃一輪'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsOneWidget);
      expect(allUp(), isTrue);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('老花眼鏡：開局翻牌記憶的倒數變長', (tester) async {
      await setUpStore(tester, const {'gear_glasses': 2});
      await tester.pumpWidget(MaterialApp(
        home:
            GameScreen(levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1), levelList: testLevels),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(countdown(tester), '${seconds + 2}');
      await tester.pump(const Duration(seconds: seconds + 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
    });

    testWidgets('提示框在小螢幕上不會跑版', (tester) async {
      await setUpStore(tester, const {});
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(levelIndex: 17, store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: seconds + 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('儲值', () {
    Future<void> pumpShop(WidgetTester tester,
        {Map<String, Object> saved = const {}, PurchaseService? purchases, int tab = ShopScreen.topUpTab}) async {
      await setUpStore(tester, saved);
      await tester.pumpWidget(MaterialApp(
        home: ShopScreen(
          store: store,
          sounds: sounds,
          purchases: purchases ?? DevPurchaseService(enabled: true),
          initialTab: tab,
        ),
      ));
      await tester.pump();
    }

    /// 捲到最下面的「恢復購買」。儲值清單在左右滑動的分頁裡，要指定捲上下方向的那一層；
    /// 清單是捲到才建立的，所以不能用 ensureVisible。
    Future<void> scrollToRestore(WidgetTester tester) async {
      final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('restore')), 200, scrollable: vertical.last);
      await tester.pump();
    }

    testWidgets('月卡：商店最上面可以買，買了到每日任務領，商店顯示剩幾天、超過 30 天不能續購', (tester) async {
      await pumpShop(tester);
      expect(find.byKey(const ValueKey('month_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('month_card_days')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('buy_month_card')));
      await tester.pump();
      expect(store.coins, monthCardInstantCoins);
      expect(store.monthCardDaysLeft, monthCardDays);
      expect(sounds.played.last, Sfx.coin);
      expect(find.text('月卡剩 30 天，現在續購會接在後面'), findsOneWidget);

      // 續購一次變 60 天，按鈕關掉
      await tester.tap(find.byKey(const ValueKey('buy_month_card')));
      await tester.pump();
      expect(store.monthCardDaysLeft, monthCardDays * 2);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('buy_month_card'))).onPressed, isNull);
      await tester.pump(const Duration(seconds: 4));

      // 每日任務最上面可以領，領完顯示今天已領
      await tester.pumpWidget(MaterialApp(home: DailyScreen(store: store, sounds: sounds)));
      expect(find.byKey(const ValueKey('daily_month_card')), findsOneWidget);
      final before = store.coins;
      await tester.tap(find.byKey(const ValueKey('claim_month_card')));
      await tester.pump();
      expect(store.coins, before + monthCardDailyCoins);
      expect(find.text('今天已領'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('月卡：沒有月卡時每日任務不顯示月卡；付款取消不會給金幣', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(home: DailyScreen(store: store, sounds: sounds)));
      expect(find.byKey(const ValueKey('daily_month_card')), findsNothing);

      final result = await buyMonthCard(_CancelPurchases(), store);
      expect(result, PurchaseResult.cancelled);
      expect(store.coins, 0);
      expect(store.monthCardActive, isFalse);
    });

    test('六種方案由小到大，買越多送越多，最多多送約 15%', () {
      expect(coinPacks.length, 6);
      expect(coinPacks.map((p) => p.id).toSet().length, 6);
      expect(coinPacks.map((p) => p.name).toSet().length, 6);
      for (var i = 1; i < coinPacks.length; i++) {
        expect(coinPacks[i].priceNtd, greaterThan(coinPacks[i - 1].priceNtd));
        expect(coinPacks[i].bonus, greaterThanOrEqualTo(coinPacks[i - 1].bonus), reason: coinPacks[i].name);
      }
      expect(coinPacks.first.bonus, 0);
      expect(coinPacks.last.bonus, lessThanOrEqualTo(0.16));
      expect(coinPacks.map((p) => p.priceLabel), ['NT\$30', 'NT\$90', 'NT\$170', 'NT\$330', 'NT\$590', 'NT\$990']);
      expect(removeAdsPriceNtd, 180);
    });

    testWidgets('首頁金幣旁的＋打開商店的儲值分頁', (tester) async {
      await pumpHome(tester);
      expect(find.byKey(const ValueKey('top_up')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('top_up')), matching: find.byKey(const ValueKey('coins'))),
          findsOneWidget,
          reason: '金幣數字在膠囊裡');
      await tapAndSettle(tester, find.byKey(const ValueKey('top_up')));
      expect(find.text('夜市商店'), findsOneWidget);
      expect(find.text('永久移除廣告'), findsOneWidget);
      expect(find.text('一把零錢'), findsOneWidget);
      final firstPack = find.ancestor(of: find.text('一把零錢'), matching: find.byType(Row)).last;
      expect(find.descendant(of: firstPack, matching: find.byType(CoinIcon)), findsWidgets, reason: '一把零錢用黃色金幣圖示');
      expect(find.descendant(of: firstPack, matching: find.text('🪙')), findsNothing, reason: '不再用 🪙 表情符號');
    });

    testWidgets('買金幣：加進存檔並提示獲得多少', (tester) async {
      await pumpShop(tester, saved: const {'coins': 50});
      await tester.tap(find.byKey(const ValueKey('pack_coins_90')));
      await tester.pump();
      expect(store.coins, 50 + 3100);
      expect(findCoinText('購買成功，獲得 🪙 3100'), findsOneWidget);
      expect(sounds.played.last, Sfx.coin);
    });

    testWidgets('永久移除廣告：買了顯示已購買，獎勵廣告的說明照樣保留', (tester) async {
      await pumpShop(tester);
      expect(find.byKey(const ValueKey('remove_ads_owned')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('buy_remove_ads')));
      await tester.pump();
      expect(store.adsRemoved, isTrue);
      expect(find.byKey(const ValueKey('remove_ads_owned')), findsOneWidget);
      expect(find.byKey(const ValueKey('buy_remove_ads')), findsNothing, reason: '不能重複購買');
      expect(find.textContaining('仍然可以自己選擇看廣告領獎勵'), findsOneWidget);
    });

    testWidgets('設定：所在地區需要時才有「廣告隱私權設定」，點了打開同意表單', (tester) async {
      await setUpStore(tester, const {});
      final privacy = FakeAdPrivacy();
      Future<void> pump() => tester.pumpWidget(MaterialApp(
          home: SettingsScreen(
              key: UniqueKey(),
              store: store,
              sounds: sounds,
              purchases: DevPurchaseService(enabled: true),
              adPrivacy: privacy)));
      await pump();
      expect(find.byKey(const ValueKey('privacy_options')), findsNothing, reason: '不在歐洲等地區不用顯示');
      privacy.required = true;
      await pump();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('privacy_options')), 200);
      await tester.tap(find.byKey(const ValueKey('privacy_options')));
      await tester.pump();
      expect(privacy.shown, 1);
    });

    testWidgets('設定：背景音樂和音效各有音量滑桿，拖動會存檔，關掉時滑桿變灰', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
          home: SettingsScreen(store: store, sounds: sounds, purchases: DevPurchaseService(enabled: true))));
      final music = find.byKey(const ValueKey('music_volume'));
      final sfx = find.byKey(const ValueKey('sfx_volume'));
      expect(find.text('50%'), findsOneWidget, reason: '背景音樂預設在中間');
      expect(find.text('100%'), findsOneWidget, reason: '音效預設最大');

      // 背景音樂拉到最右邊
      await tester.drag(music, const Offset(400, 0));
      await tester.pump();
      expect(sounds.musicVolume, 1.0);
      expect(store.musicVolume(-1), 1.0, reason: '放開後存檔');

      // 音效拉到最左邊：放開時播一聲試聽（音量 0 的話實際播放器不會出聲）
      sounds.played.clear();
      await tester.drag(sfx, const Offset(-400, 0));
      await tester.pump();
      expect(sounds.sfxVolume, 0.0);
      expect(store.sfxVolume(-1), 0.0);
      expect(sounds.played, [Sfx.coin]);
      expect(find.text('0%'), findsOneWidget);

      // 關掉背景音樂：滑桿不能拖
      await tester.tap(find.byKey(const ValueKey('music_switch')));
      await tester.pump();
      expect(tester.widget<Slider>(music).onChanged, isNull);
      await tester.drag(music, const Offset(-400, 0));
      expect(sounds.musicVolume, 1.0);

      // 重置進度不會清掉音量設定
      await store.resetProgress();
      expect(store.musicVolume(-1), 1.0);
      expect(store.sfxVolume(-1), 0.0);
    });

    testWidgets('設定：開源授權列出套件，點進去看授權全文', (tester) async {
      LicenseRegistry.addLicense(() => Stream.fromIterable([
            const LicenseEntryWithLineBreaks(['audioplayers'], 'MIT License\n\nCopyright (c) 2017 Blue Fire'),
          ]));
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
          home: SettingsScreen(store: store, sounds: sounds, purchases: DevPurchaseService(enabled: true))));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('licenses')), 100);
      await tester.tap(find.byKey(const ValueKey('licenses')));
      await tester.pumpAndSettle();
      expect(find.text('開源授權'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('license_audioplayers')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Copyright (c) 2017 Blue Fire'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('恢復購買：商店和設定頁都能拿回移除廣告', (tester) async {
      final purchases = DevPurchaseService(enabled: true);
      await purchases.buy(removeAdsProductId); // 之前在別支手機買過
      await pumpShop(tester, purchases: purchases);
      expect(store.adsRemoved, isFalse);
      await scrollToRestore(tester);
      await tester.tap(find.byKey(const ValueKey('restore')));
      await tester.pump();
      expect(store.adsRemoved, isTrue);
      expect(find.text('已恢復你買過的項目'), findsOneWidget);

      // 設定頁
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store, sounds: sounds, purchases: purchases)));
      await tester.tap(find.byKey(const ValueKey('restore_purchases')));
      await tester.pump();
      expect(store.adsRemoved, isTrue);

      // 沒買過
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
          home: SettingsScreen(store: store, sounds: sounds, purchases: DevPurchaseService(enabled: true))));
      await tester.tap(find.byKey(const ValueKey('restore_purchases')));
      await tester.pump();
      expect(store.adsRemoved, isFalse);
      expect(find.text('沒有可以恢復的購買項目'), findsOneWidget);
    });

    testWidgets('正式版還沒串接付款：購買只會顯示即將開放，不會給金幣', (tester) async {
      await pumpShop(tester, purchases: DevPurchaseService(enabled: false));
      await tester.tap(find.byKey(const ValueKey('pack_coins_30')));
      await tester.pump();
      expect(store.coins, 0);
      expect(find.text('儲值功能即將開放，敬請期待'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('buy_remove_ads')));
      await tester.pump();
      expect(store.adsRemoved, isFalse);
    });

    testWidgets('金幣不夠時，提示旁的「去儲值」切到儲值分頁', (tester) async {
      await pumpShop(tester, tab: 0);
      await tester.tap(find.byKey(const ValueKey('buy_hourglass')));
      await tester.pump();
      expect(findCoinText('金幣不夠，還差 🪙 ${ItemType.hourglass.price}'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500)); // 等提示滑進畫面再點
      await tester.tap(find.byKey(const ValueKey('go_top_up')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('一把零錢'), findsOneWidget);
      expect(find.byKey(const ValueKey('remove_ads_card')), findsOneWidget);
    });

    testWidgets('卡背分頁的價格用黃色金幣圖示，不是 🪙 表情符號', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: ShopScreen(store: store, sounds: sounds, purchases: DevPurchaseService(enabled: true), initialTab: 2),
      ));
      await tester.pump();
      expect(findCoinText('🪙 ${skinById('fortune').price}'), findsOneWidget);
      expect(find.text('🪙 ${skinById('fortune').price}'), findsNothing);
    });

    testWidgets('儲值分頁在小螢幕不會跑版', (tester) async {
      await pumpShop(tester);
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(tester.takeException(), isNull);
      await scrollToRestore(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('增加收益', () {
    String today() {
      final d = DateTime.now();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    Future<void> pumpTopUp(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
      await setUpStore(tester, saved);
      await tester.pumpWidget(MaterialApp(
        home: ShopScreen(
          store: store,
          sounds: sounds,
          purchases: DevPurchaseService(enabled: true),
          initialTab: ShopScreen.topUpTab,
          ads: ads,
        ),
      ));
      await tester.pump();
    }

    Future<void> pumpDaily(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
      await setUpStore(tester, saved);
      await tester
          .pumpWidget(MaterialApp(home: DailyScreen(store: store, sounds: sounds, ads: ads, random: Random(1))));
      await tester.pump();
    }

    testWidgets('新手禮包：金幣、每種道具、限定卡背，只能買一次；重置進度保留卡背，恢復購買拿回卡背', (tester) async {
      await pumpTopUp(tester);
      expect(find.byKey(const ValueKey('starter_pack')), findsOneWidget, reason: '儲值分頁最上面');
      final starterTop = tester.getTopLeft(find.byKey(const ValueKey('starter_pack'))).dy;
      expect(starterTop, lessThan(tester.getTopLeft(find.byKey(const ValueKey('month_card'))).dy));
      await tester.tap(find.byKey(const ValueKey('buy_starter_pack')));
      await tester.pump();
      expect(store.coins, starterPackCoins);
      for (final type in ItemType.values) {
        expect(store.itemCount(type), starterPackItemsEach, reason: type.label);
      }
      expect(store.ownedSkins, contains(starterPackSkinId));
      expect(store.starterPackBought, isTrue);
      expect(find.byKey(const ValueKey('starter_pack')), findsNothing, reason: '買過就不再顯示');
      expect(await buyStarterPack(DevPurchaseService(enabled: true), store), isNull, reason: '只能買一次');
      expect(await store.buySkin(skinById(starterPackSkinId)), isFalse, reason: '限定卡背不能用金幣買');

      await store.resetProgress();
      expect(store.coins, 0);
      expect(store.ownedSkins, contains(starterPackSkinId), reason: '真錢買的卡背保留');
      expect(store.starterPackBought, isTrue);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('新手禮包：恢復購買拿回卡背，但不會重發金幣和道具', (tester) async {
      await setUpStore(tester, const {});
      final purchases = DevPurchaseService(enabled: true);
      await purchases.buy(starterPackProductId);
      expect(await restorePurchases(purchases, store), isTrue);
      expect(store.ownedSkins, contains(starterPackSkinId));
      expect(store.starterPackBought, isTrue);
      expect(store.coins, 0);
    });

    testWidgets('商店看廣告領金幣：每次 100，每天 5 次；廣告沒播成功不給', (tester) async {
      await pumpTopUp(tester);
      ads.rewardSucceeds = false;
      await tester.tap(find.byKey(const ValueKey('ad_coins')));
      await tester.pump();
      expect(store.coins, 0);
      expect(find.text('廣告目前無法播放，請稍後再試'), findsOneWidget);
      ads.rewardSucceeds = true;
      for (var i = 0; i < shopAdCoinsPerDay; i++) {
        await tester.tap(find.byKey(const ValueKey('ad_coins')));
        await tester.pump();
      }
      expect(store.coins, shopAdCoins * shopAdCoinsPerDay);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ad_coins'))).onPressed, isNull, reason: '次數用完');
      expect(find.textContaining('今天的次數用完了'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('夜市轉盤：每天免費轉一次，看廣告再轉 3 次，轉完明天再來；首頁每日任務有紅點', (tester) async {
      await pumpDaily(tester);
      expect(store.hasClaimableDaily, isTrue, reason: '還有免費轉盤');
      final expected = spinWheel(Random(1));
      await tester.tap(find.byKey(const ValueKey('wheel_free')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('wheel_free'))).onPressed, isNull,
          reason: '轉的時候不能再按');
      await tester.pump(PrizeWheel.spinDuration + const Duration(milliseconds: 100));
      final prize = wheelPrizes[expected];
      if (prize.coins > 0) {
        expect(store.coins, prize.coins);
      } else {
        expect(store.itemCount(prize.item!), 1);
      }
      expect(store.wheelFreeAvailable, isFalse);
      expect(find.textContaining('今天還剩 $wheelAdSpinsPerDay 次'), findsOneWidget);

      for (var i = 0; i < wheelAdSpinsPerDay; i++) {
        await tester.tap(find.byKey(const ValueKey('wheel_ad')));
        await tester.pump();
        await tester.pump(PrizeWheel.spinDuration + const Duration(milliseconds: 100));
      }
      expect(ads.rewardedShown, wheelAdSpinsPerDay);
      expect(find.byKey(const ValueKey('wheel_done')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('轉盤指針停在抽中的那一格', (tester) async {
      for (var index = 0; index < wheelPrizes.length; index++) {
        final key = GlobalKey<PrizeWheelState>();
        int? stopped;
        await tester.pumpWidget(MaterialApp(
          home: Center(child: PrizeWheel(key: key, size: 200, onStopped: (i) => stopped = i)),
        ));
        key.currentState!.spinTo(index);
        await tester.pump();
        await tester.pump(PrizeWheel.spinDuration + const Duration(milliseconds: 50));
        expect(stopped, index);
        // 轉盤轉了 angle 之後，正上方（指針）對到的格子
        final angle = tester
            .widget<Transform>(find.descendant(of: find.byType(PrizeWheel), matching: find.byType(Transform)).first)
            .transform;
        final rotation = atan2(angle.entry(1, 0), angle.entry(0, 0));
        final slice = 2 * pi / wheelPrizes.length;
        final under = ((-rotation / slice).round() % wheelPrizes.length + wheelPrizes.length) % wheelPrizes.length;
        expect(under, index, reason: '第 $index 格');
      }
    });

    testWidgets('簽到後可以看廣告再領一次（每天一次）', (tester) async {
      await pumpDaily(tester);
      expect(find.byKey(const ValueKey('check_in_double')), findsNothing, reason: '還沒簽到');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('check_in')), 200);
      await tester.tap(find.byKey(const ValueKey('check_in')));
      await tester.pump();
      expect(store.coins, checkInRewards[0]);
      await tester.tap(find.byKey(const ValueKey('check_in_double')));
      await tester.pump();
      expect(store.coins, checkInRewards[0] * 2);
      expect(find.byKey(const ValueKey('check_in_double')), findsNothing, reason: '每天一次');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('每日任務可以看廣告領雙倍', (tester) async {
      await pumpDaily(tester, saved: {
        'daily_date': today(),
        for (final t in dailyTaskPool) 'daily_p_${t.id}': 99,
      });
      final task = store.todayTasks.first;
      await tester.scrollUntilVisible(find.byKey(ValueKey('daily_double_${task.id}')), 200);
      await tester.tap(find.byKey(ValueKey('daily_double_${task.id}')));
      await tester.pump();
      expect(store.coins, task.coins * 2);
      expect(store.isDailyClaimed(task), isTrue);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('全部完成寶箱：5 個任務都領完才能開，送金幣和招財貓；看廣告金幣 ×2；一天一次', (tester) async {
      await pumpDaily(tester, saved: {
        'daily_date': today(),
        for (final t in dailyTaskPool) 'daily_p_${t.id}': 99,
      });
      final tasks = store.todayTasks;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('daily_chest')), 200);
      expect(find.byKey(const ValueKey('daily_chest_open')), findsNothing, reason: '任務還沒領完');
      expect(store.dailyTasksClaimed, 0);
      expect(findCoinText('0 / ${tasks.length} 個任務已領・🪙 $dailyChestCoins ＋ 🐱 招財貓'), findsOneWidget);
      for (final t in tasks.skip(1)) {
        await store.claimDaily(t);
      }
      expect(store.canOpenDailyChest, isFalse, reason: '還差 1 個');
      await tester.tap(find.byKey(ValueKey('daily_${tasks.first.id}')));
      await tester.pump();
      expect(store.canOpenDailyChest, isTrue);
      expect(store.hasClaimableDaily, isTrue, reason: '首頁每日任務亮紅點');
      final coins = store.coins;
      final cats = store.itemCount(ItemType.luckyCat);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('daily_chest_double')), 200);
      await tester.tap(find.byKey(const ValueKey('daily_chest_double')));
      await tester.pump();
      expect(store.coins, coins + dailyChestCoins * 2);
      expect(store.itemCount(ItemType.luckyCat), cats + 1);
      expect(find.text('已開啟'), findsOneWidget);
      expect(await store.openDailyChest(), isFalse, reason: '一天一次');
      await tester.pump(const Duration(seconds: 3));
    });

    test('每日挑戰：同一天的種子固定、換日就換；今天的最高分換日歸零', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 12, 31, 23, 0);
      final store = await ProgressStore.load(clock: () => now);
      expect(store.dailyChallengeSeed, 20261231);
      expect(await store.recordDailyChallenge(5000), 0);
      expect(await store.recordDailyChallenge(3000), 5000, reason: '沒破紀錄不覆蓋');
      expect(store.dailyChallengeBest, 5000);
      expect(store.endlessBest, 0, reason: '不算進大胃王的最高分');
      now = DateTime(2027, 1, 1, 8, 0);
      expect(store.dailyChallengeSeed, 20270101);
      expect(store.dailyChallengeBest, 0, reason: '新的一天重新比');
    });

    testWidgets('每日挑戰：今天的種子出牌，一開始就算玩過；沒有重新開始，結束只能回首頁', (tester) async {
      await setUpStore(tester, const {});
      final board = FakeLeaderboardService();
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(
            store: store, ads: ads, sounds: sounds, previewSeconds: 0, dailyChallenge: true, leaderboards: board),
      ));
      final first = tableOnScreen(tester);
      expect(EndlessGame(random: Random(store.dailyChallengeSeed)).slots.whereType<Food>().length, first.length);
      expect(store.dailyChallengePlayed, isTrue, reason: '一開始就用掉今天的機會');
      expect(find.byKey(const ValueKey('restart')), findsNothing, reason: '不能重新開始');
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);
      expect(find.text('今日挑戰結束'), findsOneWidget);
      expect(find.text('再吃一輪'), findsNothing);
      expect(find.text('強化裝備再挑戰'), findsNothing);
      expect(store.dailyChallengeBest, 600);
      expect(store.endlessBest, 0, reason: '不算進大胃王的最高分');
      expect(board.submitted, [(Leaderboard.daily, 600)]);
    });

    test('每日挑戰：規則照日期輪流，每天都不一樣，五天一輪', () {
      final days = [for (var d = 0; d < 5; d++) dailyRuleFor(DateTime(2026, 11, 20 + d))];
      expect(days.toSet().length, 5);
      expect(dailyRuleFor(DateTime(2026, 11, 25)), days.first);
      expect(dailyRuleFor(DateTime(2026, 11, 20, 23, 59)), dailyRuleFor(DateTime(2026, 11, 20)));
    });

    test('每日挑戰：連續天數，昨天有玩就 +1，斷一天從 1 開始；最長紀錄不會變少；同一天不重複算', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 11, 20, 9);
      final store = await ProgressStore.load(clock: () => now);
      expect(store.dailyStreak, 0);
      await store.startDailyChallenge();
      await store.startDailyChallenge();
      expect(store.dailyStreak, 1);
      for (var d = 21; d <= 22; d++) {
        now = DateTime(2026, 11, d, 21);
        expect(store.dailyChallengePlayed, isFalse);
        await store.startDailyChallenge();
      }
      expect(store.dailyStreak, 3);
      expect(store.isAchieved(achievements.firstWhere((a) => a.id == 'daily_streak3')), isTrue);
      now = DateTime(2026, 11, 23, 12);
      expect(store.dailyStreak, 3, reason: '今天還沒玩，昨天有玩，連續還在');
      now = DateTime(2026, 11, 24, 12);
      expect(store.dailyStreak, 0, reason: '斷了一天');
      await store.startDailyChallenge();
      expect(store.dailyStreak, 1);
      expect(store.dailyBestStreak, 3);
    });

    test('每日挑戰：連續 30 天的成就送月光常客卡背', () {
      final a = achievements.firstWhere((a) => a.id == 'daily_streak30');
      expect((a.target, a.skinId), (30, 'moonlight'));
      expect(skinById('moonlight').achievementOnly, isTrue);
    });

    test('每日挑戰的遊戲：翻完 40 翻就結束，不能吃胃藥；規則會改連擊上限、大胃王時間、吃光獎勵、老闆提示', () {
      // 每一翻都配對成功：桌子不會塞滿，翻到第 40 翻就結束
      final g = EndlessGame(random: Random(3), turnLimit: dailyTurnLimit);
      while (!g.isEnded) {
        if (g.boardCleared) g.nextWave();
        final a = g.slots.indexWhere((f) => f != null);
        final b = g.slots.lastIndexWhere((f) => f == g.slots[a]);
        g.pick(a);
        g.pick(b);
        expect(g.turnsLeft, dailyTurnLimit - g.turns);
      }
      expect(g.outOfTurns, isTrue);
      expect(g.turns, dailyTurnLimit);
      expect(g.turnsLeft, 0);
      expect(g.matches, dailyTurnLimit);
      expect(g.canRevive, isFalse, reason: '翻完了不能吃胃藥');
      expect(g.coinsEarned, greaterThan(0));
      expect(EndlessGame(random: Random(1)).turnsLeft, isNull, reason: '大胃王沒有翻數限制');

      expect(DailyRule.comboRush.comboCap, 10);
      expect(DailyRule.feverDay.feverAt, 3);
      expect(DailyRule.clearFeast.clearBonusMultiplier, 3);
      expect(DailyRule.noBoss.bossHints, isFalse);
      expect(DailyRule.quickEye.previewSeconds, 1);
      final noBoss = EndlessGame(random: Random(1), bossHints: false)..consecutiveMisses = 5;
      expect(noBoss.takeBossHint(), isNull);
    });

    testWidgets('每日挑戰畫面：剩幾翻、今日規則，沒有道具列；結算可以看廣告金幣 ×2', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, previewSeconds: 0, dailyChallenge: true),
      ));
      expect(endlessText(tester, 'turns_left'), '剩 $dailyTurnLimit 翻');
      expect(find.byKey(const ValueKey('next_serve')), findsNothing);
      expect(find.byKey(const ValueKey('daily_rule')), findsOneWidget);
      expect(find.text('今日規則：${store.dailyRule.title}'), findsOneWidget);
      expect(find.byKey(const ValueKey('peek')), findsNothing, reason: '不能偷看、不能用道具');
      await eatEndlessPair(tester);
      await settleEndlessEat(tester);
      expect(endlessText(tester, 'turns_left'), '剩 ${dailyTurnLimit - 1} 翻');
      await fillEndlessTable(tester);
      expect(find.text('今日挑戰結束'), findsOneWidget);
      expect(find.textContaining('連續挑戰 1 天'), findsOneWidget);
      final coins = store.coins;
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_ad')));
      await tester.pump(const Duration(seconds: 1));
      expect(store.coins, greaterThan(coins));
      expect((store.coins - coins).isEven, isTrue, reason: '金幣 ×2');
    });

    testWidgets('排行榜：可以用時上面多一個排行榜按鈕，點了打開大胃王的排行榜；不能用時不顯示', (tester) async {
      await setUpStore(tester, const {});
      final board = FakeLeaderboardService();
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(
            store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0, leaderboards: board),
      ));
      await tester.tap(find.byKey(const ValueKey('leaderboard')));
      await tester.pump();
      expect(board.shown, [Leaderboard.endless]);
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);
      expect(board.submitted, [(Leaderboard.endless, 600)]);

      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
      expect(find.byKey(const ValueKey('leaderboard')), findsNothing);
    });

    testWidgets('分享成績：大胃王結算視窗有分享按鈕，按了不會關掉視窗', (tester) async {
      await setUpStore(tester, const {});
      final share = FakeShareService();
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0, share: share),
      ));
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);
      await tester.tap(find.byKey(const ValueKey('dialog_share')));
      await tester.pump();
      expect(share.shared.length, 1);
      final card = share.shared.single;
      expect((card.title, card.score, card.matches, card.allClears, card.isRecord), ('夜市大胃王', 600, 1, 1, true));
      expect(card.message, contains('夜市大胃王吃了 600 分'));
      expect(find.text('新紀錄！吃飽收攤'), findsOneWidget, reason: '視窗還在');
    });

    testWidgets('分享圖：1080×1350 的 PNG', (tester) async {
      final png = await tester.runAsync(() => renderScoreCard(
          const ScoreCard(title: '每日挑戰', score: 128500, matches: 140, bestCombo: 5, allClears: 3, isRecord: true)));
      expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47], reason: 'PNG 檔頭');
      final size = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
        final frame = await codec.getNextFrame();
        return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      });
      expect(size, scoreCardSize);
    });

    test('每日提醒：今天 8 點前還有獎勵沒領就今天提醒，否則明天 8 點；內容寫出沒領的東西', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 11, 20, 10, 0);
      final store = await ProgressStore.load(clock: () => now);
      var r = planReminder(store, now);
      expect(r.at, DateTime(2026, 11, 20, reminderHour));
      expect(r.body, contains('簽到獎勵'));
      expect(r.body, contains('免費轉盤'));

      await store.checkIn();
      await store.claimWheel(0, byAd: false);
      r = planReminder(store, now);
      expect(r.at, DateTime(2026, 11, 21, reminderHour), reason: '今天都領完了，明天再提醒');

      now = DateTime(2026, 11, 20, 21, 0);
      expect(planReminder(store, now).at, DateTime(2026, 11, 21, reminderHour), reason: '過了 8 點就排明天');
      now = DateTime(2026, 12, 31, 22, 0);
      expect(planReminder(store, now).at, DateTime(2027, 1, 1, reminderHour), reason: '跨年也對');
    });

    testWidgets('設定：每日提醒開關，要先允許通知；關掉會取消提醒', (tester) async {
      await setUpStore(tester, const {});
      final reminders = FakeReminderService(allow: false);
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
            store: store, sounds: sounds, purchases: DevPurchaseService(enabled: true), reminders: reminders),
      ));
      await tester.tap(find.byKey(const ValueKey('reminder_switch')));
      await tester.pump();
      expect(store.reminderOn, isFalse, reason: '不允許通知就維持關閉');
      expect(find.textContaining('沒有通知權限'), findsOneWidget);

      reminders.allow = true;
      await tester.tap(find.byKey(const ValueKey('reminder_switch')));
      await tester.pump();
      expect(store.reminderOn, isTrue);
      expect(reminders.scheduled, 1);

      await tester.tap(find.byKey(const ValueKey('reminder_switch')));
      await tester.pump();
      expect(store.reminderOn, isFalse);
      expect(reminders.cancelled, 1);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('第一次簽到後問要不要每日提醒，只問一次', (tester) async {
      await setUpStore(tester, const {});
      final reminders = FakeReminderService();
      await tester.pumpWidget(MaterialApp(home: DailyScreen(store: store, sounds: sounds, reminders: reminders)));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('check_in')), 200);
      await tester.tap(find.byKey(const ValueKey('check_in')));
      await tester.pumpAndSettle();
      expect(find.text('每天提醒你簽到？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder_yes')));
      await tester.pumpAndSettle();
      expect(store.reminderOn, isTrue);
      expect(reminders.scheduled, 1);
      expect(store.reminderAsked, isTrue);
    });

    testWidgets('結算視窗內容很多時：小螢幕不跑版，上面可以捲動，按鈕都看得到、點得到', (tester) async {
      for (final size in const [Size(640, 1136), Size(750, 1334)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        ResultChoice? choice;
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => choice = await showDialog<ResultChoice>(
                  context: context,
                  builder: (_) => ResultDialog(
                    title: '刷新今日最佳！',
                    lines: const [
                      '吃了 41 組，最高 5 連擊',
                      '全部吃光 5 次',
                      '總分 16500',
                      '今天最佳 16500・明天換一盤',
                      '獲得 🪙 83',
                      '🏆 成就達成：小吃通',
                      '🏆 成就達成：吃飽飽',
                    ],
                    adLabel: '看廣告吃胃藥，收掉 10 張',
                    primaryLabel: '再吃一輪',
                    leaveLabel: '回到首頁',
                    emphasizeAd: true,
                    upgradeLabel: '強化裝備再挑戰',
                    upgradeHint: '連擊已經衝到上限 ×5！攤車升到 Lv.1，連擊上限提高到 ×6，分數更高（🪙 3000）',
                    onShare: (_) {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size 不跑版');
        final leave = find.byKey(const ValueKey('dialog_leave'));
        expect(tester.getRect(leave).bottom, lessThanOrEqualTo(size.height / 2), reason: '$size 回到首頁在畫面裡');
        await tester.tap(leave);
        await tester.pumpAndSettle();
        expect(choice, ResultChoice.leave, reason: '$size 點得到');
      }
    });

    testWidgets('首頁每日挑戰一天只能玩一次：中途離開以目前分數記錄，回首頁變暗、點了只提示明天再來', (tester) async {
      await pumpHome(tester);
      expect(find.text(store.dailyRule.title), findsOneWidget, reason: '還沒玩時顯示今日規則');
      expect(find.byKey(const ValueKey('daily_challenge_badge')), findsNothing, reason: '還沒有連續天數');
      expect(find.byKey(const ValueKey('daily_challenge_dot')), findsOneWidget, reason: '今天還沒玩，亮紅點');
      await tapAndSettle(tester, find.byKey(const ValueKey('daily_challenge')));
      await eatEndlessPair(tester);
      await settleEndlessEat(tester);
      final score = int.parse(endlessText(tester, 'score'));
      expect(score, greaterThan(0));
      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      expect(find.textContaining('每日挑戰一天只能玩一次'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_leave')));
      expect(store.dailyChallengeBest, score, reason: '中途離開也照目前分數記錄');
      expect(find.byKey(const ValueKey('daily_challenge_dot')), findsNothing);
      expect(find.text('今天 $score 分'), findsOneWidget);
      expect(find.text('🔥1'), findsOneWidget, reason: '連續挑戰 1 天');

      await tester.tap(find.byKey(const ValueKey('daily_challenge')));
      await settle(tester);
      expect(find.text('今天的每日挑戰已經玩過了，明天換一盤再來！'), findsOneWidget);
      expect(find.byType(EndlessScreen), findsNothing, reason: '不能再玩');
    });

    testWidgets('大胃王每玩 3 輪播一次插頁廣告；吃過胃藥的那輪、買了移除廣告都不播', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
      for (var round = 1; round <= 3; round++) {
        await fillEndlessTable(tester);
        await tapAndSettle(tester, find.text('再吃一輪'));
        expect(ads.interstitialShown, round == 3 ? 1 : 0, reason: '第 $round 輪');
      }
      // 第 6 輪看過吃胃藥的廣告：不播
      for (var round = 4; round <= 6; round++) {
        await fillEndlessTable(tester);
        if (round == 6) {
          await tester.tap(find.byKey(const ValueKey('dialog_ad')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await fillEndlessTable(tester);
        }
        await tapAndSettle(tester, find.text('再吃一輪'));
      }
      expect(ads.interstitialShown, 1, reason: '吃過胃藥的那輪不播');

      await store.setAdsRemoved(true);
      for (var round = 7; round <= 9; round++) {
        await fillEndlessTable(tester);
        await tapAndSettle(tester, find.text('再吃一輪'));
      }
      expect(ads.interstitialShown, 1, reason: '買了移除廣告不播');
    });
  });

  group('強化裝備', () {
    int none(GearType _) => 0;

    test('建議：走透透只差 1～2 組就建議帽子，寫出差幾組和多幾秒', () {
      final advice = adviseGear(levelOf: none, coins: 0, endless: false, pairsLeft: 2, bestCombo: 2)!;
      expect(advice.type, GearType.hat);
      expect(advice.nextLevel, 1);
      expect(advice.cost, GearType.hat.costs[0]);
      expect(advice.message, startsWith('只差 2 組就收攤了！'));
      expect(advice.message, contains('老闆的帽子升到 Lv.1，每局時間 +2 秒'));
      expect(advice.message, isNot(contains('現在就升得起')));
    });

    test('建議：連擊衝到上限就建議攤車', () {
      final advice = adviseGear(levelOf: none, coins: 0, endless: true, bestCombo: 5, comboCap: 5)!;
      expect(advice.type, GearType.cart);
      expect(advice.message, contains('連擊已經衝到上限 ×5！'));
      expect(advice.message, contains('連擊上限提高到 ×6'));
    });

    test('建議：照模式的預設順序，跳過已經升滿的；全部升滿就不建議', () {
      List<GearType> sequence({required bool endless}) {
        final maxed = <GearType>{};
        final out = <GearType>[];
        while (true) {
          final a = adviseGear(levelOf: (t) => maxed.contains(t) ? t.maxLevel : 0, coins: 0, endless: endless);
          if (a == null) return out;
          out.add(a.type);
          maxed.add(a.type);
        }
      }

      // 大胃王不會建議走透透限定的帽子
      expect(sequence(endless: true), [
        GearType.backpack,
        GearType.cart,
        GearType.glasses,
        GearType.lunchBag,
        GearType.favor,
        GearType.abacus,
      ]);
      // 走透透不會建議大胃王限定的裝備
      expect(sequence(endless: false),
          [GearType.hat, GearType.glasses, GearType.cart, GearType.lunchBag, GearType.abacus]);
      final abacus = adviseGear(levelOf: (t) => t == GearType.abacus ? 1 : t.maxLevel, coins: 0, endless: true)!;
      expect(abacus.nextLevel, 2);
      expect(abacus.message, contains('金幣再 +10%'));
    });

    test('建議：翻錯很多次就建議老花眼鏡，眼鏡滿了再建議便當袋', () {
      final glasses = adviseGear(levelOf: (_) => 0, coins: 0, endless: false, mistakes: 4)!;
      expect(glasses.type, GearType.glasses);
      expect(glasses.message, startsWith('這一局翻錯了 4 次！'));
      expect(glasses.message, contains('翻牌記憶多 1 秒'));
      final bag =
          adviseGear(levelOf: (t) => t == GearType.glasses ? t.maxLevel : 0, coins: 0, endless: true, mistakes: 3)!;
      expect(bag.type, GearType.lunchBag);
      expect(bag.message, contains('翻錯時連擊只少 1 段'));
    });

    test('建議：大胃王不建議帽子（走透透限定）；金幣夠的時候提示現在就升得起', () {
      final advice = adviseGear(levelOf: none, coins: GearType.backpack.costs[0], endless: true)!;
      expect(advice.type, GearType.backpack);
      expect(advice.message, contains('全部吃光的獎勵再 +10%'));
      expect(advice.message, contains('現在就升得起'));
      expect(adviseGear(levelOf: none, coins: 0, endless: false)!.type, GearType.hat);
      expect(GearType.hat.modeTag, '（走透透限定）');
      expect(GearType.backpack.modeTag, '（大胃王限定）');
      expect(GearType.cart.modeTag, '');
    });

    testWidgets('走透透時間到：顯示建議，強化裝備打開裝備分頁，升級後回來重新挑戰', (tester) async {
      await pumpGame(tester, saved: {'coins': GearType.hat.costs[0]});
      await tester.pump(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('時間到了'), findsOneWidget);
      expect(find.byKey(const ValueKey('upgrade_hint')), findsOneWidget);
      expect(find.textContaining('老闆的帽子升到 Lv.1'), findsOneWidget);
      // 按鈕順序：看廣告 → 強化裝備 → 重新開始
      final adTop = tester.getTopLeft(find.byKey(const ValueKey('dialog_ad'))).dy;
      final upgradeTop = tester.getTopLeft(find.byKey(const ValueKey('dialog_upgrade'))).dy;
      expect(upgradeTop, greaterThan(adTop));
      expect(upgradeTop, lessThan(tester.getTopLeft(find.text('重新開始這一攤')).dy));

      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_upgrade')));
      expect(find.text('夜市商店'), findsOneWidget);
      expect(find.text('老闆的帽子（走透透限定）  Lv.0 / 3'), findsOneWidget, reason: '直接打開裝備分頁');
      await tester.tap(find.byKey(const ValueKey('upgrade_hat')));
      await tester.pump();
      expect(store.gearLevel(GearType.hat), 1);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('時間到了'), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('time'))).data, '62', reason: '用新的帽子重新開始：60 + 2 秒');
    });

    testWidgets('大胃王收攤：強化裝備前先發這一輪的金幣，回來後再吃一輪', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
      await eatEndlessPair(tester);
      await fillEndlessTable(tester);
      expect(find.byKey(const ValueKey('dialog_upgrade')), findsOneWidget);
      expect(store.coins, 0, reason: '還沒決定之前不發金幣');

      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_upgrade')));
      expect(store.coins, (600 / EndlessGame.scorePerCoin).round(), reason: '打開商店前先發這一輪的金幣');
      expect(find.text('老闆的帽子（走透透限定）  Lv.0 / 3'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(tester.widget<RollingNumber>(find.byKey(const ValueKey('score'))).value, 0, reason: '回來後是新的一輪');
    });

    testWidgets('裝備全部升滿時，不顯示強化裝備', (tester) async {
      await pumpGame(tester, saved: {for (final t in GearType.values) 'gear_${t.name}': t.maxLevel});
      await tester.pump(const Duration(seconds: 70));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('時間到了'), findsOneWidget);
      expect(find.byKey(const ValueKey('dialog_upgrade')), findsNothing);
      expect(find.byKey(const ValueKey('upgrade_hint')), findsNothing);
    });

    testWidgets('時間到視窗多了建議和按鈕，在最小螢幕上也放得下', (tester) async {
      await pumpGame(tester, saved: {'coins': 99999});
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('upgrade_hint')), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final key in ['dialog_ad', 'dialog_upgrade', 'dialog_leave']) {
        expect(tester.getRect(find.byKey(ValueKey(key))).bottom, lessThan(568), reason: '$key 在畫面內');
      }
    });
  });
}
