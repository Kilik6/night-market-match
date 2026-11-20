import 'dart:math';

import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/items.dart';
import '../game/wheel.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/reminder_service.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/coin.dart';
import '../widgets/game_widgets.dart';
import '../widgets/night_scaffold.dart';
import '../widgets/prize_wheel.dart';

/// 每日任務、夜市轉盤與連續簽到。有 [ads] 時可以看廣告多轉轉盤、雙倍領簽到和任務獎勵。
class DailyScreen extends StatefulWidget {
  /// 今日任務的順序：可以領的在最上面、還沒完成的在中間、領過的放最下面。
  static List<DailyTask> orderedTasks(ProgressStore store) {
    int rank(DailyTask t) => store.isDailyClaimed(t) ? 2 : (store.isDailyDone(t) ? 0 : 1);
    final tasks = store.todayTasks;
    return [
      for (final r in [0, 1, 2]) ...tasks.where((t) => rank(t) == r),
    ];
  }

  const DailyScreen({super.key, required this.store, required this.sounds, this.ads, this.random, this.reminders});

  final ProgressStore store;
  final SoundService sounds;
  final AdService? ads;

  /// 轉盤抽獎用，測試時傳固定種子。
  final Random? random;

  /// 每日提醒：第一次簽到後問玩家要不要開。
  final ReminderService? reminders;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  ProgressStore get _store => widget.store;
  late final Random _random = widget.random ?? Random();
  final _wheelKey = GlobalKey<PrizeWheelState>();

  /// 轉盤正在轉、或正在播廣告：按鈕先關掉。
  bool _busy = false;

  /// 這一次轉盤是不是看廣告轉的。
  bool _spinByAd = false;

  /// 播獎勵廣告，播放期間暫停背景音樂。播不了時提示並回傳 false。
  Future<bool> _watchAd() async {
    final ads = widget.ads;
    if (ads == null) return false;
    setState(() => _busy = true);
    widget.sounds.pauseMusic();
    final earned = await ads.showRewarded();
    widget.sounds.resumeMusic();
    if (!mounted) return false;
    setState(() => _busy = false);
    if (!earned) _toast('廣告目前無法播放，請稍後再試');
    return earned;
  }

  Future<void> _spin({required bool byAd}) async {
    if (_busy) return;
    if (byAd && !await _watchAd()) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _spinByAd = byAd;
    });
    widget.sounds.play(Sfx.flip);
    _wheelKey.currentState?.spinTo(spinWheel(_random));
  }

  Future<void> _onWheelStopped(int index) async {
    await _store.claimWheel(index, byAd: _spinByAd);
    if (!mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() => _busy = false);
    final prize = wheelPrizes[index];
    _toast(prize.item != null ? '轉到 ${prize.item!.emoji} ${prize.item!.label} ×1！' : '轉到 🪙 ${prize.coins}！');
  }

  /// 夜市轉盤：每天免費一次，看廣告可以再轉幾次。
  Widget _wheelSection() {
    final free = _store.wheelFreeAvailable;
    final adLeft = _store.wheelAdSpinsLeft;
    final Widget button;
    if (free) {
      button = FilledButton(
        key: const ValueKey('wheel_free'),
        onPressed: _busy ? null : () => _spin(byAd: false),
        style: FilledButton.styleFrom(
          backgroundColor: NightColors.glow,
          foregroundColor: NightColors.ink,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const Text('免費轉一次', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      );
    } else if (widget.ads != null && adLeft > 0) {
      button = AdButton(
        key: const ValueKey('wheel_ad'),
        label: '看廣告再轉一次（今天還剩 $adLeft 次）',
        onPressed: _busy ? null : () => _spin(byAd: true),
      );
    } else {
      button = const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('今天的轉盤轉完了，明天再來！',
            key: ValueKey('wheel_done'),
            textAlign: TextAlign.center,
            style: TextStyle(color: NightColors.mist, fontSize: 14)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('夜市轉盤', style: TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Center(child: PrizeWheel(key: _wheelKey, size: 220, onStopped: _onWheelStopped)),
        const SizedBox(height: 10),
        button,
      ],
    );
  }

  /// 簽到後看廣告再領一次。
  Future<void> _doubleCheckIn() async {
    if (_busy || !await _watchAd()) return;
    final coins = await _store.doubleCheckIn();
    if (coins == 0 || !mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() {});
    _toast('再領一次簽到獎勵，獲得 🪙 $coins');
  }

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
    await _askReminder();
  }

  /// 第一次簽到後問一次要不要每天提醒（不在一打開 App 就跳權限詢問，玩家比較願意答應）。
  Future<void> _askReminder() async {
    final reminders = widget.reminders;
    if (reminders == null || _store.reminderAsked || _store.reminderOn) return;
    await _store.setReminderAsked();
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: const Text('每天提醒你簽到？', style: TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
        content: const Text('連續簽到獎勵越來越多。每天晚上 8 點提醒一次，隨時可以在設定裡關掉。',
            style: TextStyle(color: NightColors.ink, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不用了', style: TextStyle(color: NightColors.ink)),
          ),
          TextButton(
            key: const ValueKey('reminder_yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('好，提醒我', style: TextStyle(color: Color(0xFFA2580A), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true || !await reminders.requestPermission()) return;
    await _store.setReminderOn(true);
    await reminders.reschedule(_store);
  }

  Future<void> _claimMonthCard() async {
    final coins = await _store.claimMonthCard();
    if (coins == 0 || !mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() {});
    _toast('月卡今日獎勵，獲得 🪙 $coins');
  }

  /// 夜市月卡的每日領取（有月卡才顯示）。
  Widget _monthCardRow() {
    final canClaim = _store.canClaimMonthCard;
    return Container(
      key: const ValueKey('daily_month_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NightColors.glow.withValues(alpha: canClaim ? 0.9 : 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          const Text('📅', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('夜市月卡',
                    style: TextStyle(color: NightColors.glow, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                CoinText(
                  '每天 🪙 $monthCardDailyCoins・還剩 ${_store.monthCardDaysLeft} 天',
                  style: const TextStyle(color: NightColors.mist, fontSize: 13),
                ),
              ],
            ),
          ),
          if (canClaim)
            FilledButton(
              key: const ValueKey('claim_month_card'),
              onPressed: _claimMonthCard,
              style: FilledButton.styleFrom(backgroundColor: NightColors.glow, foregroundColor: NightColors.ink),
              child: const Text('領取', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            const Text('今天已領', style: TextStyle(color: NightColors.jade, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _claim(DailyTask task, {bool doubled = false}) async {
    if (doubled && (_busy || !await _watchAd())) return;
    if (!await _store.claimDaily(task, doubled: doubled) || !mounted) return;
    widget.sounds.play(Sfx.coin);
    setState(() {});
    _toast('獲得 🪙 ${task.coins * (doubled ? 2 : 1)}');
  }

  Future<void> _openChest({bool doubled = false}) async {
    if (doubled && (_busy || !await _watchAd())) return;
    if (!await _store.openDailyChest(doubled: doubled) || !mounted) return;
    widget.sounds.play(Sfx.win);
    setState(() {});
    _toast('寶箱打開了！獲得 🪙 ${dailyChestCoins * (doubled ? 2 : 1)} 和 ${ItemType.luckyCat.emoji} ${ItemType.luckyCat.label}');
  }

  /// 任務全部領完的寶箱：顯示進度，能開時發光。
  Widget _chestRow() {
    final total = _store.todayTasks.length;
    final claimed = _store.dailyTasksClaimed;
    final opened = _store.dailyChestOpened;
    final ready = _store.canOpenDailyChest;
    return Container(
      key: const ValueKey('daily_chest'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ready ? const Color(0xFF4A2A0E) : NightColors.stall,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ready ? NightColors.glow : NightColors.glow.withValues(alpha: 0.3), width: ready ? 2 : 1),
        boxShadow: ready ? [BoxShadow(color: NightColors.glow.withValues(alpha: 0.35), blurRadius: 14)] : null,
      ),
      child: Row(
        children: [
          Text(opened ? '🎉' : '🎁', style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('全部完成寶箱',
                    style: TextStyle(color: NightColors.paper, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                CoinText(
                  opened
                      ? '明天再來開新的寶箱'
                      : '$claimed / $total 個任務已領・🪙 $dailyChestCoins ＋ ${ItemType.luckyCat.emoji} ${ItemType.luckyCat.label}',
                  key: const ValueKey('daily_chest_text'),
                  style: const TextStyle(color: NightColors.mist, fontSize: 13),
                ),
              ],
            ),
          ),
          if (opened)
            const Text('已開啟', style: TextStyle(color: NightColors.jade, fontWeight: FontWeight.w700))
          else if (ready) ...[
            if (widget.ads != null) ...[
              OutlinedButton(
                key: const ValueKey('daily_chest_double'),
                onPressed: _busy ? null : () => _openChest(doubled: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NightColors.glow,
                  side: const BorderSide(color: NightColors.glow),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('廣告 ×2', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
            ],
            FilledButton(
              key: const ValueKey('daily_chest_open'),
              onPressed: _busy ? null : _openChest,
              style: FilledButton.styleFrom(backgroundColor: NightColors.glow, foregroundColor: NightColors.ink),
              child: const Text('開啟', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
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
          if (_store.monthCardActive) ...[
            _monthCardRow(),
            const SizedBox(height: 18),
          ],
          _wheelSection(),
          const SizedBox(height: 22),
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
          if (widget.ads != null && _store.canDoubleCheckIn) ...[
            const SizedBox(height: 8),
            AdButton(
              key: const ValueKey('check_in_double'),
              label: '看廣告再領一次 🪙 ${checkInRewards[_store.checkInStreak - 1]}',
              onPressed: _busy ? null : _doubleCheckIn,
            ),
          ],
          const SizedBox(height: 22),
          const Text('今日任務', style: TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          for (final task in DailyScreen.orderedTasks(_store)) ...[
            _taskRow(task),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          _chestRow(),
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
          else if (done) ...[
            if (widget.ads != null) ...[
              // 看廣告領雙倍
              OutlinedButton(
                key: ValueKey('daily_double_${task.id}'),
                onPressed: _busy ? null : () => _claim(task, doubled: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NightColors.glow,
                  side: const BorderSide(color: NightColors.glow),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('廣告 ×2', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
            ],
            FilledButton(
              key: ValueKey('daily_${task.id}'),
              onPressed: _busy ? null : () => _claim(task),
              style: FilledButton.styleFrom(backgroundColor: NightColors.glow, foregroundColor: NightColors.ink),
              child: const Text('領取', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}
