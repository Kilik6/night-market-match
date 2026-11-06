import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/card_skins.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/night_scaffold.dart';

/// 成就：顯示進度，達成後領獎。
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, required this.store, required this.sounds});

  final ProgressStore store;
  final SoundService sounds;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  ProgressStore get _store => widget.store;

  Future<void> _claim(Achievement a) async {
    if (!await _store.claimAchievement(a) || !mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() {});
    final reward = a.skinId != null ? '卡背「${skinById(a.skinId!).name}」' : '🪙 ${a.coins}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('獲得 $reward'), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final done = achievements.where(_store.isClaimed).length;
    return NightScaffold(
      title: '成就 $done / ${achievements.length}',
      actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: CoinBadge(coins: _store.coins)))],
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: achievements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final a = achievements[i];
          final achieved = _store.isAchieved(a);
          final claimed = _store.isClaimed(a);
          final progress = _store.metricValue(a.metric).clamp(0, a.target);
          final reward = a.skinId != null ? '卡背「${skinById(a.skinId!).name}」' : '🪙 ${a.coins}';
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(
                  claimed ? Icons.emoji_events_rounded : Icons.emoji_events_outlined,
                  size: 30,
                  color: achieved ? const Color(0xFFD9A21B) : NightColors.mist.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: const TextStyle(color: NightColors.paper, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(a.description, style: const TextStyle(color: NightColors.mist, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        '$progress / ${a.target}・獎勵：$reward',
                        style: const TextStyle(color: NightColors.mist, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (claimed)
                  const Text('已領取', style: TextStyle(color: NightColors.jade, fontWeight: FontWeight.w700))
                else if (achieved)
                  FilledButton(
                    key: ValueKey('claim_${a.id}'),
                    onPressed: () => _claim(a),
                    style: FilledButton.styleFrom(backgroundColor: NightColors.glow, foregroundColor: NightColors.ink),
                    child: const Text('領取', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
