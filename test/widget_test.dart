import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/card_skins.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/game/night_market_data.dart';
import 'package:night_market_match/screens/game_screen.dart';
import 'package:night_market_match/screens/home_screen.dart';
import 'package:night_market_match/services/ad_service.dart';
import 'package:night_market_match/services/progress_store.dart';
import 'package:night_market_match/services/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final g = MatchingGame(level: levels[2], random: Random(1));
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
      final g = MatchingGame(level: levels[0], random: Random(1));
      g.pick(0);
      g.pick(pairOf(g, 0));
      expect(g.combo, 2);

      final a = List.generate(g.cards.length, (j) => j).firstWhere((j) => !g.isMatched[j]);
      final b = List.generate(g.cards.length, (j) => j)
          .firstWhere((j) => !g.isMatched[j] && g.cards[j] != g.cards[a]);
      g.pick(a);
      expect(g.pick(b), PickResult.mismatched);
      expect(g.combo, 1);
      expect(g.isLocked, isTrue);

      final other = List.generate(g.cards.length, (j) => j)
          .firstWhere((j) => !g.isOpen[j]);
      expect(g.pick(other), PickResult.ignored);
      expect(g.steps, 4);

      g.hideMismatched();
      expect(g.isOpen[a], isFalse);
      expect(g.isOpen[b], isFalse);
      expect(g.isLocked, isFalse);
    });

    test('全部配對完成：過關、加時間獎勵、算星數和金幣', () {
      final g = MatchingGame(level: levels[0], random: Random(1));
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
        final g = MatchingGame(level: levels[0], random: Random(1));
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
      final g = MatchingGame(level: levels[0], random: Random(1));
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
      final g = MatchingGame(level: levels[0], random: Random(1));
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
      final g = MatchingGame(level: levels[0], random: Random(1));
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

  group('內容資料', () {
    test('18 攤夜市，難度遞增，小吃種類夠最大的一攤用', () {
      expect(levels.length, 18);
      expect(levels.map((l) => l.name).toSet().length, 18);
      // 最多 24 張牌，小螢幕也放得下
      expect(levels.every((l) => l.pairs <= 12), isTrue);
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

    test('卡背 id 不重複，預設卡背免費', () {
      expect(cardSkins.map((s) => s.id).toSet().length, cardSkins.length);
      expect(skinById(defaultSkinId).price, 0);
      expect(skinById('不存在').id, defaultSkinId);
    });
  });

  group('ProgressStore', () {
    test('買卡背：金幣不夠買不了，買了會扣金幣並可換上', () async {
      SharedPreferences.setMockInitialValues({'coins': 400});
      final store = await ProgressStore.load();
      final starry = skinById('starry'); // 500
      final fortune = skinById('fortune'); // 300
      expect(await store.buySkin(starry), isFalse);
      expect(store.coins, 400);

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
      home: GameScreen(levelIndex: level, store: store, ads: ads, sounds: sounds, random: Random(1)),
    ));
  }

  /// 從首頁開始。
  Future<void> pumpHome(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
    await setUpStore(tester, saved);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
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

  /// 用同樣的種子重建遊戲，得知牌的排列。
  MatchingGame mirror(int level) => MatchingGame(level: levels[level], random: Random(1));

  Future<void> solveOnScreen(WidgetTester tester, int level) async {
    final g = mirror(level);
    for (var i = 0; i < g.cards.length; i++) {
      if (g.isMatched[i]) continue;
      final j = pairOf(g, i);
      g.pick(i);
      g.pick(j);
      await tester.tap(find.byKey(ValueKey('card_$i')));
      await tester.tap(find.byKey(ValueKey('card_$j')));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('GameScreen', () {
    testWidgets('開局：逢甲夜市 12 張蓋著的牌', (tester) async {
      await pumpGame(tester);
      expect(find.text('逢甲夜市'), findsOneWidget);
      expect(find.text('第 1 攤・台中'), findsOneWidget);
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

    testWidgets('過關：金幣、解鎖、星數寫進存檔，可以直接前往下一攤', (tester) async {
      await pumpGame(tester);
      await solveOnScreen(tester, 0);
      expect(find.text('收攤！逢甲夜市完成'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);

      await tester.tap(find.text('前往下一攤：士林夜市'));
      await settle(tester);
      expect(find.text('士林夜市'), findsOneWidget);
      expect(find.text('🪙 260'), findsOneWidget); // (2000 + 60 秒 × 10) / 10
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
      expect(find.text('🪙 520'), findsOneWidget);
    });

    testWidgets('第 3 次過關播插頁式廣告；看過獎勵型廣告的那次不播', (tester) async {
      await pumpGame(tester, saved: {'clears': 2});
      await solveOnScreen(tester, 0);
      await tester.tap(find.text('前往下一攤：士林夜市'));
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

      await tester.tap(find.text('前往下一攤：士林夜市'));
      await tester.pump();
      expect(sounds.played.last, Sfx.coin);
    });

    testWidgets('最難的羅東夜市 24 張牌也能完整顯示', (tester) async {
      await pumpGame(tester, level: 5);
      expect(find.text('羅東夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(24));
      for (var i = 0; i < 24; i++) {
        expect(tester.getRect(find.byKey(ValueKey('card_$i'))).bottom, lessThan(2556 / 3));
      }
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
    testWidgets('首頁：開始遊戲進到最新解鎖的一攤，並顯示總星數和金幣', (tester) async {
      await pumpHome(tester, saved: {'unlocked': 2, 'coins': 123, 'stars_0': 3});
      expect(find.text('夜市翻牌'), findsOneWidget);
      expect(find.text('第 2 攤・士林夜市'), findsOneWidget);
      expect(find.text('★ 3 / 54'), findsOneWidget);
      expect(find.text('🪙 123'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      expect(find.text('士林夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(16));
    });

    testWidgets('遊戲中按返回會先確認；選繼續玩就留下，選離開就回首頁', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('start')));

      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      expect(find.text('離開這一攤？'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // 確認視窗開著時不倒數
      await tapAndSettle(tester, find.text('繼續玩'));
      expect(find.text('逢甲夜市'), findsOneWidget);
      final time = int.parse(tester.widget<Text>(find.byKey(const ValueKey('time'))).data!);
      expect(time, greaterThanOrEqualTo(58));

      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_leave')));
      expect(find.byKey(const ValueKey('start')), findsOneWidget);
    });

    testWidgets('選擇夜市：上鎖的會提示，過關後回列表星數和解鎖會更新', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('levels')));
      expect(find.text('選擇夜市'), findsOneWidget);
      expect(find.text('逢甲夜市・台中'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('level_1')));
      await tester.pump();
      expect(find.text('先通過「逢甲夜市」才能解鎖'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('level_0')));
      await solveOnScreen(tester, 0);
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_leave')));
      expect(find.text('選擇夜市'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('level_stars_0'))).data, '★★★');

      await tapAndSettle(tester, find.byKey(const ValueKey('level_1')));
      expect(find.text('士林夜市'), findsOneWidget);
    });

    testWidgets('卡背商店：金幣不夠會提示，買了就換上，首頁顯示目前卡背', (tester) async {
      await pumpHome(tester, saved: {'coins': 400});
      await tapAndSettle(tester, find.byKey(const ValueKey('shop')));
      expect(find.text('卡背商店'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('skin_starry'))); // 500，不夠
      await tester.pump();
      expect(find.text('金幣不夠，還差 🪙 100'), findsOneWidget);
      expect(store.coins, 400);

      await tester.tap(find.byKey(const ValueKey('skin_fortune'))); // 300
      await tester.pump();
      expect(store.coins, 100);
      expect(store.equippedSkin, 'fortune');
      expect(sounds.played.last, Sfx.coin);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('目前使用：招財金'), findsOneWidget);
      expect(find.text('🪙 100'), findsOneWidget);
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
      expect(find.text('第 1 攤・逢甲夜市'), findsOneWidget);
      expect(find.text('🪙 0'), findsOneWidget);
    });
  
    testWidgets('選擇夜市：18 攤可以捲動，打開時會捲到最新解鎖的那一攤', (tester) async {
      await pumpHome(tester, saved: {'unlocked': 15});
      await tapAndSettle(tester, find.byKey(const ValueKey('levels')));
      expect(find.text('大東夜市・台南'), findsOneWidget); // 第 15 攤在畫面內
      await tapAndSettle(tester, find.byKey(const ValueKey('level_14')));
      expect(find.text('大東夜市'), findsOneWidget);
    });

    testWidgets('最後一攤南機場夜市過關，顯示逛完所有夜市', (tester) async {
      await pumpGame(tester, saved: {'unlocked': 18}, level: 17);
      expect(find.text('南機場夜市'), findsOneWidget);
      await solveOnScreen(tester, 17);
      expect(find.text('恭喜逛完所有夜市！'), findsOneWidget);
      expect(find.text('再玩一次'), findsOneWidget);
    });
  });
}
