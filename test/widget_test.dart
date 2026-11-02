import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/game/night_market_data.dart';
import 'package:night_market_match/screens/game_screen.dart';

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
  });

  group('GameScreen', () {
    Future<void> pumpGame(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: GameScreen(random: Random(1))));
    }

    /// 用同樣的種子重建遊戲，得知牌的排列。
    MatchingGame mirror(int level) => MatchingGame(level: levels[level], random: Random(1));

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

    testWidgets('過關後拿到金幣並解鎖下一攤', (tester) async {
      await pumpGame(tester);
      final g = mirror(0);
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
      expect(find.text('收攤！逢甲夜市完成'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);

      await tester.tap(find.text('前往下一攤：士林夜市'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第 2 攤・士林夜市'), findsOneWidget);
      expect(find.text('🪙 260'), findsOneWidget); // (2000 + 60 秒 × 10) / 10
      expect(find.text('夜'), findsNWidgets(16));
    });
  });
}
