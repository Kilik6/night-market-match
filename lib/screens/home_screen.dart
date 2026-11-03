import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/lanterns.dart';
import '../widgets/night_scaffold.dart';
import 'game_screen.dart';
import 'level_select_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

/// 首頁：開始遊戲、選擇夜市、卡背商店、設定。
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

  /// 最新解鎖的那一攤。
  int get _latestLevel => _store.unlocked.clamp(1, levels.length) - 1;

  int get _totalStars => [for (var i = 0; i < levels.length; i++) _store.bestStars(i)].reduce((a, b) => a + b);

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
                  '★ $_totalStars / ${levels.length * 3}',
                  key: const ValueKey('total_stars'),
                  style: const TextStyle(color: Color(0xFFD9A21B), fontSize: 16, fontWeight: FontWeight.w700),
                ),
                CoinBadge(coins: _store.coins),
              ],
            ),
            Expanded(child: _Hero(skin: skinById(_store.equippedSkin))),
            MenuButton(
              key: const ValueKey('start'),
              primary: true,
              icon: Icons.play_arrow_rounded,
              label: '開始遊戲',
              subtitle: '第 ${_latestLevel + 1} 攤・${latest.name}',
              onPressed: () => _open(_game(_latestLevel)),
            ),
            const SizedBox(height: 12),
            MenuButton(
              key: const ValueKey('levels'),
              icon: Icons.map_rounded,
              label: '選擇夜市',
              subtitle: '已解鎖 ${_latestLevel + 1} / ${levels.length} 攤',
              onPressed: () => _open(LevelSelectScreen(store: _store, sounds: widget.sounds, gameBuilder: _game)),
            ),
            const SizedBox(height: 12),
            MenuButton(
              key: const ValueKey('shop'),
              icon: Icons.storefront_rounded,
              label: '卡背商店',
              subtitle: '目前使用：${skinById(_store.equippedSkin).name}',
              onPressed: () => _open(ShopScreen(store: _store, sounds: widget.sounds)),
            ),
            const SizedBox(height: 12),
            MenuButton(
              key: const ValueKey('settings'),
              icon: Icons.settings_rounded,
              label: '設定',
              onPressed: () => _open(SettingsScreen(store: _store, sounds: widget.sounds)),
            ),
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
      final cardW = min(c.maxWidth * 0.26, c.maxHeight * 0.36);
      final cardH = cardW * 4 / 3;
      Widget card(double angle, double dx, Widget child) => Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomCenter,
              child: SizedBox(width: cardW, height: cardH, child: child),
            ),
          );
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🧋', style: TextStyle(fontSize: cardW * 0.42)),
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
              ],
            ),
          ),
        ],
      );
    });
  }
}
