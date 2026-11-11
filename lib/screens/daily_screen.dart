import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/coin.dart';
import '../widgets/night_scaffold.dart';

/// 每日任務與連續簽到。
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key, required this.store, required this.sounds});

  final ProgressStore store;
  final SoundService sounds;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  ProgressStore get _store => widget.store;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: CoinText(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _checkIn() async {
    final coins = await _store.checkIn();
    if (coins == 0 || !mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() {});
    _toast('簽到成功，獲得 🪙 $coins');
  }

  Future<void> _claim(DailyTask task) async {
    if (!await _store.claimDaily(task) || !mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() {});
    _toast('獲得 🪙 ${task.coins}');
  }

  @override
  Widget build(BuildContext context) {
    final canCheckIn = _store.canCheckIn;
    final day = _store.nextCheckInDay; // 今天簽到後算第幾天
    return NightScaffold(
      title: '每日任務',
      actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: CoinBadge(coins: _store.coins)))],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('連續簽到', style: TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < checkInRewards.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: _dayCell(i + 1, canCheckIn, day)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('check_in'),
            onPressed: canCheckIn ? _checkIn : null,
            style: FilledButton.styleFrom(
              backgroundColor: NightColors.glow,
              foregroundColor: NightColors.ink,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: CoinText(
              canCheckIn ? '簽到領 🪙 ${checkInRewards[day - 1]}' : '今天已經簽到了',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          const SizedBox(height: 22),
          const Text('今日任務', style: TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          for (final task in _store.todayTasks) ...[
            _taskRow(task),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// 簽到日曆的一格：已簽到的天數打勾。
  Widget _dayCell(int d, bool canCheckIn, int day) {
    final done = canCheckIn ? d < day : d <= day;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: done ? NightColors.glow.withValues(alpha: 0.2) : NightColors.stall,
        borderRadius: BorderRadius.circular(8),
        border: canCheckIn && d == day ? Border.all(color: NightColors.glow, width: 1.5) : null,
      ),
      child: Column(
        children: [
          Text('$d', style: const TextStyle(color: NightColors.mist, fontSize: 11)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              done ? '✓' : '${checkInRewards[d - 1]}',
              style: const TextStyle(color: NightColors.glow, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(DailyTask task) {
    final progress = _store.dailyProgress(task.id).clamp(0, task.target);
    final done = _store.isDailyDone(task);
    final claimed = _store.isDailyClaimed(task);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.description, style: const TextStyle(color: NightColors.paper, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                CoinText(
                  '$progress / ${task.target}・獎勵 🪙 ${task.coins}',
                  style: const TextStyle(color: NightColors.mist, fontSize: 13),
                ),
              ],
            ),
          ),
          if (claimed)
            const Text('已領取', style: TextStyle(color: NightColors.jade, fontWeight: FontWeight.w700))
          else if (done)
            FilledButton(
              key: ValueKey('daily_${task.id}'),
              onPressed: () => _claim(task),
              style: FilledButton.styleFrom(backgroundColor: NightColors.glow, foregroundColor: NightColors.ink),
              child: const Text('領取', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
