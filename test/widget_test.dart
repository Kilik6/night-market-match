import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_market_match/game/achievements.dart';
import 'package:night_market_match/game/card_skins.dart';
import 'package:night_market_match/game/endless_game.dart';
import 'package:night_market_match/game/items.dart';
import 'package:night_market_match/game/matching_game.dart';
import 'package:night_market_match/game/night_market_data.dart';
import 'package:night_market_match/screens/endless_screen.dart';
import 'package:night_market_match/screens/game_screen.dart';
import 'package:night_market_match/screens/home_screen.dart';
import 'package:night_market_match/screens/splash_screen.dart';
import 'package:night_market_match/services/ad_service.dart';
import 'package:night_market_match/services/progress_store.dart';
import 'package:night_market_match/services/sound_service.dart';
import 'package:night_market_match/widgets/card_widget.dart';
import 'package:night_market_match/widgets/game_widgets.dart';
import 'package:night_market_match/widgets/match_effects.dart';
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

  group('道具與裝備', () {
    MatchingGame newGame({int level = 0, int bonus = 0, int cap = 5, double multiplier = 1}) => MatchingGame(
          level: levels[level],
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

    test('道具：買、用、數量不夠不能用', () async {
      SharedPreferences.setMockInitialValues({'coins': 150});
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
      SharedPreferences.setMockInitialValues({'coins': 5000});
      final store = await ProgressStore.load();
      expect(store.upgradeCost(GearType.cart), 500);
      expect(await store.upgradeGear(GearType.cart), isTrue);
      expect(store.upgradeCost(GearType.cart), 1200);
      expect(await store.upgradeGear(GearType.cart), isTrue);
      expect(store.upgradeCost(GearType.cart), isNull);
      expect(await store.upgradeGear(GearType.cart), isFalse);
      expect(store.gearLevel(GearType.cart), 2);
      expect(store.coins, 3300);
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

      expect(await store.recordEndlessScore(2400, matches: 20), isTrue);
      expect(await store.recordEndlessScore(1800, matches: 55), isFalse, reason: '分數沒破紀錄');
      expect(store.endlessBest, 2400);
      expect(store.endlessBestMatches, 55, reason: '組數各自比較，沒破分數紀錄也會更新');
      await store.recordEndlessRound();
      await store.recordEndlessRound();
      expect(store.endlessRounds, 2);

      expect(store.isAchieved(byId('endless_first')), isTrue);
      expect(store.isAchieved(byId('endless_2000')), isTrue);
      expect(store.isAchieved(byId('endless_5000')), isFalse);
      expect(store.isAchieved(byId('endless_pairs50')), isTrue);
      expect(store.isAchieved(byId('endless_rounds20')), isFalse);

      await store.recordEndlessScore(10000);
      expect(await store.claimAchievement(byId('endless_10000')), isTrue);
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
      home: GameScreen(levelIndex: level, store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
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
      expect(find.text('總分 2620，獲得 🪙 288'), findsOneWidget);
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

    testWidgets('手機開了減少動態效果就不放特效', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true, size: Size(393, 852)),
          child: GameScreen(levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
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
      expect(find.text('🪙 123'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const ValueKey('start')));
      expect(find.text('選擇夜市'), findsOneWidget, reason: '先進選擇夜市，不會直接開始');
      expect(find.text('夜'), findsNothing);
      await tapAndSettle(tester, find.byKey(const ValueKey('level_1')));
      expect(find.text('城隍廟夜市'), findsOneWidget);
      expect(find.text('夜'), findsNWidgets(16));
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
      expect(find.text('每一局開始時，先提示 $previewHintSeconds 秒，接著所有卡牌翻開 $previewMemorizeSeconds 秒讓你記住位置，蓋回去後才開始計時。'),
          findsOneWidget);
      expect(find.textContaining('金幣是分數 ÷ 20'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('howto_more')), 300);
      for (final type in ItemType.values) {
        expect(find.text('${type.emoji} ${type.label}：${type.description}'), findsOneWidget, reason: type.name);
      }
      expect(find.textContaining('每升一級，每局時間 +2 秒'), findsOneWidget);
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
      expect(time, greaterThanOrEqualTo(58));

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
      await solveOnScreen(tester, 0);
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_leave')));
      expect(find.text('選擇夜市'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('level_stars_0'))).data, '★★★');

      await tapAndSettle(tester, find.byKey(const ValueKey('level_1')));
      expect(find.text('城隍廟夜市'), findsOneWidget);
    });

    testWidgets('商店：卡背金幣不夠會提示，買了就換上，成就卡背不能買', (tester) async {
      await pumpHome(tester, saved: {'coins': 400});
      await tapAndSettle(tester, find.byKey(const ValueKey('shop')));
      expect(find.text('夜市商店'), findsOneWidget);
      await tapAndSettle(tester, find.text('卡背'));

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
      expect(find.text('🪙 100'), findsOneWidget);
      expect(find.text('福'), findsNWidgets(2)); // 首頁扇形卡片的兩張卡背
    });

    testWidgets('商店：買道具、升級裝備', (tester) async {
      await pumpHome(tester, saved: {'coins': 500});
      await tapAndSettle(tester, find.byKey(const ValueKey('shop')));

      await tester.tap(find.byKey(const ValueKey('buy_hourglass')));
      await tester.pump();
      expect(store.itemCount(ItemType.hourglass), 1);
      expect(store.coins, 400);
      expect(find.text('沙漏（持有 1）'), findsOneWidget);

      await tapAndSettle(tester, find.text('裝備'));
      await tester.tap(find.byKey(const ValueKey('upgrade_hat')));
      await tester.pump();
      expect(store.gearLevel(GearType.hat), 1);
      expect(store.coins, 100);

      await tester.tap(find.byKey(const ValueKey('upgrade_hat'))); // 600，不夠
      await tester.pump();
      expect(find.text('金幣不夠，還差 🪙 500'), findsOneWidget);
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
      expect(find.text('🪙 0'), findsOneWidget);
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
    /// 直接打開夜市大胃王。
    Future<void> pumpEndless(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
      await setUpStore(tester, saved);
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
      ));
    }

    /// 用同樣的種子在旁邊跑一份，得知牌的位置。畫面補牌和這份補牌的順序一樣，結果就會一樣。
    EndlessGame mirrorEndless() => EndlessGame(random: Random(1));

    /// 在畫面上配對一組，等補牌完成，旁邊那份也跟著做。
    Future<void> eatPair(WidgetTester tester, EndlessGame g) async {
      late int a, b;
      outer:
      for (a = 0; a < g.cards.length; a++) {
        for (b = a + 1; b < g.cards.length; b++) {
          if (g.cards[a] == g.cards[b]) break outer;
        }
      }
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      g.pick(a);
      g.pick(b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950)); // 等相撞動畫播完、補牌
      await tester.pump(const Duration(milliseconds: 400)); // 等發牌動畫
      g.refill();
    }

    String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    /// 等時間用完、結算視窗跳出來。
    Future<void> runOutOfTime(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 75));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('首頁可以進入夜市大胃王，16 張牌', (tester) async {
      await pumpHome(tester);
      expect(find.text('無盡挑戰，吃越多分越高'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const ValueKey('endless')));
      expect(find.text('夜市大胃王'), findsOneWidget);
      expect(find.byKey(const ValueKey('card_15')), findsOneWidget);
      expect(find.byKey(const ValueKey('card_16')), findsNothing);
      expect(textOf(tester, 'time'), '60');
    });

    testWidgets('配對成功加分、加時間，補上新牌後可以一直配下去', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      await tester.pump(const Duration(seconds: 5));
      expect(textOf(tester, 'time'), '55');

      await eatPair(tester, g);
      expect(textOf(tester, 'score'), '100');
      expect(textOf(tester, 'time'), '57', reason: '55 秒 +3 秒，配對和補牌過了 1 秒');
      expect(find.textContaining('+3 秒'), findsOneWidget);

      // 補牌後畫面和旁邊那份一致：照著配下去，分數要完全一樣
      for (var i = 0; i < 12; i++) {
        await eatPair(tester, g);
      }
      expect(textOf(tester, 'score'), '${g.score}');
      expect(g.matches, 13);
      expect(find.byKey(const ValueKey('endless_progress')), findsOneWidget);
      expect(find.text('已吃 13 組・最高分 ${g.score}'), findsOneWidget);
      expect(store.discoveredFoods, isNotEmpty, reason: '大胃王配到的小吃也會收錄圖鑑');
    });

    testWidgets('配對成功：兩張牌浮起來往中間飛、相撞後才放特效，消失後補新牌', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      late int a, b;
      outer:
      for (a = 0; a < 16; a++) {
        for (b = a + 1; b < 16; b++) {
          if (g.cards[a] == g.cards[b]) break outer;
        }
      }
      final startA = tester.getCenter(find.byKey(ValueKey('card_$a')));
      final startB = tester.getCenter(find.byKey(ValueKey('card_$b')));
      final mid = (startA + startB) / 2;
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      await tester.pump();

      final fly = find.byKey(const ValueKey('merge_fly'));
      final flying = find.descendant(of: fly, matching: find.byType(CardWidget));
      double gap() => (tester.getCenter(flying.at(0)) - tester.getCenter(flying.at(1))).distance;
      Opacity slot(int i) => tester.widget<Opacity>(find.byKey(ValueKey('slot_visible_$i')));

      expect(fly, findsOneWidget);
      expect(flying, findsNWidgets(2));
      expect(slot(a).opacity, 0, reason: '原本的格子先空著，不會同時畫兩張');
      expect(slot(b).opacity, 0);
      final startGap = gap();

      // 浮起來：還沒往中間飛，但往上移
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getCenter(flying.at(0)).dy, lessThan(startA.dy));
      expect(find.text('+100'), findsNothing, reason: '還沒撞上，不放特效');

      // 飛到快撞上：兩張距離大幅縮短
      await tester.pump(const Duration(milliseconds: 330));
      expect(gap(), lessThan(startGap * 0.5));
      expect(find.text('+100'), findsNothing);

      // 撞上：重疊在中點，從中間飄分數
      await tester.pump(const Duration(milliseconds: 100));
      expect(gap(), lessThan(1), reason: '兩張重疊');
      expect((tester.getCenter(flying.at(0)) - mid).distance, lessThan(14), reason: '在兩張牌的中點（含浮起的高度）');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+100'), findsOneWidget);

      // 消失、補新牌
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(fly, findsNothing);
      expect(slot(a).opacity, 1);
      expect(tester.widget<CardWidget>(find.byKey(ValueKey('card_$a'))).isMatched, isFalse, reason: '已補上新牌');
      await tester.pump(const Duration(milliseconds: 1200));
    });

    testWidgets('減少動態效果時不飛不撞，牌發光一下就補新牌', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1), previewSeconds: 0),
        ),
      ));
      final g = mirrorEndless();
      late int a, b;
      outer:
      for (a = 0; a < 16; a++) {
        for (b = a + 1; b < 16; b++) {
          if (g.cards[a] == g.cards[b]) break outer;
        }
      }
      await tester.tap(find.byKey(ValueKey('card_$a')));
      await tester.tap(find.byKey(ValueKey('card_$b')));
      await tester.pump();
      expect(find.byKey(const ValueKey('merge_fly')), findsNothing);
      expect(tester.widget<CardWidget>(find.byKey(ValueKey('card_$a'))).isMatched, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.widget<CardWidget>(find.byKey(ValueKey('card_$a'))).isMatched, isFalse);
    });

    testWidgets('補上的新牌是蓋著的', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      await eatPair(tester, g);
      for (final i in g.lastRefilled) {
        final card = tester.widget<CardWidget>(find.byKey(ValueKey('card_$i')));
        expect(card.isShow, isFalse);
        expect(card.isMatched, isFalse);
        expect(card.food, g.cards[i]);
      }
    });

    testWidgets('時間到：破紀錄、存最高分，按再吃一輪才發金幣', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      for (var i = 0; i < 3; i++) {
        await eatPair(tester, g);
      }
      expect(g.score, 600);
      await runOutOfTime(tester);
      expect(find.text('新紀錄！吃飽收攤'), findsOneWidget);
      expect(find.text('總分 600'), findsOneWidget);
      expect(find.text('刷新最高分！（原本 0）'), findsOneWidget);
      expect(find.text('獲得 🪙 30'), findsOneWidget, reason: '600 分 ÷ 20');
      expect(store.endlessBest, 600, reason: '時間到就先存最高分');
      expect(store.coins, 0, reason: '還沒決定要不要續命，先不發金幣');

      await tapAndSettle(tester, find.text('再吃一輪'));
      expect(store.coins, 30);
      expect(textOf(tester, 'score'), '0');
      expect(textOf(tester, 'time'), '60');
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

      // 續命後時間到：不能再續命
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('dialog_ad')), findsNothing);
      await tapAndSettle(tester, find.byKey(const ValueKey('dialog_leave')));
      expect(store.coins, 5, reason: '100 分 ÷ 20，只發一次');
      expect(find.text('最高分 100'), findsOneWidget, reason: '首頁入口顯示最高分');
    });

    testWidgets('結算視窗顯示新達成的成就；續命和廣告失敗都只算一輪', (tester) async {
      await pumpEndless(tester);
      final g = mirrorEndless();
      for (var i = 0; i < 5; i++) {
        await eatPair(tester, g);
      }
      expect(g.score, 1500);
      await runOutOfTime(tester);
      expect(find.text('🏆 成就達成：開吃！'), findsOneWidget);
      expect(store.endlessRounds, 1);
      expect(store.endlessBestMatches, 5);

      ads.rewardSucceeds = false;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.endlessRounds, 1, reason: '廣告失敗重開結算視窗不能多算一輪');

      ads.rewardSucceeds = true;
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 2; i++) {
        await eatPair(tester, g);
      }
      expect(g.score, 2500, reason: '續命後連擊延續：1500 + 500 + 500（連擊上限 5）');
      await tester.pump(const Duration(seconds: 20));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.endlessRounds, 1, reason: '續命後再結算還是同一輪');
      expect(store.endlessBest, 2500);
      expect(find.text('🏆 成就達成：開吃！'), findsOneWidget);
      expect(find.text('🏆 成就達成：吃飽飽'), findsOneWidget, reason: '續命後才達到 2000 分');

      await tapAndSettle(tester, find.text('再吃一輪'));
      await runOutOfTime(tester);
      expect(store.endlessRounds, 2);
      expect(find.textContaining('🏆 成就達成'), findsNothing, reason: '已經達成過的不再顯示');
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

    testWidgets('小螢幕不會跑版（含補牌中）', (tester) async {
      for (final size in const [Size(640, 1136), Size(750, 1334)]) {
        await pumpEndless(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
        await eatPair(tester, mirrorEndless());
        expect(tester.takeException(), isNull, reason: '$size 補牌後');
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
    final banner = find.byKey(const ValueKey('preview_countdown'));

    Future<void> pumpLevel(WidgetTester tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(levelIndex: 0, store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
    }

    testWidgets('走透透：先在牌桌中央提示 $previewHintSeconds 秒，再翻開倒數 $previewMemorizeSeconds 秒，最後才開始計時', (tester) async {
      await pumpLevel(tester);
      await tester.pump(const Duration(milliseconds: 500));
      // 第一段：提示框，牌還蓋著
      expect(hint, findsOneWidget);
      expect(find.text('記住所有卡牌！'), findsOneWidget);
      expect(find.text('卡牌即將翻開 $previewMemorizeSeconds 秒'), findsOneWidget);
      expect(anyFaceUp(tester, 12), isFalse);
      expect(banner, findsNothing);
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('peek'))).onTap, isNull, reason: '準備中不能偷看');
      await tester.tap(find.byKey(const ValueKey('card_0')), warnIfMissed: false);
      await tester.pump(const Duration(seconds: previewHintSeconds - 1));
      expect(hint, findsOneWidget, reason: '提示框顯示滿 $previewHintSeconds 秒');
      expect(anyFaceUp(tester, 12), isFalse, reason: '準備中點牌沒有反應');
      expect(timeText(tester), '60');

      // 第二段：提示框消失、全部翻開、上方倒數
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(allFaceUp(tester, 12), isTrue);
      // 倒數 5、4、3、2、1，每秒跳一次
      for (var n = previewMemorizeSeconds; n >= 1; n--) {
        expect(countdown(tester), '$n');
        expect(allFaceUp(tester, 12), isTrue);
        if (n > 1) await tester.pump(const Duration(seconds: 1));
      }
      expect(timeText(tester), '60', reason: '記憶期間不扣時間');

      // 結束：蓋牌、開始計時，再過 1 秒才扣第一秒
      await tester.pump(const Duration(milliseconds: 600));
      expect(anyFaceUp(tester, 12), isFalse);
      expect(banner, findsNothing);
      expect(find.text('翻兩張一樣的小吃就能配對'), findsOneWidget);
      expect(timeText(tester), '60');
      await tester.pump(const Duration(seconds: 1));
      expect(timeText(tester), '59');
      expect(tester.widget<ItemTile>(find.byKey(const ValueKey('peek'))).onTap, isNotNull, reason: '偷看還能用');
    });

    testWidgets('提示框在牌桌正中央；倒數橫幅在牌桌上方，牌不會移位', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      final topLeft = tester.getRect(find.byKey(const ValueKey('card_0')));
      final bottomRight = tester.getRect(find.byKey(const ValueKey('card_15')));
      final boardCenter = Rect.fromPoints(topLeft.topLeft, bottomRight.bottomRight).center;
      final hintCenter = tester.getRect(hint).center;
      expect((hintCenter - boardCenter).distance, lessThan(2), reason: '提示框置中在牌桌上');
      final box = tester.widget<Container>(hint).decoration! as BoxDecoration;
      expect(box.color!.a, lessThan(1), reason: '提示框是半透明的');

      await tester.pump(const Duration(seconds: previewHintSeconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(banner).bottom, lessThan(topLeft.top), reason: '倒數在牌桌上方，不擋牌');
      expect(tester.getRect(find.byKey(const ValueKey('card_0'))), topLeft);
      await tester.pump(const Duration(seconds: previewMemorizeSeconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(find.byKey(const ValueKey('card_0'))), topLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('準備中按返回，提示和倒數都會停住', (tester) async {
      await pumpLevel(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tapAndSettle(tester, find.byKey(const ValueKey('back')));
      await tester.pump(const Duration(seconds: previewHintSeconds + previewMemorizeSeconds + 1));
      await tapAndSettle(tester, find.text('繼續玩'));
      // 沒暫停的話早就整段結束了
      expect(find.byKey(const ValueKey('preview_hint')).evaluate().isNotEmpty || banner.evaluate().isNotEmpty, isTrue,
          reason: '確認視窗開著時不倒數');
      await tester.pump(const Duration(seconds: previewHintSeconds + previewMemorizeSeconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hint, findsNothing);
      expect(banner, findsNothing);
      expect(anyFaceUp(tester, 12), isFalse);
    });

    testWidgets('大胃王：開局也有提示和倒數；再吃一輪會重來，續命不會', (tester) async {
      await setUpStore(tester, const {});
      await tester.pumpWidget(MaterialApp(
        home: EndlessScreen(store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(hint, findsOneWidget);
      expect(anyFaceUp(tester, 16), isFalse);
      await tester.pump(const Duration(seconds: previewHintSeconds));
      expect(allFaceUp(tester, 16), isTrue);
      expect(countdown(tester), '$previewMemorizeSeconds');
      await tester.pump(const Duration(seconds: previewMemorizeSeconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(anyFaceUp(tester, 16), isFalse);
      expect(timeText(tester), '60');

      // 時間到，看廣告續命：不會再提示
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('dialog_ad')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(timeText(tester), '15');
      expect(hint, findsNothing);
      expect(banner, findsNothing);
      expect(anyFaceUp(tester, 16), isFalse);

      // 再吃一輪：重新提示
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('再吃一輪'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(hint, findsOneWidget);
      expect(anyFaceUp(tester, 16), isFalse);
      await tester.pump(const Duration(seconds: previewHintSeconds + previewMemorizeSeconds + 1));
    });

    testWidgets('提示框在小螢幕上不會跑版', (tester) async {
      await setUpStore(tester, const {});
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(levelIndex: 17, store: store, ads: ads, sounds: sounds, random: Random(1)),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(hint, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: previewHintSeconds));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: previewMemorizeSeconds + 1));
    });
  });
}
