import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/endless_game.dart';
import 'package:night_market_match/game/items.dart';
import 'package:night_market_match/game/matching_game.dart' show PickResult;
import 'package:night_market_match/game/night_market_data.dart';

/// 桌上（未配對）各種小吃的張數。
Map<Food, int> countsOf(EndlessGame g) {
  final counts = <Food, int>{};
  for (var i = 0; i < g.cards.length; i++) {
    if (!g.isMatched[i]) counts.update(g.cards[i], (c) => c + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// 找一組桌上完整的對子。
(int, int) anyPair(EndlessGame g) {
  for (var a = 0; a < g.cards.length; a++) {
    if (g.isMatched[a]) continue;
    for (var b = a + 1; b < g.cards.length; b++) {
      if (!g.isMatched[b] && g.cards[a] == g.cards[b]) return (a, b);
    }
  }
  throw StateError('桌上沒有對子');
}

/// 找兩張不是一對的牌。
(int, int) anyMismatch(EndlessGame g) {
  for (var a = 0; a < g.cards.length; a++) {
    for (var b = a + 1; b < g.cards.length; b++) {
      if (!g.isMatched[a] && !g.isMatched[b] && g.cards[a] != g.cards[b]) return (a, b);
    }
  }
  throw StateError('找不到不同的兩張');
}

void matchAny(EndlessGame g) {
  final (a, b) = anyPair(g);
  g.pick(a);
  expect(g.pick(b), PickResult.matched);
}

/// 補牌後桌上必須成立的規則。
void expectBoardHealthy(EndlessGame g, {String reason = ''}) {
  expect(g.isMatched.contains(true), isFalse, reason: '$reason 補完不該有空格');
  final counts = countsOf(g);
  expect(counts.values.every((c) => c <= 2), isTrue, reason: '$reason 同一種小吃最多兩張');
  expect(g.pairsOnBoard, greaterThanOrEqualTo(EndlessGame.minPairsOnBoard), reason: '$reason 對子不夠會死局');
  expect(g.cards.length, g.boardSize);
}

void main() {
  group('EndlessGame 開局', () {
    test('16 張全部成對，時間 60 秒', () {
      final g = EndlessGame(random: Random(1));
      expect(g.cards.length, 16);
      expect(countsOf(g).values.every((c) => c == 2), isTrue);
      expect(countsOf(g).length, 8);
      expect(g.timeLeft, 60);
      expect(g.score, 0);
      expect(g.isEnded, isFalse);
    });

    test('帽子加的秒數同時加在起始時間和上限', () {
      final g = EndlessGame(random: Random(1), bonusSeconds: 4);
      expect(g.timeLeft, 64);
      expect(g.maxSeconds, 64);
    });

    test('reset 重新開一局', () {
      final g = EndlessGame(random: Random(2));
      matchAny(g);
      g.refill();
      g.tick();
      g.reset();
      expect(g.score, 0);
      expect(g.matches, 0);
      expect(g.timeLeft, 60);
      expect(countsOf(g).values.every((c) => c == 2), isTrue);
    });
  });

  group('EndlessGame 計分與時間', () {
    test('配對得分 100 × 連擊，連擊有上限', () {
      final g = EndlessGame(random: Random(3));
      final points = <int>[];
      for (var i = 0; i < 7; i++) {
        matchAny(g);
        points.add(g.lastPoints);
        g.refill();
      }
      expect(points, [100, 200, 300, 400, 500, 500, 500]);
      expect(g.score, 2500);
      expect(g.bestCombo, 5);
    });

    test('攤車提高連擊上限', () {
      final g = EndlessGame(random: Random(3), comboCap: 7);
      for (var i = 0; i < 8; i++) {
        matchAny(g);
        g.refill();
      }
      expect(g.lastPoints, 700);
    });

    test('配對加秒數，不超過上限', () {
      final g = EndlessGame(random: Random(4));
      for (var i = 0; i < 5; i++) {
        g.tick();
      }
      expect(g.timeLeft, 55);
      matchAny(g);
      expect(g.lastTimeGain, 3);
      expect(g.timeLeft, 58);
      g.refill();
      matchAny(g);
      expect(g.timeLeft, 60, reason: '最多回到上限 60 秒');
    });

    test('配對越多，加的秒數越少：3 → 2 → 1', () {
      expect(EndlessGame.timeGainFor(0), 3);
      expect(EndlessGame.timeGainFor(19), 3);
      expect(EndlessGame.timeGainFor(20), 2);
      expect(EndlessGame.timeGainFor(49), 2);
      expect(EndlessGame.timeGainFor(50), 1);
      expect(EndlessGame.timeGainFor(500), 1);
    });

    test('翻錯中斷連擊、不扣時間，蓋回去前不能再翻', () {
      final g = EndlessGame(random: Random(5));
      matchAny(g);
      g.refill();
      expect(g.combo, 2);
      final (a, b) = anyMismatch(g);
      final before = g.timeLeft;
      g.pick(a);
      expect(g.pick(b), PickResult.mismatched);
      expect(g.combo, 1);
      expect(g.mistakes, 1);
      expect(g.timeLeft, before);
      expect(g.isLocked, isTrue);
      final other = List.generate(16, (i) => i).firstWhere((i) => i != a && i != b);
      expect(g.pick(other), PickResult.ignored);
      g.hideMismatched();
      expect(g.isOpen[a] || g.isOpen[b], isFalse);
      expect(g.isLocked, isFalse);
    });

    test('護身符擋下一次翻錯', () {
      final g = EndlessGame(random: Random(5));
      matchAny(g);
      g.refill();
      expect(g.useItem(ItemType.charm), isTrue);
      final (a, b) = anyMismatch(g);
      g.pick(a);
      g.pick(b);
      expect(g.combo, 2, reason: '護身符生效，連擊不中斷');
      expect(g.charmActive, isFalse);
    });

    test('不能翻已經翻開或已配對的牌', () {
      final g = EndlessGame(random: Random(6));
      final (a, b) = anyPair(g);
      g.pick(a);
      expect(g.pick(a), PickResult.ignored);
      g.pick(b);
      expect(g.pick(a), PickResult.ignored, reason: '已配對、還沒補牌');
    });
  });

  group('EndlessGame 補牌', () {
    test('只補已配對的格子，補完蓋著', () {
      final g = EndlessGame(random: Random(7));
      final (a, b) = anyPair(g);
      final untouched = [for (var i = 0; i < 16; i++) if (i != a && i != b) g.cards[i]];
      g.pick(a);
      g.pick(b);
      final filled = g.refill();
      expect(filled, [a, b]..sort());
      expect(g.lastRefilled, filled);
      expect(g.isOpen[a] || g.isOpen[b], isFalse);
      expect([for (var i = 0; i < 16; i++) if (i != a && i != b) g.cards[i]], untouched);
    });

    test('同一批補上的牌彼此一定不是一對（各種種子都檢查）', () {
      for (var seed = 0; seed < 200; seed++) {
        final g = EndlessGame(random: Random(seed));
        for (var m = 0; m < 60; m++) {
          matchAny(g);
          final filled = g.refill();
          final foods = [for (final i in filled) g.cards[i]];
          expect(foods.toSet().length, foods.length, reason: 'seed $seed 第 $m 組：剛補上的兩張是一對');
        }
      }
    });

    test('連續配對兩組才補牌，四格一起補也不會互相成對', () {
      for (var seed = 0; seed < 100; seed++) {
        final g = EndlessGame(random: Random(seed));
        for (var round = 0; round < 20; round++) {
          matchAny(g);
          matchAny(g);
          final filled = g.refill();
          expect(filled.length, 4);
          final foods = [for (final i in filled) g.cards[i]];
          expect(foods.toSet().length, 4, reason: 'seed $seed');
          expectBoardHealthy(g, reason: 'seed $seed');
        }
      }
    });

    test('長時間遊玩：每次補牌後都不會死局、不會超過兩張', () {
      for (var seed = 0; seed < 300; seed++) {
        final g = EndlessGame(random: Random(seed));
        for (var m = 0; m < 200; m++) {
          matchAny(g);
          g.refill();
          expectBoardHealthy(g, reason: 'seed $seed 第 $m 組');
        }
      }
    });

    test('對子快用完時，補牌會優先補成對（防死局的安全網）', () {
      // 正常遊玩很少走到這裡，所以直接擺出極端的桌面：只有 2 組對子，其餘 12 張都落單
      for (var seed = 0; seed < 300; seed++) {
        final g = EndlessGame(random: Random(seed));
        g.matches = 80; // 20 種小吃都已開放
        g.cards = [foods[0], foods[0], foods[1], foods[1], for (var i = 2; i < 14; i++) foods[i]];
        expect(g.pairsOnBoard, 2);
        expect(g.singlesOnBoard, 12);
        g.pick(0);
        g.pick(1);
        expect(g.pairsOnBoard, 1);
        g.refill();
        expectBoardHealthy(g, reason: 'seed $seed');
      }
    });

    test('越玩越難：小吃種類增加，桌上開始出現落單的牌', () {
      final g = EndlessGame(random: Random(8));
      expect(g.activeKinds, 10);
      var maxSingles = 0;
      final seen = <Food>{};
      for (var m = 0; m < 120; m++) {
        matchAny(g);
        g.refill();
        maxSingles = max(maxSingles, g.singlesOnBoard);
        seen.addAll(g.cards);
      }
      expect(g.activeKinds, foods.length, reason: '最後 20 種小吃都會出現');
      expect(seen.length, foods.length);
      expect(maxSingles, greaterThanOrEqualTo(4), reason: '後期要記的落單牌變多');
    });

    test('只出現目前開放的小吃種類', () {
      for (var seed = 0; seed < 50; seed++) {
        final g = EndlessGame(random: Random(seed));
        final allowed = <Food>{...g.cards};
        for (var m = 0; m < 7; m++) {
          matchAny(g);
          g.refill();
          allowed.addAll(g.cards);
        }
        expect(allowed.length, lessThanOrEqualTo(10), reason: 'seed $seed：前 8 組只會用到 10 種');
      }
    });
  });

  group('EndlessGame 結束、續命與道具', () {
    test('時間到結束，結束後不能翻牌', () {
      final g = EndlessGame(random: Random(9));
      for (var i = 0; i < 59; i++) {
        expect(g.tick(), isFalse);
      }
      expect(g.tick(), isTrue);
      expect(g.isEnded, isTrue);
      expect(g.pick(0), PickResult.ignored);
      expect(g.tick(), isFalse);
    });

    test('看廣告續命一次 15 秒，翻錯中的牌會蓋回去', () {
      final g = EndlessGame(random: Random(9));
      final (a, b) = anyMismatch(g);
      g.pick(a);
      g.pick(b);
      while (!g.tick()) {}
      expect(g.revive(), isTrue);
      expect(g.timeLeft, 15);
      expect(g.isEnded, isFalse);
      expect(g.isLocked, isFalse);
      while (!g.tick()) {}
      expect(g.canRevive, isFalse);
      expect(g.revive(), isFalse);
    });

    test('金幣：結束後才結算，每 20 分 1 枚，算盤和招財貓會加成', () {
      final g = EndlessGame(random: Random(10), coinMultiplier: 1.2);
      g.useItem(ItemType.luckyCat);
      for (var i = 0; i < 3; i++) {
        matchAny(g);
        g.refill();
      }
      expect(g.score, 600);
      expect(g.coinsEarned, 0, reason: '還沒結束');
      while (!g.tick()) {}
      expect(g.coinsEarned, (600 / 20 * 1.2 * 1.5).round(), reason: '無盡模式每 20 分換 1 枚金幣');
    });

    test('沙漏可以超過時間上限', () {
      final g = EndlessGame(random: Random(11));
      g.useItem(ItemType.hourglass);
      expect(g.timeLeft, 70);
      matchAny(g);
      expect(g.timeLeft, 70, reason: '已經超過上限，配對不加也不扣');
    });

    test('道具每局每種限用一次', () {
      final g = EndlessGame(random: Random(11));
      expect(g.useItem(ItemType.hourglass), isTrue);
      expect(g.useItem(ItemType.hourglass), isFalse);
    });

    test('放大鏡：翻開的那張另一半在桌上，就配那一張', () {
      final g = EndlessGame(random: Random(12));
      final (a, b) = anyPair(g);
      g.pick(a);
      expect(g.useItem(ItemType.magnifier), isTrue);
      expect(g.lastMatchedCards, [a, b]);
      expect(g.score, 100);
      expect(g.firstPickedIndex, isNull);
    });

    test('放大鏡：翻開的那張是落單牌，就蓋回去改配別組', () {
      // 玩到桌上有落單牌
      final g = EndlessGame(random: Random(13));
      while (g.singlesOnBoard == 0) {
        matchAny(g);
        g.refill();
      }
      final counts = countsOf(g);
      final single = List.generate(16, (i) => i).firstWhere((i) => counts[g.cards[i]] == 1);
      g.pick(single);
      final scoreBefore = g.score;
      expect(g.useItem(ItemType.magnifier), isTrue);
      expect(g.isOpen[single], isFalse);
      expect(g.isMatched[single], isFalse);
      expect(g.lastMatchedCards, isNot(contains(single)));
      expect(g.score, greaterThan(scoreBefore));
      g.refill();
      expectBoardHealthy(g);
    });

    test('開局翻牌：全部翻開、不能翻牌、不倒數、不能偷看，也不會用掉偷看', () {
      final g = EndlessGame(random: Random(15));
      g.startPreview();
      expect(List.generate(16, g.isFaceUp).every((up) => up), isTrue);
      expect(g.pick(0), PickResult.ignored);
      expect(g.tick(), isFalse);
      expect(g.timeLeft, 60);
      expect(g.canPeek, isFalse);
      g.endPreview();
      expect(List.generate(16, g.isFaceUp).any((up) => up), isFalse);
      expect(g.canPeek, isTrue, reason: '開局翻牌不會用掉偷看');
      expect(g.pick(0), PickResult.firstPicked);
    });

    test('「新」標記：沒看過的是新的；翻過、開局翻牌、偷看都算看過；補上的牌又是新的', () {
      final g = EndlessGame(random: Random(16));
      expect(List.generate(16, g.isNew).every((n) => n), isTrue);
      g.startPreview();
      g.endPreview();
      expect(List.generate(16, g.isNew).any((n) => n), isFalse, reason: '開局翻牌全部看過');

      final (a, b) = anyPair(g);
      g.pick(a);
      g.pick(b);
      expect(g.isNew(a), isFalse, reason: '已配對的不標');
      final filled = g.refill();
      for (final i in filled) {
        expect(g.isNew(i), isTrue, reason: '補上的牌是新的');
      }
      g.pick(filled.first);
      expect(g.isNew(filled.first), isFalse, reason: '翻過就不是新的');
      g.hideMismatched();

      final g2 = EndlessGame(random: Random(17));
      g2.startPeek();
      expect(List.generate(16, g2.isNew).any((n) => n), isFalse, reason: '偷看全部看過');
    });

    test('老闆提示：連錯 2 次給一組對子，配對會歸零，提示後要再配 3 組才會再給', () {
      final g = EndlessGame(random: Random(18));
      void miss() {
        final (a, b) = anyMismatch(g);
        g.pick(a);
        g.pick(b);
        g.hideMismatched();
      }

      miss();
      expect(g.takeBossHint(), isNull, reason: '才錯 1 次');
      matchAny(g);
      g.refill();
      miss();
      expect(g.takeBossHint(), isNull, reason: '中間配對成功，連錯歸零');
      miss();
      final hint = g.takeBossHint();
      expect(hint, isNotNull);
      expect(g.cards[hint![0]], g.cards[hint[1]], reason: '提示的是一對');
      expect(g.isMatched[hint[0]] || g.isMatched[hint[1]], isFalse);
      expect(g.isNew(hint[0]) || g.isNew(hint[1]), isFalse, reason: '提示過就算看過');

      miss();
      miss();
      expect(g.takeBossHint(), isNull, reason: '冷卻中');
      for (var i = 0; i < EndlessGame.bossHintCooldownMatches; i++) {
        matchAny(g);
        g.refill();
      }
      miss();
      miss();
      expect(g.takeBossHint(), isNotNull, reason: '配了 3 組，冷卻結束');
    });

    test('老闆提示不會打亂之後的補牌（不用共用的亂數）', () {
      final a = EndlessGame(random: Random(19));
      final b = EndlessGame(random: Random(19));
      for (final g in [a, b]) {
        final (x, y) = anyMismatch(g);
        g.pick(x);
        g.pick(y);
        g.hideMismatched();
        final (p, q) = anyMismatch(g);
        g.pick(p);
        g.pick(q);
        g.hideMismatched();
      }
      expect(a.takeBossHint(), isNotNull); // 只有 a 拿提示
      for (var i = 0; i < 10; i++) {
        matchAny(a);
        matchAny(b);
        a.refill();
        b.refill();
      }
      expect(a.cards, b.cards);
    });

    test('偷看每局一次，偷看中不能翻牌', () {
      final g = EndlessGame(random: Random(14));
      expect(g.startPeek(), isTrue);
      expect(g.isFaceUp(0), isTrue);
      expect(g.pick(0), PickResult.ignored);
      g.endPeek();
      expect(g.isFaceUp(0), isFalse);
      expect(g.startPeek(), isFalse);
    });
  });
}
