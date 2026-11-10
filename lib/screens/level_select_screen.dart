import 'package:flutter/material.dart';

import '../game/night_market_data.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/night_scaffold.dart';

/// 選擇夜市：列出所有夜市，顯示牌數、時間、最佳星數，未解鎖的上鎖。
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key, required this.store, required this.sounds, required this.gameBuilder});

  final ProgressStore store;
  final SoundService sounds;

  /// 建立某一攤的遊戲畫面（由首頁提供，避免這裡依賴廣告等服務）。
  final Widget Function(int level) gameBuilder;

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _play(int i) async {
    widget.sounds.play(Sfx.flip);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => widget.gameBuilder(i)));
    if (mounted) setState(() {}); // 回來時更新星數和解鎖狀態
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return NightScaffold(
      title: '選擇夜市',
      actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: CoinBadge(coins: store.coins)))],
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: levels.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final level = levels[i];
          final locked = i >= store.unlocked;
          final stars = store.bestStars(i);
          return Material(
            color: NightColors.stall,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('level_$i'),
              borderRadius: BorderRadius.circular(12),
              onTap: locked ? () => _toast('先通過「${levels[i - 1].name}」才能解鎖') : () => _play(i),
              child: Opacity(
                opacity: locked ? 0.45 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      // 攤位編號，像夜市的攤位牌
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: locked ? NightColors.mist.withValues(alpha: 0.2) : NightColors.lantern,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: locked
                            ? const Icon(Icons.lock_rounded, color: NightColors.paper, size: 20)
                            : Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: NightColors.paper,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${level.name}・${level.city}',
                              style: const TextStyle(
                                color: NightColors.paper,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${level.pairs * 2} 張牌・${level.seconds} 秒',
                              style: const TextStyle(color: NightColors.mist, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${'★' * stars}${'☆' * (3 - stars)}',
                        key: ValueKey('level_stars_$i'),
                        style: TextStyle(
                          color: stars > 0 ? const Color(0xFFD9A21B) : NightColors.mist.withValues(alpha: 0.5),
                          fontSize: 18,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
