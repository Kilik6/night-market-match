import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/food_icon.dart';
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

/// 首頁：夜市大胃王、夜市走透透（進選擇夜市再開始闖關）、卡背商店、每日任務、成就、圖鑑、玩法說明、設定。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.ads, required this.sounds, this.random});

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;
  final Random? random;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProgressStore get _store => widget.store;

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
      );

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
                CoinBadge(coins: _store.coins),
              ],
            ),
            Expanded(child: _Hero(skin: skinById(_store.equippedSkin))),
            MenuButton(
              key: const ValueKey('endless'),
              primary: true,
              icon: Icons.local_fire_department_rounded,
              label: EndlessScreen.title,
              subtitle: _store.endlessBest > 0 ? '最高分 ${_store.endlessBest}' : '無盡挑戰，吃越多分越高',
              onPressed: () => _open(EndlessScreen(
                store: _store,
                ads: widget.ads,
                sounds: widget.sounds,
                random: widget.random,
              )),
            ),
            const SizedBox(height: 10),
            MenuButton(
              key: const ValueKey('start'),
              icon: Icons.directions_walk_rounded,
              label: '夜市走透透',
              subtitle: '第 ${_latestLevel + 1} 攤・${latest.name}',
              // 先到選擇夜市的列表，選好一攤才開始
              onPressed: () => _open(LevelSelectScreen(store: _store, sounds: widget.sounds, gameBuilder: _game)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _tile('shop', Icons.storefront_rounded, '夜市商店',
                    () => _open(ShopScreen(store: _store, sounds: widget.sounds))),
                const SizedBox(width: 10),
                _tile('daily', Icons.today_rounded, '每日任務',
                    () => _open(DailyScreen(store: _store, sounds: widget.sounds)),
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
                _tile('guide', Icons.menu_book_rounded, '小吃圖鑑',
                    () => _open(FoodGuideScreen(store: _store))),
                const SizedBox(width: 10),
                _tile('howto', Icons.lightbulb_rounded, '玩法說明', () => _open(const HowToPlayScreen())),
                const SizedBox(width: 10),
                _tile('settings', Icons.settings_rounded, '設定',
                    () => _open(SettingsScreen(store: _store, sounds: widget.sounds))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 首頁的小方塊按鈕；dot 表示有獎勵可以領。
  Widget _tile(String key, IconData icon, String label, VoidCallback onTap, {bool dot = false}) {
    return Expanded(
      child: Material(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 26, color: NightColors.glow),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, style: const TextStyle(color: NightColors.paper, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                if (dot)
                  Positioned(
                    top: -4,
                    right: 22,
                    child: Container(
                      key: ValueKey('${key}_dot'),
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: NightColors.lantern, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
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
        ),
      );
    });
  }
}
