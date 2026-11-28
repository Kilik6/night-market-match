import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/leaderboard_service.dart';
import '../services/reminder_service.dart';
import '../services/progress_store.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/food_icon.dart';
import '../widgets/game_widgets.dart';
import '../widgets/lanterns.dart';
import '../widgets/night_scaffold.dart';
import 'achievements_screen.dart';
import 'daily_screen.dart';
import 'endless_screen.dart';
import 'food_guide_screen.dart';
import 'game_screen.dart';
import 'how_to_play_screen.dart';
import 'level_select_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

/// 首頁：夜市大胃王（大按鈕）、每日挑戰和夜市走透透（並排半寬，走透透先進選擇夜市再開始闖關）、卡背商店、每日任務、成就、圖鑑、玩法說明、設定。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.ads,
    required this.sounds,
    this.random,
    this.previewSeconds = previewMemorizeSeconds,
    this.purchases,
    this.leaderboards = const NoLeaderboardService(),
    this.reminders,
  });

  /// 每日提醒（設定頁開關、第一次簽到後詢問）。
  final ReminderService? reminders;

  /// 排行榜（之後接 Game Center／Google Play 遊戲服務）。
  final LeaderboardService leaderboards;

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;
  final Random? random;

  /// 開局翻開全部牌的秒數，傳給兩種模式的遊戲畫面。
  final int previewSeconds;

  /// 商店付款。沒給就用開發測試用的假商店（只有 debug 版會成功）。
  final PurchaseService? purchases;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProgressStore get _store => widget.store;
  late final PurchaseService _purchases = widget.purchases ?? DevPurchaseService();

  /// 先把小吃圖片載入記憶體，第一次翻到牌時才不會閃一下。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final food in foods) {
      if (food.image != null) precacheImage(AssetImage(food.image!), context);
    }
  }

  /// 最新解鎖的那一攤。
  int get _latestLevel => _store.unlocked.clamp(1, levels.length) - 1;

  /// 打開下一頁，回來時重新整理（金幣、星數、卡背可能變了）。
  Future<void> _open(Widget page) async {
    widget.sounds.play(Sfx.flip);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() {});
  }

  GameScreen _game(int level) => GameScreen(
        levelIndex: level,
        store: _store,
        ads: widget.ads,
        sounds: widget.sounds,
        random: widget.random,
        previewSeconds: widget.previewSeconds,
        purchases: _purchases,
      );

  Future<void> _openEndless({bool daily = false}) => _open(EndlessScreen(
        store: _store,
        ads: widget.ads,
        sounds: widget.sounds,
        // 每日挑戰用當天的種子，不吃外面給的亂數
        random: daily ? null : widget.random,
        previewSeconds: widget.previewSeconds,
        purchases: _purchases,
        dailyChallenge: daily,
        leaderboards: widget.leaderboards,
      ));

  @override
  Widget build(BuildContext context) {
    final latest = levels[_latestLevel];
    return NightScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Lanterns(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '★ ${_store.totalStars} / ${levels.length * 3}',
                  key: const ValueKey('total_stars'),
                  style: const TextStyle(color: Color(0xFFD9A21B), fontSize: 16, fontWeight: FontWeight.w700),
                ),
                // 金幣旁的「＋」直接打開商店的儲值分頁
                CoinBadge(
                  coins: _store.coins,
                  topUpLabel: _purchases.open ? '儲值金幣' : '看廣告領金幣',
                  onTopUp: () => _open(ShopScreen(
                    store: _store,
                    sounds: widget.sounds,
                    purchases: _purchases,
                    initialTab: ShopScreen.topUpTab,
                    ads: widget.ads,
                  )),
                ),
              ],
            ),
            Expanded(child: _Hero(skin: skinById(_store.equippedSkin))),
            MenuButton(
              key: const ValueKey('endless'),
              primary: true,
              icon: Icons.ramen_dining_rounded,
              label: EndlessScreen.title,
              subtitle: _store.endlessBest > 0 ? '最高分 ${_store.endlessBest}' : '無盡挑戰，吃越多分越高',
              onPressed: _openEndless,
            ),
            const SizedBox(height: 10),
            // 每日挑戰和走透透並排半寬，把空間留給上面的招牌卡片
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 一天只能玩一次：玩過就變暗，點了提示明天再來
                  _halfMode(
                    'daily_challenge',
                    Icons.event_rounded,
                    EndlessScreen.dailyTitle,
                    _store.dailyChallengePlayed ? '今天 ${_store.dailyChallengeBest} 分' : _store.dailyRule.title,
                    _store.dailyChallengePlayed ? _dailyDone : () => _openEndless(daily: true),
                    dot: !_store.dailyChallengePlayed,
                    dim: _store.dailyChallengePlayed,
                    badge: _store.dailyStreak > 0 ? '🔥${_store.dailyStreak}' : null,
                  ),
                  const SizedBox(width: 10),
                  _halfMode(
                    'start',
                    Icons.map_rounded,
                    '夜市走透透',
                    '第 ${_latestLevel + 1} 攤・${latest.name}',
                    // 先到選擇夜市的列表，選好一攤才開始
                    () => _open(LevelSelectScreen(store: _store, sounds: widget.sounds, gameBuilder: _game)),
                    green: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _tile(
                    'shop',
                    Icons.storefront_rounded,
                    '夜市商店',
                    () => _open(
                        ShopScreen(store: _store, sounds: widget.sounds, purchases: _purchases, ads: widget.ads))),
                const SizedBox(width: 10),
                _tile('daily', Icons.today_rounded, '每日任務',
                    () => _open(DailyScreen(
                        store: _store, sounds: widget.sounds, ads: widget.ads, reminders: widget.reminders)),
                    dot: _store.hasClaimableDaily),
                const SizedBox(width: 10),
                _tile('achievements', Icons.emoji_events_rounded, '成就',
                    () => _open(AchievementsScreen(store: _store, sounds: widget.sounds)),
                    dot: _store.hasClaimableAchievement),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _tile('guide', Icons.menu_book_rounded, '小吃圖鑑', () => _open(FoodGuideScreen(store: _store))),
                const SizedBox(width: 10),
                _tile('howto', Icons.lightbulb_rounded, '玩法說明', () => _open(const HowToPlayScreen())),
                const SizedBox(width: 10),
                _tile('settings', Icons.settings_rounded, '設定',
                    () => _open(SettingsScreen(
                          store: _store,
                          sounds: widget.sounds,
                          purchases: _purchases,
                          reminders: widget.reminders,
                          adPrivacy: widget.ads is AdPrivacy ? widget.ads as AdPrivacy : null,
                        ))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 半寬的模式按鈕：圖示、名稱和一行小字；dot 表示今天還沒玩。green 用綠色，其他是藍色。
  Widget _halfMode(String key, IconData icon, String label, String subtitle, VoidCallback onTap,
      {bool dot = false, bool dim = false, String? badge, bool green = false}) {
    return Expanded(
      child: Opacity(
        opacity: dim ? 0.55 : 1,
        child: ChunkyButton(
          key: ValueKey(key),
          face: green ? ChunkyColors.greenFace : ChunkyColors.blueFace,
          edge: green ? ChunkyColors.greenEdge : ChunkyColors.blueEdge,
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 4),
                          Text(badge,
                              key: ValueKey('${key}_badge'),
                              style: const TextStyle(
                                  color: ChunkyColors.tileIcon, fontSize: 12, fontWeight: FontWeight.w900)),
                        ],
                        if (dot) ...[
                          const SizedBox(width: 6),
                          _redDot('${key}_dot', 10),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 提醒用的紅點。
  Widget _redDot(String key, double size) => Container(
        key: ValueKey(key),
        width: size,
        height: size,
        decoration: const BoxDecoration(color: NightColors.lantern, shape: BoxShape.circle),
      );

  /// 今天的每日挑戰已經玩過了。
  void _dailyDone() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('今天的每日挑戰已經玩過了，明天換一盤再來！'),
        duration: Duration(seconds: 2),
      ));
  }

  /// 首頁的小方塊按鈕；dot 表示有獎勵可以領。
  Widget _tile(String key, IconData icon, String label, VoidCallback onTap, {bool dot = false}) {
    return Expanded(
      child: ChunkyButton(
        key: ValueKey(key),
        face: ChunkyColors.tileFace,
        edge: ChunkyColors.tileEdge,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: ChunkyColors.tileIcon),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            if (dot) Positioned(top: -4, right: 22, child: _redDot('${key}_dot', 11)),
          ],
        ),
      ),
    );
  }
}

/// 首頁中間的主視覺：發光的標題和三張扇形展開的卡片。
class _Hero extends StatelessWidget {
  const _Hero({required this.skin});
  final CardSkin skin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // 標題和副標題約佔 90 高，卡片區（含上方間距）約是卡高的 1.4 倍，剩下的高度才給卡片
      final cardW = max(0.0, min(c.maxWidth * 0.26, (c.maxHeight - 90) / (4 / 3 * 1.4)));
      final cardH = cardW * 4 / 3;
      Widget card(double angle, double dx, Widget child) => Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomCenter,
              child: SizedBox(width: cardW, height: cardH, child: child),
            ),
          );
      // 保險：字級被系統放大等情況還是放不下時，整塊等比縮小
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '夜市翻牌',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: NightColors.glow,
                fontSize: min(56, c.maxWidth * 0.14),
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                shadows: [Shadow(color: NightColors.glow.withValues(alpha: 0.6), blurRadius: 18)],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '逛遍台灣夜市，記住每一攤的小吃',
              style: TextStyle(color: NightColors.mist, fontSize: 14, letterSpacing: 1),
            ),
            // 小螢幕上卡片會被按鈕擠得太小，就只留標題，不畫一小團卡片
            if (cardW >= 48) ...[
              SizedBox(height: cardH * 0.25),
              SizedBox(
                height: cardH * 1.15,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    card(-0.28, -cardW * 0.62, CardBack(skin: skin, width: cardW)),
                    card(0.28, cardW * 0.62, CardBack(skin: skin, width: cardW)),
                    card(
                      0,
                      0,
                      Container(
                        decoration: BoxDecoration(
                          color: NightColors.paper,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
                        ),
                        // 小螢幕上卡片很小時，圖和字一起縮小
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FoodIcon(food: foods[1], size: cardW * 0.42),
                              Text(
                                '珍珠奶茶',
                                style: TextStyle(
                                  color: NightColors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: max(10, cardW * 0.14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}
