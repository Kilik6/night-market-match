import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/achievements.dart';
import 'package:night_market_match/game/card_skins.dart';
import 'package:night_market_match/game/endless_game.dart';
import 'package:night_market_match/game/gear_advice.dart';
import 'package:night_market_match/game/items.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/game/night_market_data.dart';
import 'package:night_market_match/screens/endless_screen.dart';
import 'package:night_market_match/screens/game_screen.dart';
import 'package:night_market_match/screens/home_screen.dart';
import 'package:night_market_match/screens/settings_screen.dart';
import 'package:night_market_match/screens/shop_screen.dart';
import 'package:night_market_match/screens/splash_screen.dart';
import 'package:night_market_match/services/ad_service.dart';
import 'package:night_market_match/services/progress_store.dart';
import 'package:night_market_match/screens/daily_screen.dart';
import 'package:night_market_match/services/purchase_service.dart';
import 'package:night_market_match/services/sound_service.dart';
import 'package:night_market_match/theme.dart';
import 'package:night_market_match/widgets/card_widget.dart';
import 'package:night_market_match/widgets/coin.dart';
import 'package:night_market_match/widgets/game_widgets.dart';
import 'package:night_market_match/widgets/match_effects.dart';
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

/// 每次都回傳「玩家取消」的假商店。
class _CancelPurchases implements PurchaseService {
  @override
  Future<PurchaseResult> buy(String productId) async => PurchaseResult.cancelled;

  @override
  Future<Set<String>?> restore() async => {};
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
      int other(int a) => List.generate(g.cards.length, (j) => j)
          .firstWhere((j) => !g.isMatched[j] && g.cards[j] != g.cards[a]);

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
      expect([for (final l in levels) l.pairs * 2],
          [2, 4, 4, 6, 6, 6, 8, 8, 8, 10, 10, 12, 12, 16, 16, 20, 20, 20]);
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
      expect({for (final id in ['goldfish', 'balloon', 'ringtoss', 'lantern_fest']) id: skinById(id).price},
          {'goldfish': 3000, 'balloon': 5000, 'ringtoss': 7000, 'lantern_fest': 12000});
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
      expect(cardSkins.length, 14);
    });

    test('商店排列：道具、裝備、卡背都依價格由便宜到貴，成就卡背排最後', () {
      expect(ShopScreen.sortedItems.map((t) => t.price), [200, 250, 300, 600]);
      expect(ShopScreen.sortedGear.map((t) => t.name),
          ['hat', 'abacus', 'backpack', 'favor', 'glasses', 'cart', 'lunchBag']);
      final paid = ShopScreen.sortedSkins.where((s) => !s.achievementOnly).map((s) => s.price).toList();
      expect(paid, [...paid]..sort());
      expect(ShopScreen.sortedSkins.first.id, defaultSkinId);
      expect(ShopScreen.sortedSkins.skipWhile((s) => !s.achievementOnly).every((s) => s.achievementOnly), isTrue);
      expect(ShopScreen.sortedSkins.length, cardSkins.length);
    });

    test('裝備：7 件，大胃王限定的有標示', () {
      expect(GearType.values.map((g) => g.name),
          ['hat', 'abacus', 'cart', 'glasses', 'lunchBag', 'backpack', 'favor']);
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
      expect(store.isAchieved(byId('endless_20000')), isTrue);
      expect(store.isAchieved(byId('endless_50000')), isFalse);
      expect(store.isAchieved(byId('endless_pairs80')), isTrue);
      expect(store.isAchieved(byId('endless_rounds20')), isFalse);

      expect(await store.claimAchievement(byId('endless_100000')), isFalse, reason: '還不到 100000 分');
      await store.recordEndlessScore(100000);
      expect(await store.claimAchievement(byId('endless_100000')), isTrue);
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
      expect(tasks.length, 3);
      expect(tasks.map((t) => t.id).toSet().length, 3);
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
          levelIndex: level, store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0, levelList: testLevels),
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
          .widget<OutlinedButton>(find.descendant(of: find.byKey(const ValueKey('dialog_ad')), matching: find.byType(OutlinedButton)))
          .style!
          .side!
          .resolve({})!;
      expect(adSide.color, const Color(0xFFA2580A), reason: '廣告按鈕是原本的深黃色');
      final adFill = tester
          .widget<OutlinedButton>(find.descendant(of: find.byKey(const ValueKey('dialog_ad')), matching: find.byType(OutlinedButton)))
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
            home: Center(child: SizedBox(width: width, height: width * 4 / 3, child: CardBack(skin: skin, width: width))),
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
              key: ValueKey(i), levelIndex: i, store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
        ));
        expect(tester.takeException(), isNull, reason: levels[i].name);
        expect(tester.getRect(find.text(levels[i].name)).height, lessThan(40), reason: '${levels[i].name} 一行');
        expect(tester.getRect(find.text('第 ${i + 1} 攤・${levels[i].city}')).height, lessThan(24));
      }
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
      expect(tester.getRect(find.text('夜市大胃王')).height, lessThan(40));
      expect(tester.getRect(find.byKey(const ValueKey('endless_progress'))).height, lessThan(24));
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
              levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0, levelList: testLevels),
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
    testWidgets('首頁：夜市走透透先進選擇夜市再開始，並顯示總星數和金幣', (tester) async {
      await pumpHome(tester, saved: {'unlocked': 2, 'coins': 123, 'stars_0': 3});
      expect(find.text('夜市翻牌'), findsOneWidget);
      expect(find.text('第 2 攤・城隍廟夜市'), findsOneWidget);
      expect(find.text('★ 3 / 54'), findsOneWidget);
      expect(findCoinText('🪙 123'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('coins')), matching: find.byType(CoinIcon)), findsOneWidget,
          reason: '金幣數用畫出來的金幣圖示');
      final rich = tester.widget<RichText>(find.descendant(of: find.byKey(const ValueKey('coins')), matching: find.byType(RichText)));
      expect(rich.text.toPlainText(), isNot(contains('🪙')), reason: '不再顯示 🪙 表情符號');

      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      expect(find.text('選擇夜市'), findsOneWidget, reason: '先進選擇夜市，不會直接開始');
      expect(find.text('夜'), findsNothing);
      await tapAndSettle(tester, find.byKey(const ValueKey('level_1')));
      expect(find.text('城隍廟夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(levels[1].pairs * 2));
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
      expect(find.text('每一局開始時，所有卡牌會先翻開 $previewMemorizeSeconds 秒讓你記住位置，倒數結束蓋回去後才開始計時。'),
          findsOneWidget);
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

    /// 用同樣的種子在旁邊跑一份，得知牌的位置。畫面發牌和這份發牌的順序一樣，結果就會一樣。
    EndlessGame mirrorEndless() => EndlessGame(random: Random(1));

    (int, int) pairIn(EndlessGame g) {
      for (var a = 0; a < g.boardSize; a++) {
        if (g.isMatched[a]) continue;
        for (var b = a + 1; b < g.boardSize; b++) {
          if (!g.isMatched[b] && g.cards[a] == g.cards[b]) return (a, b);
        }
      }
      throw StateError('no pair');
    }

    /// 清桌動畫播多久（和畫面的設定一致）。
    const clearAnimation = Duration(milliseconds: 1600);

    /// 在畫面上配對一組，等相撞動畫播完；清桌的話再等清桌動畫、發下一桌，旁邊那份也跟著做。
    Future<void> eatPair(WidgetTester tester, EndlessGame g) async {
      final (a, b) = pairIn(g);
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      g.pick(a);
      g.pick(b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950)); // 等相撞動畫
      if (g.tableCleared) {
        await tester.pump(clearAnimation); // 等清桌動畫、發下一桌
        g.nextTable();
      }
      await tester.pump(const Duration(milliseconds: 400)); // 等發牌動畫
    }

    /// 一直清桌，直到第 [table] 桌。
    Future<void> clearUntil(WidgetTester tester, EndlessGame g, int table) async {
      while (g.table < table) {
        await eatPair(tester, g);
      }
    }

    String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    Opacity slot(WidgetTester tester, int i) => tester.widget<Opacity>(find.byKey(ValueKey('slot_visible_$i')));

    /// 等時間用完、結算視窗跳出來。
    Future<void> runOutOfTime(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 75));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('首頁可以進入夜市大胃王，第 1 桌 2×2', (tester) async {
      await pumpHome(tester);
      expect(find.text('無盡挑戰，吃越多分越高'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      expect(find.text('夜市大胃王'), findsOneWidget);
      expect(find.byKey(const ValueKey('card_3')), findsOneWidget);
      expect(find.byKey(const ValueKey('card_4')), findsNothing);
      expect(find.text('第 1 桌・最高分 0'), findsOneWidget);
      expect(textOf(tester, 'time'), '60');
    });

    testWidgets('配對成功加分、加時間，位置空著不補牌', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      await tester.pump(const Duration(seconds: 5));
      expect(textOf(tester, 'time'), '55');
      final (a, b) = pairIn(g);
      await eatPair(tester, g);
      expect(textOf(tester, 'score'), '100');
      expect(textOf(tester, 'time'), '57', reason: '55 秒 +3 秒，配對和動畫過了 1 秒');
      expect(slot(tester, a).opacity, 0, reason: '消掉的位置空著');
      expect(slot(tester, b).opacity, 0);
      expect(store.discoveredFoods, isNotEmpty, reason: '大胃王配到的小吃也會收錄圖鑑');
    });

    testWidgets('清桌：大動畫、+500 分、+5 秒、計時暫停，播完發第 2 桌', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      await tester.pump(const Duration(seconds: 20));
      await eatPair(tester, g); // 第一組
      final (a, b) = pairIn(g);
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      g.pick(a);
      g.pick(b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950));
      // 清桌動畫
      expect(find.byKey(const ValueKey('table_clear')), findsOneWidget);
      expect(find.text('清桌！'), findsOneWidget);
      expect(find.text('+500'), findsOneWidget);
      expect(find.text('清桌！第 1 桌 +500・+5 秒'), findsOneWidget);
      // 煙火一發一發在牌桌各處炸開
      await tester.pump(const Duration(milliseconds: 650));
      final bursts = find.byType(MatchBurst);
      expect(bursts.evaluate().length, greaterThanOrEqualTo(6), reason: '同時有很多發煙火');
      final centers = [for (final e in bursts.evaluate()) tester.getCenter(find.byWidget(e.widget))];
      final spreadX = centers.map((c) => c.dx).reduce(max) - centers.map((c) => c.dx).reduce(min);
      final spreadY = centers.map((c) => c.dy).reduce(max) - centers.map((c) => c.dy).reduce(min);
      expect(spreadX, greaterThan(100), reason: '左右散開');
      expect(spreadY, greaterThan(100), reason: '上下散開');
      expect(textOf(tester, 'score'), '${100 + 200 + 500}');
      final time = textOf(tester, 'time');
      await tester.pump(const Duration(milliseconds: 500));
      expect(textOf(tester, 'time'), time, reason: '清桌動畫期間不倒數');

      // 第 2 桌
      await tester.pump(const Duration(milliseconds: 550));
      g.nextTable();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('table_clear')), findsNothing);
      expect(find.byType(MatchBurst), findsNothing, reason: '煙火在下一桌開始前就放完');
      expect(find.text('第 2 桌・最高分 800'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(slot(tester, i).opacity, 1, reason: '新的一桌全部發好');
        final card = tester.widget<CardWidget>(find.byKey(ValueKey('card_$i')));
        expect(card.isShow, isFalse);
        expect(card.food, g.cards[i]);
      }
      expect(find.text('第 2 桌，開吃！'), findsOneWidget);
    });

    testWidgets('越後面牌越多：第 3 桌 3×2、第 6 桌 4×2、第 10 桌 4×4', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      Rect rect(int i) => tester.getRect(find.byKey(ValueKey('card_$i')));
      int columnsOnScreen() {
        final top = rect(0).top;
        var n = 0;
        while (find.byKey(ValueKey('card_$n')).evaluate().isNotEmpty && (rect(n).top - top).abs() < 1) {
          n++;
        }
        return n;
      }

      for (final (table, cards, columns) in [(3, 6, 3), (6, 8, 4), (10, 16, 4)]) {
        await clearUntil(tester, g, table);
        expect(find.byKey(ValueKey('card_${cards - 1}')), findsOneWidget, reason: '第 $table 桌');
        expect(find.byKey(ValueKey('card_$cards')), findsNothing);
        expect(columnsOnScreen(), columns, reason: '第 $table 桌欄數');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('配對成功：兩張牌浮起來往中間飛、相撞後才放特效，消失後位置空著', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      final (a, b) = pairIn(g);
      final startA = tester.getCenter(find.byKey(ValueKey('card_$a')));
      final startB = tester.getCenter(find.byKey(ValueKey('card_$b')));
      final mid = (startA + startB) / 2;
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      await tester.pump();

      final fly = find.byKey(const ValueKey('merge_fly'));
      final flying = find.descendant(of: fly, matching: find.byType(CardWidget));
      double gap() => (tester.getCenter(flying.at(0)) - tester.getCenter(flying.at(1))).distance;

      expect(fly, findsOneWidget);
      expect(flying, findsNWidgets(2));
      expect(slot(tester, a).opacity, 0, reason: '原本的格子空著，不會同時畫兩張');
      final startGap = gap();

      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getCenter(flying.at(0)).dy, lessThan(startA.dy), reason: '先浮起來');
      expect(find.text('+100'), findsNothing);

      await tester.pump(const Duration(milliseconds: 330));
      expect(gap(), lessThan(startGap * 0.5));
      expect(find.descendant(of: fly, matching: find.byType(Transform)).evaluate().every((e) {
        final m = (e.widget as Transform).transform;
        return m.entry(0, 1).abs() < 1e-9 && m.entry(1, 0).abs() < 1e-9;
      }), isTrue, reason: '飛行中沒有旋轉');

      await tester.pump(const Duration(milliseconds: 100));
      expect(gap(), lessThan(1), reason: '兩張重疊');
      expect((tester.getCenter(flying.at(0)) - mid).distance, lessThan(14));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+100'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(fly, findsNothing);
      expect(slot(tester, a).opacity, 0, reason: '不補牌，位置空著');
      await tester.pump(const Duration(milliseconds: 1200));
    });

    testWidgets('減少動態效果時不飛不撞，配對的牌直接消失，清桌照樣發下一桌', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
        ),
      ));
      final g = mirrorEndless();
      final (a, b) = pairIn(g);
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      g.pick(a);
      g.pick(b);
      await tester.pump();
      expect(find.byKey(const ValueKey('merge_fly')), findsNothing);
      expect(slot(tester, a).opacity, 0);
      final (c, d) = pairIn(g);
      await tester.tap(find.byKey(ValueKey('card_$c')));
      await tester.tap(find.byKey(ValueKey('card_$d')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('table_clear')), findsOneWidget);
      await tester.pump(clearAnimation);
      expect(find.text('第 2 桌・最高分 800'), findsOneWidget);
      expect(slot(tester, a).opacity, 1);
    });

    testWidgets('連錯兩次：老闆亮出一組對子，過一下再蓋回去', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      await clearUntil(tester, g, 3); // 3×2 的桌，有足夠的牌可以翻錯
      bool shown(int i) => tester.widget<CardWidget>(find.byKey(ValueKey('card_$i'))).isShow;
      (int, int) mismatch() {
        for (var a = 0; a < g.boardSize; a++) {
          for (var b = a + 1; b < g.boardSize; b++) {
            if (g.cards[a] != g.cards[b]) return (a, b);
          }
        }
        throw StateError('no mismatch');
      }

      for (var round = 0; round < 2; round++) {
        final (a, b) = mismatch();
        await tester.tap(find.byKey(ValueKey('card_$a')));
        await tester.tap(find.byKey(ValueKey('card_$b')));
        g.pick(a);
        g.pick(b);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        g.hideMismatched();
      }
      expect(find.text('老闆偷偷告訴你：這兩張是一對！'), findsOneWidget);
      final up = [for (var i = 0; i < g.boardSize; i++) if (shown(i)) i];
      expect(up.length, 2);
      expect(g.cards[up[0]], g.cards[up[1]], reason: '亮出來的是一對');
      await tester.pump(const Duration(milliseconds: 1300));
      expect([for (var i = 0; i < g.boardSize; i++) if (shown(i)) i], isEmpty, reason: '提示結束蓋回去');
    });

    testWidgets('時間到：破紀錄、存最高分，按再吃一輪才發金幣', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      for (var i = 0; i < 3; i++) {
        await eatPair(tester, g);
      }
      expect(g.score, 100 + 200 + 500 + 300, reason: '第 1 桌兩組加清桌，第 2 桌一組');
      await runOutOfTime(tester);
      expect(find.text('新紀錄！吃飽收攤'), findsOneWidget);
      expect(find.text('總分 1100'), findsOneWidget);
      expect(find.text('清了 1 桌、吃了 3 組，最高 3 連擊'), findsOneWidget);
      expect(find.text('刷新最高分！（原本 0）'), findsOneWidget);
      expect(findCoinText('獲得 🪙 6'), findsOneWidget, reason: '1100 分 ÷ 200，四捨五入');
      expect(store.endlessBest, 1100, reason: '時間到就先存最高分');
      expect(store.coins, 0, reason: '還沒決定要不要續命，先不發金幣');

      await tapAndSettle(tester, find.text('再吃一輪'));
      expect(store.coins, 6);
      expect(textOf(tester, 'score'), '0');
      expect(textOf(tester, 'time'), '60');
      expect(find.text('第 1 桌・最高分 1100'), findsOneWidget);
      expect(find.byKey(const ValueKey('card_4')), findsNothing, reason: '回到第 1 桌');
    });

    testWidgets('沒破紀錄時顯示原本的最高分', (tester) async {
      await pumpEndless(tester, saved: {'endless_best_score': 5000});
      await runOutOfTime(tester);
      expect(find.text('吃飽收攤'), findsOneWidget);
      expect(find.text('最高分 5000'), findsOneWidget);
      expect(store.endlessBest, 5000);
    });

    testWidgets('看廣告續命 +15 秒；廣告失敗回到結算；最後才發一次金幣', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      final g = mirrorEndless();
      await eatPair(tester, g);
      await runOutOfTime(tester);

      // 廣告維持原本的深黃字外框樣式，再吃一輪、回到首頁是黃色外框
      expect(find.ancestor(of: find.text('看廣告 +15 秒繼續吃'), matching: find.byType(FilledButton)), findsNothing);
      for (final label in ['再吃一輪', '回到首頁']) {
        expect(find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)), findsOneWidget, reason: label);
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
      expect(textOf(tester, 'time'), '15');
      expect(find.text('多 15 秒，繼續吃！'), findsOneWidget);
      expect(store.coins, 0);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('dialog_ad')), findsNothing);
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_leave')));
      expect(store.coins, 1, reason: '100 分 ÷ 200 四捨五入，只發一次');
      expect(find.text('最高分 100'), findsOneWidget, reason: '首頁入口顯示最高分');
    });

    testWidgets('結算視窗顯示新達成的成就；續命和廣告失敗都只算一輪', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      for (var i = 0; i < 3; i++) {
        await eatPair(tester, g);
      }
      expect(g.score, 1100);
      await runOutOfTime(tester);
      expect(find.text('🏆 成就達成：開吃！'), findsOneWidget);
      expect(find.text('🏆 成就達成：吃飽飽'), findsNothing, reason: '還不到 20000 分');
      expect(store.endlessRounds, 1);
      expect(store.endlessBestMatches, 3);

      ads.rewardSucceeds = false;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.endlessRounds, 1, reason: '廣告失敗重開結算視窗不能多算一輪');

      ads.rewardSucceeds = true;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 續命後一路清桌，直到超過 20000 分（配對和清桌加的時間比花掉的多，時間夠用）
      while (g.score < 20000) {
        await eatPair(tester, g);
      }
      await runOutOfTime(tester);
      expect(store.endlessRounds, 1, reason: '續命後再結算還是同一輪');
      expect(store.endlessBest, g.score);
      expect(find.text('🏆 成就達成：吃飽飽'), findsOneWidget, reason: '續命後才達到 20000 分');

      await tapAndSettle(tester, find.text('再吃一輪'));
      await runOutOfTime(tester);
      expect(store.endlessRounds, 2);
      expect(find.textContaining('🏆 成就達成'), findsNothing, reason: '已經達成過的不再顯示');
    });

    testWidgets('重新開始：確認後回到第 1 桌，分數和金幣都不保存', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      for (var i = 0; i < 3; i++) {
        await eatPair(tester, g);
      }
      expect(find.text('第 2 桌・最高分 1100'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('restart')));
      expect(find.text('重新開始這一輪？'), findsOneWidget);
      await tapAndSettle(tester, find.text('繼續吃'));
      expect(textOf(tester, 'score'), '1100', reason: '取消就繼續這一輪');

      await tapAndSettle(tester, find.byKey(const ValueKey('restart')));
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_restart')));
      expect(textOf(tester, 'score'), '0');
      expect(textOf(tester, 'time'), '60');
      expect(find.text('第 1 桌・最高分 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('card_4')), findsNothing, reason: '回到 2×2 的第 1 桌');
      expect(store.endlessBest, 0);
      expect(store.coins, 0);
    });

    testWidgets('中途離開要確認，分數和金幣都不保存', (tester) async {
      await pumpHome(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      await eatPair(tester, mirrorEndless());
      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      expect(find.text('不吃了嗎？'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('confirm_leave')));
      expect(find.byKey(const ValueKey('endless')), findsOneWidget);
      expect(store.endlessBest, 0);
      expect(store.coins, 0);
    });

    testWidgets('小螢幕不會跑版：2×2 的第 1 桌和 4×4 的第 10 桌', (tester) async {
      for (final size in const [Size(640, 1136), Size(750, 1334)]) {
        await pumpEndless(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size 第 1 桌');
        final g = mirrorEndless();
        await clearUntil(tester, g, 10);
        expect(tester.takeException(), isNull, reason: '$size 第 10 桌');
        for (var i = 0; i < 16; i++) {
          final rect = tester.getRect(find.byKey(ValueKey('card_$i')));
          expect(rect.bottom, lessThan(size.height / 2), reason: '$size 第 $i 張超出畫面');
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
    String countdown(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('preview_seconds'))).data!;
    final hint = find.byKey(const ValueKey('preview_hint'));
    const seconds = previewMemorizeSeconds;

    Future<void> pumpLevel(WidgetTester tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1), levelList: testLevels),
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

    testWidgets('提示框在牌桌正中央、半透明，牌不會移位', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      final topLeft = tester.getRect(find.byKey(const ValueKey('card_0')));
      final bottomRight = tester.getRect(find.byKey(const ValueKey('card_3')));
      final board = Rect.fromPoints(topLeft.topLeft, bottomRight.bottomRight);
      expect((tester.getRect(hint).center - board.center).distance, lessThan(2), reason: '提示框置中在牌桌上');
      expect(tester.getRect(hint).width, lessThan(board.width), reason: '框比牌桌小');
      final box = tester.widget<Container>(hint).decoration! as BoxDecoration;
      expect(box.color!.a, lessThan(0.7), reason: '半透明，看得到底下的牌');

      await tester.pump(const Duration(seconds: seconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('card_0'))), topLeft);
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

    testWidgets('大胃王：開局也翻牌倒數；再吃一輪會重來，續命不會', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(allFaceUp(tester, 4), isTrue);
      expect(countdown(tester), '$seconds');
      await tester.pump(const Duration(seconds: seconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(anyFaceUp(tester, 4), isFalse);
      expect(hint, findsNothing);
      expect(timeText(tester), '60');

      // 時間到，看廣告續命：不會再翻牌
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(timeText(tester), '15');
      expect(hint, findsNothing);
      expect(anyFaceUp(tester, 4), isFalse, reason: '續命是同一輪，不再翻牌');

      // 再吃一輪：重新翻牌倒數
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('再吃一輪'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsOneWidget);
      expect(allFaceUp(tester, 4), isTrue);
      await tester.pump(const Duration(seconds: seconds + 1));
    });

    testWidgets('大胃王：清桌後的新一桌翻開 3 秒，翻牌期間不扣時間', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(seconds: seconds));
      await tester.pump(const Duration(milliseconds: 400));
      final g = EndlessGame(random: Random(1));
      for (var n = 0; n < 2; n++) {
        late int a, b;
        outer:
        for (a = 0; a < 4; a++) {
          for (b = a + 1; b < 4; b++) {
            if (!g.isMatched[a] && !g.isMatched[b] && g.cards[a] == g.cards[b]) break outer;
          }
        }
        await tester.tap(find.byKey(ValueKey('card_$a')));
        await tester.tap(find.byKey(ValueKey('card_$b')));
        g.pick(a);
        g.pick(b);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 950)); // 相撞
      // 清桌動畫：每 0.1 秒畫一次，煙火才會在施放的時間點開始播（一次跳 1.6 秒會全部擠在最後才開始）
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsOneWidget, reason: '第 2 桌也翻牌');
      expect(find.byType(MatchBurst), findsNothing, reason: '「記住所有卡牌」的時候沒有煙火');
      expect(countdown(tester), '3');
      expect(allFaceUp(tester, 4), isTrue);
      final time = timeText(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(timeText(tester), time, reason: '翻牌期間不扣時間');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(anyFaceUp(tester, 4), isFalse);
      expect(find.text('第 2 桌，開吃！'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      // 計時器跨桌一直在跑，蓋牌後 1.4 秒內可能扣 1 或 2 秒，只確認有繼續倒數
      expect(int.parse(timeText(tester)), lessThan(int.parse(time)), reason: '蓋牌後繼續計時');
    });

    testWidgets('老花眼鏡：開局翻牌記憶的倒數變長', (tester) async {
      await setUpStore(tester, const {'gear_glasses': 2});
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1), levelList: testLevels),
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
          findsOneWidget, reason: '金幣數字在膠囊裡');
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
      expect(find.text('已恢復「永久移除廣告」'), findsOneWidget);

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

      expect(sequence(endless: true), [
        GearType.hat,
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
      final abacus = adviseGear(
          levelOf: (t) => t == GearType.abacus ? 1 : t.maxLevel, coins: 0, endless: true)!;
      expect(abacus.nextLevel, 2);
      expect(abacus.message, contains('金幣再 +10%'));
    });

    test('建議：翻錯很多次就建議老花眼鏡，眼鏡滿了再建議便當袋', () {
      final glasses = adviseGear(levelOf: (_) => 0, coins: 0, endless: false, mistakes: 4)!;
      expect(glasses.type, GearType.glasses);
      expect(glasses.message, startsWith('這一局翻錯了 4 次！'));
      expect(glasses.message, contains('開局翻牌記憶多 1 秒'));
      final bag = adviseGear(
          levelOf: (t) => t == GearType.glasses ? t.maxLevel : 0, coins: 0, endless: true, mistakes: 3)!;
      expect(bag.type, GearType.lunchBag);
      expect(bag.message, contains('翻錯時連擊只少 1 段'));
    });

    test('建議：大胃王的帽子寫每一輪；金幣夠的時候提示現在就升得起', () {
      final advice = adviseGear(levelOf: none, coins: GearType.hat.costs[0], endless: true)!;
      expect(advice.message, contains('每一輪時間 +2 秒，能多吃幾桌'));
      expect(advice.message, contains('現在就升得起'));
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
      expect(find.text('老闆的帽子  Lv.0 / 3'), findsOneWidget, reason: '直接打開裝備分頁');
      await tester.tap(find.byKey(const ValueKey('upgrade_hat')));
      await tester.pump();
      expect(store.gearLevel(GearType.hat), 1);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('時間到了'), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('time'))).data, '62', reason: '用新的帽子重新開始：60 + 2 秒');
    });

    testWidgets('大胃王時間到：強化裝備前先發這一輪的金幣，回來後再吃一輪', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
      final g = EndlessGame(random: Random(1));
      for (var n = 0; n < 2; n++) {
        late int a, b;
        outer:
        for (a = 0; a < g.boardSize; a++) {
          for (b = a + 1; b < g.boardSize; b++) {
            if (!g.isMatched[a] && !g.isMatched[b] && g.cards[a] == g.cards[b]) break outer;
          }
        }
        await tester.tap(find.byKey(ValueKey('card_$a')));
        await tester.tap(find.byKey(ValueKey('card_$b')));
        g.pick(a);
        g.pick(b);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 3)); // 清桌動畫、發下一桌
      await tester.pump(const Duration(seconds: 75));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('dialog_upgrade')), findsOneWidget);
      expect(store.coins, 0, reason: '還沒決定之前不發金幣');

      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_upgrade')));
      expect(store.coins, (800 / EndlessGame.scorePerCoin).round(), reason: '打開商店前先發這一輪的金幣');
      expect(find.text('老闆的帽子  Lv.0 / 3'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('score'))).data, '0', reason: '回來後是新的一輪');
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
