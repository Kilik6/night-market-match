import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/endless_game.dart';
import 'package:night_market_match/game/items.dart';
import 'package:night_market_match/game/matching_game.dart' show PickResult;
import 'package:night_market_match/game/night_market_data.dart';

/// 桌上有牌的格子。
List<int> filled(EndlessGame g) => [
      for (var i = 0; i < EndlessGame.capacity; i++)
        if (g.slots[i] != null) i
    ];

/// 找一組桌上的對子。
(int, int) anyPair(EndlessGame g) {
  final cards = filled(g);
  for (final a in cards) {
    for (final b in cards) {
      if (b > a && g.slots[a] == g.slots[b]) return (a, b);
    }
  }
  throw StateError('桌上沒有對子');
}

/// 找兩張不是一對的牌。
(int, int) anyMismatch(EndlessGame g) {
  final cards = filled(g);
  for (final a in cards) {
    for (final b in cards) {
      if (b > a && g.slots[a] != g.slots[b]) return (a, b);
    }
  }
  throw StateError('找不到不同的兩張');
}

PickResult matchAny(EndlessGame g) {
  final (a, b) = anyPair(g);
  g.pick(a);
  return g.pick(b);
}

/// 翻錯一次並蓋回去（老闆會加菜）。
void miss(EndlessGame g) {
  final (a, b) = anyMismatch(g);
  g.pick(a);
  g.pick(b);
  g.hideMismatched();
}

/// 把桌上全部吃光（不上下一波）。
void clearBoard(EndlessGame g) {
  while (!g.boardCleared) {
    matchAny(g);
  }
}

/// 開局只有一組，沒辦法翻錯；先吃光上第 2 波（2 組）。
EndlessGame ready(int seed) {
  final g = EndlessGame(random: Random(seed));
  clearBoard(g);
  g.nextWave();
  return g;
}

/// 一直翻錯到桌子塞滿結束。
void missUntilFull(EndlessGame g) {
  while (!g.isEnded) {
    miss(g);
  }
}

/// 每一組都是兩張一樣的、而且桌上每一組都不一樣。
void expectPairsValid(EndlessGame g) {
  final counts = <Food, int>{};
  for (final f in g.slots.whereType<Food>()) {
    counts[f] = (counts[f] ?? 0) + 1;
  }
  expect(counts.values.every((c) => c == 2), isTrue, reason: '每種小吃剛好兩張');
}

void main() {
  group('EndlessGame 開局', () {
    test('桌子 5×4 = 20 格，開局只上一組（2 張）', () {
      final g = EndlessGame(random: Random(1));
      expect(EndlessGame.capacity, 20);
      expect(g.slots.length, 20);
      expect(g.cardCount, 2);
      expect(g.wave, 1);
      expect(g.score, 0);
      expect(g.combo, 1);
      expectPairsValid(g);
    });

    test('reset 回到開局、分數歸零', () {
      final g = EndlessGame(random: Random(2));
      matchAny(g);
      g.nextWave();
      miss(g);
      g.reset();
      expect(g.cardCount, 2);
      expect(g.wave, 1);
      expect(g.score, 0);
      expect(g.matches, 0);
      expect(g.mistakes, 0);
      expect(g.allClears, 0);
      expect(g.serveProgress, 0);
      expect(g.isEnded, isFalse);
    });
  });

  group('EndlessGame 上菜與塞滿', () {
    test('配對成功：兩張牌從桌上拿掉', () {
      final g = EndlessGame(random: Random(3));
      g.nextWave(); // 還沒吃光不會上下一波
      expect(g.cardCount, 2);
      matchAny(g);
      expect(g.cardCount, 0);
      expect(g.matches, 1);
    });

    test('翻錯：每翻錯 3 次，蓋回去時老闆多加一組菜；蓋回去前不能再翻', () {
      final g = ready(4); // 第 2 波 2 組
      final before = g.cardCount;
      final (a, b) = anyMismatch(g);
      g.pick(a);
      expect(g.pick(b), PickResult.mismatched);
      final (c, _) = anyPair(g);
      expect(g.pick(c), PickResult.ignored, reason: '翻錯的牌還沒蓋回去');
      g.hideMismatched();
      expect(g.lastMissPenalty, isFalse);
      expect(g.missesUntilPenalty, 2);
      miss(g);
      expect(g.lastMissPenalty, isFalse);
      expect(g.missesUntilPenalty, 1);
      expect(g.cardCount, before, reason: '翻錯 2 次還不加菜（上菜進度也還沒滿）');
      miss(g);
      expect(g.lastMissPenalty, isTrue, reason: '第 3 次加菜');
      expect(g.cardCount, before + 2);
      expect(g.missesUntilPenalty, 3, reason: '重新計算');
      expectPairsValid(g);
    });

    test('翻錯次數不用連續：中間翻對也會累積', () {
      final g = EndlessGame(random: Random(40));
      while (g.pairsLeft < 3) {
        clearBoard(g);
        g.nextWave();
      }
      miss(g);
      miss(g);
      matchAny(g);
      expect(g.missesUntilPenalty, 1);
      miss(g);
      expect(g.lastMissPenalty, isTrue);
    });

    test('新上的菜是蓋著的，桌上每一組小吃都不一樣', () {
      final g = ready(5);
      for (var i = 0; i < 8; i++) {
        miss(g);
      }
      expect(filled(g).every((i) => !g.isFaceUp(i)), isTrue);
      expectPairsValid(g);
    });

    test('上菜進度：每翻一次累積一點，滿了就上一組；吃越多上越快', () {
      final g = EndlessGame(random: Random(6));
      expect(g.serveRate, EndlessGame.serveRateStart);
      expect(g.turnsUntilServe, 5, reason: '一開始約翻 5 次上一組');
      clearBoard(g);
      g.nextWave();
      // 吃光那一回合不上菜；之後每吃一組進度加 serveRate
      final progress = g.serveProgress;
      final rate = g.serveRate;
      matchAny(g);
      expect(g.serveProgress, closeTo(progress + g.serveRate, 1e-9), reason: '吃完這一組後的速度累積上去');
      expect(g.serveRate, closeTo(rate + EndlessGame.serveRateStep, 1e-9), reason: '吃越多上越快');
      g.matches = 1000;
      expect(g.serveRate, 1.0, reason: '最快每翻一次上一組');
    });

    test('一直翻錯：桌子越來越滿，要上菜但塞滿了就結束，不會超過 20 張', () {
      final g = ready(7);
      var last = g.cardCount;
      while (!g.isEnded) {
        miss(g);
        if (!g.isEnded) expect(g.cardCount, greaterThanOrEqualTo(last), reason: '翻錯不會讓牌變少');
        expect(g.cardCount, lessThanOrEqualTo(EndlessGame.capacity));
        last = g.cardCount;
        expectPairsValid(g);
      }
      expect(g.cardCount, EndlessGame.capacity);
      expect(g.pick(filled(g).first), PickResult.ignored, reason: '結束後不能翻牌');
    });
  });

  group('EndlessGame 全部吃光', () {
    test('吃光：回傳 finished，加 500 × 第幾次吃光，不能翻牌，等 nextWave 上下一波', () {
      final g = EndlessGame(random: Random(8));
      expect(matchAny(g), PickResult.finished);
      expect(g.boardCleared, isTrue);
      expect(g.allClears, 1);
      expect(g.lastClearBonus, 500);
      expect(g.score, 100 + 500);
      expect(g.isLocked, isTrue);
      expect(g.lastServedPairs, 0, reason: '吃光那一回合不上菜');
      g.nextWave();
      expect(g.boardCleared, isFalse);
      expect(g.wave, 2);
      expect(g.cardCount, 4, reason: '第 2 波上 2 組');
      expectPairsValid(g);
    });

    test('每一波上的組數：1、2、3、4，之後都是 4 組；吃光獎勵越來越多', () {
      final g = EndlessGame(random: Random(9));
      final sizes = <int>[];
      for (var w = 1; w <= 6; w++) {
        sizes.add(g.pairsLeft);
        clearBoard(g);
        expect(g.lastClearBonus, 500 * w);
        g.nextWave();
      }
      expect(sizes, [1, 2, 3, 4, 4, 4]);
      expect(EndlessGame.pairsForWave(10), EndlessGame.maxWavePairs);
    });

    test('大胃王背包：吃光獎勵依倍率增加', () {
      final g = EndlessGame(random: Random(10), clearBonusMultiplier: 1.2);
      clearBoard(g);
      expect(g.lastClearBonus, 600);
    });
  });

  group('EndlessGame 計分、連擊與大胃王時間', () {
    /// 用沒有上菜的方式準備很多組：一直吃光、上下一波，直到桌上有 [pairs] 組。
    EndlessGame withPairs(int seed, int pairs, {int comboCap = 5}) {
      final g = EndlessGame(random: Random(seed), comboCap: comboCap);
      while (g.pairsLeft < pairs) {
        clearBoard(g);
        g.nextWave();
      }
      g.combo = 1;
      g.streak = 0;
      g.feverLeft = 0;
      return g;
    }

    test('配對得分 100 × 連擊，連擊有上限', () {
      final g = withPairs(11, 4);
      final before = g.score;
      final points = <int>[];
      for (var i = 0; i < 3; i++) {
        matchAny(g);
        points.add(g.lastPoints);
      }
      expect(points, [100, 200, 300]);
      expect(g.score - before, 600);
      g.combo = 5;
      matchAny(g);
      expect(g.combo, 5, reason: '連擊上限 ×5');
    });

    test('攤車提高連擊上限', () {
      final g = EndlessGame(random: Random(12), comboCap: 7);
      g.combo = 7;
      matchAny(g);
      expect(g.lastPoints, 700);
      expect(g.combo, 7);
    });

    test('大胃王時間：連續配對 5 組開始，接下來 5 組分數 ×2，用完結束', () {
      final g = withPairs(13, 4);
      // 準備足夠的對子：連續 10 組不能翻錯，所以每吃光一次就上下一波
      var started = false;
      final doubled = <bool>[];
      for (var i = 0; i < 10; i++) {
        if (g.boardCleared) g.nextWave();
        if (g.pairsLeft == 0) continue;
        matchAny(g);
        if (g.feverJustStarted) {
          started = true;
          expect(i, EndlessGame.feverAt - 1, reason: '第 5 組開始');
          expect(g.lastFever, isFalse, reason: '開始的那一組還沒加倍');
        } else if (started) {
          doubled.add(g.lastFever);
        }
      }
      expect(started, isTrue);
      expect(doubled.take(EndlessGame.feverMatches).every((d) => d), isTrue);
      expect(g.feverActive, isFalse, reason: '5 組用完就結束');
    });

    test('大胃王時間的分數 ×2', () {
      final g = withPairs(14, 3);
      g.combo = 3;
      g.feverLeft = 2;
      matchAny(g);
      expect(g.lastPoints, 100 * 3 * 2);
      expect(g.feverLeft, 1);
    });

    test('翻錯中斷連擊和大胃王時間', () {
      final g = withPairs(15, 4);
      matchAny(g);
      matchAny(g);
      g.feverLeft = 3;
      miss(g);
      expect(g.combo, 1);
      expect(g.feverActive, isFalse);
      expect(g.streak, 0);
      expect(g.mistakes, 1);
    });

    test('護身符擋下一次翻錯：連擊和大胃王時間都保住', () {
      final g = withPairs(16, 4);
      matchAny(g);
      matchAny(g);
      g.feverLeft = 3;
      expect(g.useItem(ItemType.charm), isTrue);
      miss(g);
      expect(g.combo, 3);
      expect(g.feverLeft, 3);
      miss(g);
      expect(g.combo, 1, reason: '只擋一次');
    });

    test('保溫便當袋：翻錯時連擊只少 1 段；Lv.2 每輪第一次翻錯不扣', () {
      final g = EndlessGame(random: Random(17), comboKeepOnMiss: true, firstMissForgiven: true);
      while (g.pairsLeft < 3) {
        clearBoard(g);
        g.nextWave();
      }
      g.combo = 4;
      miss(g);
      expect(g.combo, 4, reason: '第一次翻錯不扣');
      miss(g);
      expect(g.combo, 3, reason: '之後只少 1 段');
      expect(g.mistakes, 2, reason: '翻錯次數照算');
    });
  });

  group('EndlessGame 結束、喝酸梅湯與道具', () {
    test('喝酸梅湯：每輪一次，收掉 5 組（10 張），上菜進度歸零，繼續吃', () {
      final g = ready(18);
      missUntilFull(g);
      expect(g.canRevive, isTrue);
      g.serveProgress = 0.7;
      expect(g.revive(), isTrue);
      expect(g.isEnded, isFalse);
      expect(g.cardCount, EndlessGame.capacity - EndlessGame.reviveRemovePairs * 2);
      expect(g.serveProgress, 0);
      expect(filled(g).every((i) => !g.isOpen[i]), isTrue, reason: '翻開的牌都蓋回去');
      expectPairsValid(g);
      missUntilFull(g);
      expect(g.canRevive, isFalse, reason: '每輪只能一次');
      expect(g.revive(), isFalse);
    });

    test('金幣：結束後才結算，每 200 分 1 枚，算盤和招財貓會加成', () {
      final g = EndlessGame(random: Random(19), coinMultiplier: 1.2);
      clearBoard(g);
      g.nextWave();
      g.score = 10000;
      expect(g.coinsEarned, 0, reason: '還沒結束');
      g.useItem(ItemType.luckyCat);
      missUntilFull(g);
      g.score = 10000;
      expect(g.coinsEarned, (10000 / 200 * 1.2 * 1.5).round());
    });

    test('沙漏不能在大胃王用（沒有時間限制）', () {
      final g = EndlessGame(random: Random(20));
      expect(g.canUseItem(ItemType.hourglass), isFalse);
      expect(g.useItem(ItemType.hourglass), isFalse);
    });

    test('放大鏡：翻開的那張就配它的另一半；用道具不會讓老闆上菜；吃到最後一組會吃光', () {
      final g = EndlessGame(random: Random(21));
      clearBoard(g);
      g.nextWave();
      final (a, b) = anyPair(g);
      g.pick(a);
      final progress = g.serveProgress;
      expect(g.useItem(ItemType.magnifier), isTrue);
      expect(g.slots[a], isNull);
      expect(g.slots[b], isNull);
      expect(g.serveProgress, progress, reason: '用道具不算翻牌');
      expect(g.lastServedPairs, 0);
      expect(g.canUseItem(ItemType.magnifier), isFalse, reason: '每局一次');
      matchAny(g);
      expect(g.boardCleared, isTrue);
    });

    test('翻牌記憶：全部翻開、不能翻牌、不能偷看，也不會用掉偷看', () {
      final g = EndlessGame(random: Random(22));
      g.startPreview();
      expect(g.isFaceUp(filled(g).first), isTrue);
      final empty = List.generate(EndlessGame.capacity, (i) => i).firstWhere((i) => g.slots[i] == null);
      expect(g.isFaceUp(empty), isFalse, reason: '空位沒有牌面');
      expect(g.pick(filled(g).first), PickResult.ignored);
      expect(g.canPeek, isFalse);
      g.endPreview();
      expect(g.hintUsed, isFalse);
      expect(g.canPeek, isTrue);
    });

    test('偷看每局一次，偷看中不能翻牌', () {
      final g = EndlessGame(random: Random(23));
      expect(g.startPeek(), isTrue);
      expect(g.pick(filled(g).first), PickResult.ignored);
      g.endPeek();
      expect(g.startPeek(), isFalse);
    });

    test('老闆提示：連錯 2 次給一組對子，配對會歸零，提示後要再配 3 組才會再給', () {
      final g = EndlessGame(random: Random(24));
      while (g.pairsLeft < 4) {
        clearBoard(g);
        g.nextWave();
      }
      miss(g);
      expect(g.takeBossHint(), isNull, reason: '才錯 1 次');
      matchAny(g);
      miss(g);
      expect(g.takeBossHint(), isNull, reason: '中間配對成功，連錯歸零');
      miss(g);
      final hint = g.takeBossHint();
      expect(hint, isNotNull);
      expect(g.slots[hint![0]], g.slots[hint[1]]);
      miss(g);
      miss(g);
      expect(g.takeBossHint(), isNull, reason: '冷卻中');
      for (var i = 0; i < EndlessGame.bossHintCooldownMatches; i++) {
        matchAny(g);
      }
      miss(g);
      miss(g);
      expect(g.takeBossHint(), isNotNull, reason: '配了 3 組，冷卻結束');
    });

    test('老闆的人情：冷卻變短，最少 1 組', () {
      final g = EndlessGame(random: Random(25), bossHintCooldown: 0);
      while (g.pairsLeft < 3) {
        clearBoard(g);
        g.nextWave();
      }
      miss(g);
      miss(g);
      expect(g.takeBossHint(), isNotNull);
      miss(g);
      miss(g);
      expect(g.takeBossHint(), isNull, reason: '冷卻最少 1 組，不會連續拿提示');
      matchAny(g);
      miss(g);
      miss(g);
      expect(g.takeBossHint(), isNotNull);
    });

    test('老闆提示不會打亂之後的上菜（不用共用的亂數）', () {
      final a = ready(26);
      final b = ready(26);
      for (final g in [a, b]) {
        miss(g);
        miss(g);
      }
      expect(a.takeBossHint(), isNotNull); // 只有 a 拿提示
      for (final g in [a, b]) {
        miss(g);
        miss(g);
      }
      expect(a.slots, b.slots);
    });
  });

  test('小吃池夠多：桌子塞滿時每一組都能是不同的小吃', () {
    expect(foods.length, greaterThanOrEqualTo(EndlessGame.capacity ~/ 2));
  });
}
