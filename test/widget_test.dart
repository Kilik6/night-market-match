import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/screens/game_screen.dart';

/// 找出和 index 配對的另一張牌，或第一張不同的牌。
int pairOf(MatchingGame g, int i) =>
    List.generate(g.cards.length, (j) => j).firstWhere((j) => j != i && g.cards[j] == g.cards[i]);
int differentFrom(MatchingGame g, int i) =>
    List.generate(g.cards.length, (j) => j).firstWhere((j) => g.cards[j] != g.cards[i]);

void main() {
  group('MatchingGame', () {
    test('開局有 16 張牌、每個符號各 2 張、全部蓋著', () {
      final g = MatchingGame(random: Random(1));
      expect(g.cards.length, 16);
      for (final s in MatchingGame.defaultSymbols) {
        expect(g.cards.where((c) => c == s).length, 2);
      }
      expect(g.isOpen.every((o) => !o), isTrue);
      expect(g.steps, 0);
    });

    test('配對成功會保持翻開', () {
      final g = MatchingGame(random: Random(1));
      expect(g.pick(0), PickResult.firstPicked);
      expect(g.pick(pairOf(g, 0)), PickResult.matched);
      expect(g.isOpen.where((o) => o).length, 2);
      expect(g.steps, 2);
    });

    test('翻錯後鎖住：等待期間點牌不翻開、也不增加步數（修正 RN 版問題）', () {
      final g = MatchingGame(random: Random(1));
      final wrong = differentFrom(g, 0);
      g.pick(0);
      expect(g.pick(wrong), PickResult.mismatched);
      expect(g.isLocked, isTrue);

      final other = List.generate(16, (j) => j).firstWhere((j) => j != 0 && j != wrong);
      expect(g.pick(other), PickResult.ignored);
      expect(g.isOpen[other], isFalse);
      expect(g.steps, 2);

      g.hideMismatched();
      expect(g.isOpen[0], isFalse);
      expect(g.isOpen[wrong], isFalse);
      expect(g.isLocked, isFalse);
    });

    test('點已翻開的牌不算步數', () {
      final g = MatchingGame(random: Random(1));
      g.pick(0);
      expect(g.pick(0), PickResult.ignored);
      expect(g.steps, 1);
    });

    test('全部配對完成就結束，重玩會歸零', () {
      final g = MatchingGame(random: Random(1));
      for (var i = 0; i < g.cards.length; i++) {
        if (g.isOpen[i]) continue;
        g.pick(i);
        g.pick(pairOf(g, i));
      }
      expect(g.isEnded, isTrue);
      expect(g.steps, 16);

      g.reset();
      expect(g.isEnded, isFalse);
      expect(g.steps, 0);
      expect(g.isOpen.every((o) => !o), isTrue);
    });
  });

  testWidgets('畫面：翻錯 1 秒後蓋回、完成後出現 Try Again', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final g = MatchingGame(random: Random(1));
    await tester.pumpWidget(MaterialApp(home: GameScreen(game: g)));
    expect(find.text('FC Matching Game'), findsOneWidget);
    expect(find.text('?'), findsNWidgets(16));

    final wrong = differentFrom(g, 0);
    await tester.tap(find.byKey(const ValueKey('card_0')));
    await tester.tap(find.byKey(ValueKey('card_$wrong')));
    await tester.pump();
    expect(find.text('?'), findsNWidgets(14));
    expect(find.text('You have tried 2 time(s).'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('?'), findsNWidgets(16));

    for (var i = 0; i < 16; i++) {
      if (g.isOpen[i]) continue;
      await tester.tap(find.byKey(ValueKey('card_$i')));
      await tester.tap(find.byKey(ValueKey('card_${pairOf(g, i)}')));
      await tester.pump();
    }
    expect(find.text('Congrats! You have completed in 18 steps.'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    expect(find.text('You have tried 0 time(s).'), findsOneWidget);
  });
}
