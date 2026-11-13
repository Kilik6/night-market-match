import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/endless_game.dart';
import 'package:night_market_match/game/items.dart';
import 'package:night_market_match/game/matching_game.dart' show PickResult;
import 'package:night_market_match/game/night_market_data.dart';

/// 找一組桌上完整的對子。
(int, int) anyPair(EndlessGame g) {
  for (var a = 0; a < g.boardSize; a++) {
    if (g.isMatched[a]) continue;
    for (var b = a + 1; b < g.boardSize; b++) {
      if (!g.isMatched[b] && g.cards[a] == g.cards[b]) return (a, b);
    }
  }
  throw StateError('桌上沒有對子');
}

/// 找兩張不是一對的牌。
(int, int) anyMismatch(EndlessGame g) {
  for (var a = 0; a < g.boardSize; a++) {
    for (var b = a + 1; b < g.boardSize; b++) {
      if (!g.isMatched[a] && !g.isMatched[b] && g.cards[a] != g.cards[b]) return (a, b);
    }
  }
  throw StateError('找不到不同的兩張');
}

PickResult matchAny(EndlessGame g) {
  final (a, b) = anyPair(g);
  g.pick(a);
  return g.pick(b);
}

/// 把這一桌清完（不發下一桌）。
void clearTable(EndlessGame g) {
  while (!g.tableCleared) {
    matchAny(g);
  }
}

void main() {
  group('EndlessGame 開局', () {
    test('第 1 桌 2×2：4 張、2 組，時間 60 秒', () {
      final g = EndlessGame(random: Random(1));
      expect(g.table, 1);
      expect(g.boardSize, 4);
      expect(g.columns, 2);
      expect(g.cards.toSet().length, 2);
      for (final f in g.cards.toSet()) {
        expect(g.cards.where((c) => c == f).length, 2);
      }
      expect(g.timeLeft, 60);
      expect(g.score, 0);
    });

    test('帽子加的秒數同時加在起始時間和上限', () {
      final g = EndlessGame(random: Random(1), bonusSeconds: 4);
      expect(g.timeLeft, 64);
      expect(g.maxSeconds, 64);
    });

    test('reset 回到第 1 桌、分數歸零', () {
      final g = EndlessGame(random: Random(2));
      clearTable(g);
      g.nextTable();
      g.tick();
      g.reset();
      expect(g.table, 1);
      expect(g.boardSize, 4);
      expect(g.score, 0);
      expect(g.matches, 0);
      expect(g.tablesCleared, 0);
      expect(g.timeLeft, 60);
    });
  });

  group('EndlessGame 一桌一桌清', () {
    test('牌桌大小：第 1～2 桌 2×2、第 3～5 桌 3×2、第 6～9 桌 4×2、第 10 桌起 4×4', () {
      final expected = {1: (4, 2), 2: (4, 2), 3: (6, 3), 5: (6, 3), 6: (8, 4), 9: (8, 4), 10: (16, 4), 30: (16, 4)};
      expected.forEach((table, size) {
        expect(EndlessGame.cardsForTable(table), size.$1, reason: '第 $table 桌張數');
        expect(EndlessGame.columnsForTable(table), size.$2, reason: '第 $table 桌欄數');
      });
    });

    test('配對成功的牌消掉、位置空著，不會補牌', () {
      final g = EndlessGame(random: Random(3));
      final (a, b) = anyPair(g);
      final before = g.cards.toList();
      g.pick(a);
      expect(g.pick(b), PickResult.matched);
      expect(g.isMatched[a] && g.isMatched[b], isTrue);
      expect(g.cards, before, reason: '沒有補牌');
      expect(g.pick(a), PickResult.ignored, reason: '消掉的位置不能點');
      expect(g.pairsLeft, 1);
    });

    test('清桌：最後一組回傳 finished，加 500 × 第幾桌和 5 秒，計時暫停、不能翻牌', () {
      final g = EndlessGame(random: Random(4));
      for (var i = 0; i < 20; i++) {
        g.tick();
      }
      expect(g.timeLeft, 40);
      expect(matchAny(g), PickResult.matched);
      expect(matchAny(g), PickResult.finished);
      expect(g.tableCleared, isTrue);
      expect(g.tablesCleared, 1);
      expect(g.lastClearBonus, 500);
      expect(g.score, 100 + 200 + 500);
      expect(g.timeLeft, 40 + 3 + 3 + 5);
      expect(g.tick(), isFalse);
      expect(g.timeLeft, 51, reason: '清桌動畫期間不倒數');
      expect(g.isLocked, isTrue);
      expect(g.canPeek, isFalse);
    });

    test('nextTable：發下一桌全新的牌，連擊和分數延續', () {
      final g = EndlessGame(random: Random(5));
      clearTable(g);
      final combo = g.combo;
      final score = g.score;
      g.nextTable();
      expect(g.table, 2);
      expect(g.tableCleared, isFalse);
      expect(g.isMatched.any((m) => m), isFalse);
      expect(g.isOpen.any((o) => o), isFalse);
      expect(g.combo, combo, reason: '連擊延續到下一桌');
      expect(g.score, score);
      g.nextTable();
      expect(g.table, 2, reason: '沒清桌不能跳下一桌');
    });

    test('清桌獎勵隨桌數增加；一路清到第 12 桌牌桌大小都正確、每桌都成對', () {
      final g = EndlessGame(random: Random(6));
      for (var t = 1; t <= 12; t++) {
        expect(g.boardSize, EndlessGame.cardsForTable(t), reason: '第 $t 桌');
        for (final f in g.cards.toSet()) {
          expect(g.cards.where((c) => c == f).length, 2, reason: '第 $t 桌每種小吃剛好一對');
        }
        final before = g.score;
        clearTable(g);
        expect(g.lastClearBonus, 500 * t);
        expect(g.score - before, greaterThanOrEqualTo(500 * t));
        g.nextTable();
      }
      expect(g.tablesCleared, 12);
    });

    test('時間上限：配對和清桌加的秒數不超過 60 秒', () {
      final g = EndlessGame(random: Random(7));
      clearTable(g);
      expect(g.timeLeft, 60);
    });
  });

  group('EndlessGame 計分', () {
    test('配對得分 100 × 連擊，連擊有上限，跨桌延續', () {
      final g = EndlessGame(random: Random(8));
      final points = <int>[];
      for (var i = 0; i < 7; i++) {
        if (g.tableCleared) g.nextTable();
        matchAny(g);
        points.add(g.lastPoints);
      }
      expect(points, [100, 200, 300, 400, 500, 500, 500]);
      expect(g.bestCombo, 5);
    });

    test('攤車提高連擊上限', () {
      final g = EndlessGame(random: Random(8), comboCap: 7);
      for (var i = 0; i < 8; i++) {
        if (g.tableCleared) g.nextTable();
        matchAny(g);
      }
      expect(g.lastPoints, 700);
    });

    test('配對越多，加的秒數越少：3 → 2 → 1', () {
      expect(EndlessGame.timeGainFor(0), 3);
      expect(EndlessGame.timeGainFor(19), 3);
      expect(EndlessGame.timeGainFor(20), 2);
      expect(EndlessGame.timeGainFor(49), 2);
      expect(EndlessGame.timeGainFor(50), 1);
    });

    test('翻錯中斷連擊、不扣時間，蓋回去前不能再翻', () {
      final g = EndlessGame(random: Random(9));
      clearTable(g);
      g.nextTable();
      clearTable(g);
      g.nextTable();
      expect(g.boardSize, 6);
      expect(g.combo, greaterThan(1));
      final (a, b) = anyMismatch(g);
      final time = g.timeLeft;
      g.pick(a);
      expect(g.pick(b), PickResult.mismatched);
      expect(g.combo, 1);
      expect(g.mistakes, 1);
      expect(g.timeLeft, time);
      expect(g.isLocked, isTrue);
      g.hideMismatched();
      expect(g.isLocked, isFalse);
    });

    test('護身符擋下一次翻錯', () {
      final g = EndlessGame(random: Random(9));
      clearTable(g);
      g.nextTable();
      g.useItem(ItemType.charm);
      final combo = g.combo;
      final (a, b) = anyMismatch(g);
      g.pick(a);
      g.pick(b);
      expect(g.combo, combo);
      expect(g.charmActive, isFalse);
    });
  });

  group('EndlessGame 結束、續命與道具', () {
    test('時間到結束，結束後不能翻牌', () {
      final g = EndlessGame(random: Random(10));
      for (var i = 0; i < 59; i++) {
        expect(g.tick(), isFalse);
      }
      expect(g.tick(), isTrue);
      expect(g.isEnded, isTrue);
      expect(g.pick(0), PickResult.ignored);
    });

    test('看廣告續命一次 15 秒，翻錯中的牌會蓋回去', () {
      final g = EndlessGame(random: Random(10));
      final (a, b) = anyMismatch(g);
      g.pick(a);
      g.pick(b);
      while (!g.tick()) {}
      expect(g.revive(), isTrue);
      expect(g.timeLeft, 15);
      expect(g.isLocked, isFalse);
      while (!g.tick()) {}
      expect(g.revive(), isFalse);
    });

    test('金幣：結束後才結算，每 200 分 1 枚，算盤和招財貓會加成', () {
      final g = EndlessGame(random: Random(11), coinMultiplier: 1.2);
      g.useItem(ItemType.luckyCat);
      clearTable(g); // 100 + 200 + 清桌 500
      expect(g.score, 800);
      expect(g.coinsEarned, 0);
      g.nextTable();
      while (!g.tick()) {}
      expect(g.coinsEarned, (800 / 200 * 1.2 * 1.5).round());
      expect(EndlessGame.scorePerCoin, 200, reason: '100000 分約換 500 枚');
    });

    test('沙漏可以超過時間上限', () {
      final g = EndlessGame(random: Random(12));
      g.useItem(ItemType.hourglass);
      expect(g.timeLeft, 70);
      matchAny(g);
      expect(g.timeLeft, 70);
    });

    test('放大鏡：翻開的那張就配它的另一半；配到最後一組會清桌', () {
      final g = EndlessGame(random: Random(13));
      final (a, b) = anyPair(g);
      g.pick(a);
      expect(g.useItem(ItemType.magnifier), isTrue);
      expect(g.lastMatchedCards, [a, b]);
      expect(g.useItem(ItemType.magnifier), isFalse, reason: '每局一次');

      final g2 = EndlessGame(random: Random(14));
      matchAny(g2);
      g2.useItem(ItemType.magnifier);
      expect(g2.tableCleared, isTrue);
      expect(g2.lastClearBonus, 500);
    });

    test('翻牌記憶：全部翻開、不能翻牌、不倒數、不能偷看，也不會用掉偷看', () {
      final g = EndlessGame(random: Random(15));
      g.startPreview();
      expect(List.generate(g.boardSize, g.isFaceUp).every((up) => up), isTrue);
      expect(g.pick(0), PickResult.ignored);
      expect(g.tick(), isFalse);
      expect(g.canPeek, isFalse);
      g.endPreview();
      expect(List.generate(g.boardSize, g.isFaceUp).any((up) => up), isFalse);
      expect(g.canPeek, isTrue);
    });

    test('偷看每局一次，偷看中不能翻牌', () {
      final g = EndlessGame(random: Random(16));
      expect(g.startPeek(), isTrue);
      expect(g.pick(0), PickResult.ignored);
      g.endPeek();
      expect(g.startPeek(), isFalse);
    });

    test('老闆提示：連錯 2 次給一組對子，配對會歸零，提示後要再配 3 組才會再給', () {
      final g = EndlessGame(random: Random(18));
      // 先到 4×4 的桌，牌夠多才好測
      while (g.table < 10) {
        clearTable(g);
        g.nextTable();
      }
      void miss() {
        final (a, b) = anyMismatch(g);
        g.pick(a);
        g.pick(b);
        g.hideMismatched();
      }

      miss();
      expect(g.takeBossHint(), isNull, reason: '才錯 1 次');
      matchAny(g);
      miss();
      expect(g.takeBossHint(), isNull, reason: '中間配對成功，連錯歸零');
      miss();
      final hint = g.takeBossHint();
      expect(hint, isNotNull);
      expect(g.cards[hint![0]], g.cards[hint[1]]);
      miss();
      miss();
      expect(g.takeBossHint(), isNull, reason: '冷卻中');
      for (var i = 0; i < EndlessGame.bossHintCooldownMatches; i++) {
        matchAny(g);
      }
      miss();
      miss();
      expect(g.takeBossHint(), isNotNull, reason: '配了 3 組，冷卻結束');
    });

    test('大胃王背包：清桌獎勵依倍率增加', () {
      final g = EndlessGame(random: Random(20), clearBonusMultiplier: 1.2);
      clearTable(g);
      expect(g.lastClearBonus, 600);
    });

    test('老闆的人情：冷卻變短，最少 1 組', () {
      final g = EndlessGame(random: Random(21), bossHintCooldown: 1);
      while (g.table < 10) {
        clearTable(g);
        g.nextTable();
      }
      void miss() {
        final (a, b) = anyMismatch(g);
        g.pick(a);
        g.pick(b);
        g.hideMismatched();
      }

      miss();
      miss();
      expect(g.takeBossHint(), isNotNull);
      matchAny(g); // 只配 1 組就過了冷卻
      miss();
      miss();
      expect(g.takeBossHint(), isNotNull);
      final zero = EndlessGame(random: Random(21), bossHintCooldown: 0);
      for (final x in [zero]) {
        while (x.table < 10) {
          clearTable(x);
          x.nextTable();
        }
        final (a, b) = anyMismatch(x);
        x.pick(a);
        x.pick(b);
        x.hideMismatched();
        final (c, d) = anyMismatch(x);
        x.pick(c);
        x.pick(d);
        x.hideMismatched();
        expect(x.takeBossHint(), isNotNull);
        final (e, f) = anyMismatch(x);
        x.pick(e);
        x.pick(f);
        x.hideMismatched();
        final (h, k) = anyMismatch(x);
        x.pick(h);
        x.pick(k);
        x.hideMismatched();
        expect(x.takeBossHint(), isNull, reason: '冷卻最少 1 組，不會連續拿提示');
      }
    });

    test('保溫便當袋：翻錯時連擊只少 1 段；Lv.2 每輪第一次翻錯不扣', () {
      final g = EndlessGame(random: Random(22), comboKeepOnMiss: true, firstMissForgiven: true);
      while (g.boardSize < 6) {
        clearTable(g);
        g.nextTable();
      }
      matchAny(g);
      final combo = g.combo;
      expect(combo, greaterThan(2));
      void miss() {
        final (a, b) = anyMismatch(g);
        g.pick(a);
        g.pick(b);
        g.hideMismatched();
      }

      miss();
      expect(g.combo, combo, reason: '第一次翻錯不扣');
      miss();
      expect(g.combo, combo - 1, reason: '之後只少 1 段');
      expect(g.mistakes, 2, reason: '翻錯次數照算');
    });

    test('老闆提示不會打亂之後的發牌（不用共用的亂數）', () {
      final a = EndlessGame(random: Random(19));
      final b = EndlessGame(random: Random(19));
      for (final g in [a, b]) {
        clearTable(g);
        g.nextTable();
        clearTable(g);
        g.nextTable();
        for (var i = 0; i < 2; i++) {
          final (x, y) = anyMismatch(g);
          g.pick(x);
          g.pick(y);
          g.hideMismatched();
        }
      }
      expect(a.takeBossHint(), isNotNull); // 只有 a 拿提示
      for (final g in [a, b]) {
        clearTable(g);
        g.nextTable();
      }
      expect(a.cards, b.cards);
    });
  });

  test('小吃池至少要能擺滿最大的一桌', () {
    expect(foods.length, greaterThanOrEqualTo(EndlessGame.maxCards ~/ 2));
  });
}
