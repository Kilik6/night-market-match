import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/game/night_market_data.dart';
import 'package:night_market_match/screens/game_screen.dart';
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

  group('GameScreen', () {
    late FakeAdService ads;
    late FakeSoundService sounds;

    Future<ProgressStore> pumpGame(WidgetTester tester, [Map<String, Object> saved = const {}]) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(saved);
      final store = await ProgressStore.load();
      ads = FakeAdService();
      sounds = FakeSoundService()..muted = store.muted;
      await tester.pumpWidget(
          MaterialApp(home: GameScreen(store: store, ads: ads, sounds: sounds, random: Random(1))));
      return store;
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

    testWidgets('開局：逢甲夜市 12 張蓋著的牌，其他夜市上鎖', (tester) async {
      await pumpGame(tester);
      expect(find.text('第 1 攤・逢甲夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(12));
      expect(find.text('🔒 士林夜市'), findsOneWidget);
      expect(find.text('🔒 六合夜市'), findsOneWidget);
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

    testWidgets('過關：金幣和解鎖寫進存檔，下次打開從新的一攤開始', (tester) async {
      final store = await pumpGame(tester);
      await solveOnScreen(tester, 0);
      expect(find.text('收攤！逢甲夜市完成'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);

      await tester.tap(find.text('前往下一攤：士林夜市'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第 2 攤・士林夜市'), findsOneWidget);
      expect(find.text('🪙 260'), findsOneWidget); // (2000 + 60 秒 × 10) / 10
      expect(find.text('夜'), findsNWidgets(16));
      expect(store.coins, 260);
      expect(store.unlocked, 2);
      expect(store.clears, 1);
      expect(ads.rewardedShown, 0);

      // 模擬重新打開 App：讀同一份存檔
      await tester.pumpWidget(const SizedBox());
      final reopened = await ProgressStore.load();
      await tester.pumpWidget(MaterialApp(home: GameScreen(store: reopened, ads: ads, sounds: sounds, random: Random(1))));
      expect(find.text('第 2 攤・士林夜市'), findsOneWidget);
      expect(find.text('🪙 260'), findsOneWidget);
      expect(find.text('🔒 士林夜市'), findsNothing);
    });

    testWidgets('過關看廣告，金幣 ×2', (tester) async {
      final store = await pumpGame(tester);
      await solveOnScreen(tester, 0);
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ads.rewardedShown, 1);
      expect(store.coins, 520);
      expect(find.text('🪙 520'), findsOneWidget);
    });

    testWidgets('第 3 次過關播插頁式廣告；看過獎勵型廣告的那次不播', (tester) async {
      await pumpGame(tester, {'clears': 2});
      await solveOnScreen(tester, 0);
      await tester.tap(find.text('前往下一攤：士林夜市'));
      await tester.pump();
      expect(ads.interstitialShown, 1);

      await tester.pumpWidget(const SizedBox()); // 清掉畫面，重新開一局
      await pumpGame(tester, {'clears': 2});
      await solveOnScreen(tester, 0);
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      expect(ads.interstitialShown, 0);
    });

    testWidgets('看廣告偷看全部 2 秒，每局只能一次', (tester) async {
      await pumpGame(tester);
      await tester.tap(find.byKey(const ValueKey('peek')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ads.rewardedShown, 1);
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

    testWidgets('靜音按鈕：關掉後不播音效，並記在存檔裡', (tester) async {
      final store = await pumpGame(tester);
      await tester.tap(find.byKey(const ValueKey('mute')));
      await tester.pump();
      expect(store.muted, isTrue);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('card_0')));
      await tester.pump();
      expect(sounds.played, isEmpty);

      await tester.tap(find.byKey(const ValueKey('mute')));
      await tester.pump();
      expect(store.muted, isFalse);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });
  });
}
