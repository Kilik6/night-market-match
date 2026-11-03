import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/matching_game.dart';
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/night_scaffold.dart';

/// 闖關畫面：招牌（返回鍵、夜市名稱、金幣）、時間／分數／連擊、牌桌、廣告按鈕。
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.levelIndex,
    required this.store,
    required this.ads,
    required this.sounds,
    this.random,
  });

  /// 從哪一攤開始（過關後可以直接前往下一攤）。
  final int levelIndex;
  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

  /// 測試時傳入固定種子，讓洗牌結果可預測。
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _Choice { primary, watchAd, leave }

class _GameScreenState extends State<GameScreen> {
  /// 每過幾關播一次插頁式廣告。
  static const interstitialEvery = 3;
  static const peekDuration = Duration(seconds: 2);

  late int _levelIndex;
  late MatchingGame _game;
  Timer? _clock;
  Timer? _hideTimer;
  Timer? _peekTimer;

  /// 播廣告、問要不要離開時暫停倒數。
  bool _paused = false;
  String _message = '翻兩張一樣的小吃就能配對';

  ProgressStore get _store => widget.store;
  SoundService get _sounds => widget.sounds;

  @override
  void initState() {
    super.initState();
    _startLevel(widget.levelIndex.clamp(0, levels.length - 1));
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _clock?.cancel();
    _hideTimer?.cancel();
    _peekTimer?.cancel();
  }

  void _startLevel(int index) {
    _cancelTimers();
    _paused = false;
    _levelIndex = index;
    _game = MatchingGame(level: levels[index], random: widget.random);
    _message = '翻兩張一樣的小吃就能配對';
    _startClock();
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted || _paused) return;
    final timeUp = _game.tick();
    setState(() {});
    if (timeUp) {
      _clock?.cancel();
      _hideTimer?.cancel();
      _sounds.play(Sfx.lose);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _showLoseDialog();
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _leave() => Navigator.of(context).pop();

  /// 按返回鍵：遊戲進行中先問一下，避免誤觸。
  Future<void> _onBack() async {
    if (_game.isEnded) {
      _leave();
      return;
    }
    setState(() => _paused = true);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: const Text('離開這一攤？', style: TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
        content: const Text('這一局的進度不會保存。', style: TextStyle(color: NightColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('繼續玩', style: TextStyle(color: NightColors.ink)),
          ),
          TextButton(
            key: const ValueKey('confirm_leave'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('離開', style: TextStyle(color: Color(0xFFC0392B), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (leave == true) {
      _cancelTimers();
      _leave();
    } else {
      setState(() => _paused = false);
    }
  }

  /// 播全螢幕廣告時暫停背景音樂。
  Future<T> _duringAd<T>(Future<T> Function() show) async {
    _sounds.pauseMusic();
    try {
      return await show();
    } finally {
      _sounds.resumeMusic();
    }
  }

  /// 播放獎勵型廣告，播放期間暫停倒數。
  Future<bool> _watchRewarded() async {
    setState(() => _paused = true);
    final earned = await _duringAd(widget.ads.showRewarded);
    if (mounted) setState(() => _paused = false);
    if (!earned && mounted) _toast('廣告目前無法播放，請稍後再試');
    return earned;
  }

  void _onCardTap(int index) {
    if (_paused) return;
    final result = _game.pick(index);
    if (result == PickResult.ignored) return;
    _sounds.play(switch (result) {
      PickResult.matched => _game.lastCombo >= 3 ? Sfx.combo : Sfx.match,
      PickResult.finished => Sfx.win,
      PickResult.mismatched => Sfx.miss,
      _ => Sfx.flip,
    });

    setState(() {
      switch (result) {
        case PickResult.matched:
        case PickResult.finished:
          final name = _game.lastMatched!.name;
          _message = _game.lastCombo > 1
              ? '$name！${_game.lastCombo} 連擊 +${_game.lastPoints}'
              : '$name，配對成功 +${_game.lastPoints}';
        case PickResult.mismatched:
          _message = '不一樣，連擊中斷';
        default:
          break;
      }
    });

    if (result == PickResult.mismatched) {
      _hideTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(_game.hideMismatched);
      });
    } else if (result == PickResult.finished) {
      _clock?.cancel();
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _showWinDialog();
      });
    }
  }

  /// 看廣告：偷看全部卡片 2 秒（每局一次）。
  Future<void> _onPeek() async {
    if (!_game.canPeek || _paused) return;
    final earned = await _watchRewarded();
    if (!earned || !mounted || !_game.canPeek) return;
    _hideTimer?.cancel();
    _sounds.play(Sfx.flip);
    setState(() {
      _game.startPeek();
      _message = '記住位置！';
    });
    _peekTimer = Timer(peekDuration, () {
      if (mounted) setState(_game.endPeek);
    });
  }

  Future<void> _showWinDialog() async {
    final earned = _game.coinsEarned;
    final hasNext = _levelIndex + 1 < levels.length;
    final isRecord = await _store.recordStars(_levelIndex, _game.stars);
    if (!mounted) return;
    final choice = await showDialog<_Choice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResultDialog(
        title: '收攤！${_game.level.name}完成',
        stars: _game.stars,
        lines: [
          '剩餘 ${_game.timeLeft} 秒，時間獎勵 +${_game.timeBonus}',
          '總分 ${_game.score}，獲得 🪙 $earned',
          if (isRecord && _game.stars > 1) '刷新這一攤的最佳紀錄！',
          if (!hasNext) '恭喜逛完所有夜市！',
        ],
        adLabel: '看廣告，金幣 ×2',
        primaryLabel: hasNext ? '前往下一攤：${levels[_levelIndex + 1].name}' : '再玩一次',
        leaveLabel: '回到夜市列表',
      ),
    );
    if (!mounted) return;

    var coins = earned;
    var watchedAd = false;
    if (choice == _Choice.watchAd) {
      watchedAd = await _watchRewarded();
      if (watchedAd) coins *= 2;
    }

    await _store.addCoins(coins);
    if (hasNext) await _store.unlockUpTo(_levelIndex + 2);
    final clears = await _store.addClear();
    if (!mounted) return;
    _sounds.play(Sfx.coin);
    if (watchedAd) _toast('金幣 ×2，獲得 🪙 $coins');

    // 每過 3 關播一次插頁式廣告；剛看完獎勵型廣告的那次不播，買了移除廣告也不播
    if (clears % interstitialEvery == 0 && !watchedAd && !_store.adsRemoved) {
      await _duringAd(widget.ads.showInterstitial);
      if (!mounted) return;
    }

    if (choice == _Choice.leave) {
      _leave();
      return;
    }
    setState(() => _startLevel(hasNext ? _levelIndex + 1 : _levelIndex));
  }

  Future<void> _showLoseDialog() async {
    final choice = await showDialog<_Choice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResultDialog(
        title: '時間到了',
        lines: ['還差 ${_game.pairsLeft} 組就收攤了'],
        adLabel: _game.canRevive ? '看廣告 +${MatchingGame.reviveSeconds} 秒繼續' : null,
        primaryLabel: '重新開始這一攤',
        leaveLabel: '回到夜市列表',
      ),
    );
    if (!mounted) return;

    switch (choice) {
      case _Choice.watchAd:
        final earned = await _watchRewarded();
        if (!mounted) return;
        if (earned && _game.revive()) {
          setState(() => _message = '多 ${MatchingGame.reviveSeconds} 秒，加油！');
          _startClock();
        } else {
          await _showLoseDialog(); // 廣告沒播成功，回到時間到的視窗
        }
      case _Choice.leave:
        _leave();
      case _Choice.primary:
      case null:
        setState(() => _startLevel(_levelIndex));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 攔下 Android 返回鍵／iOS 返回手勢，改走 _onBack 的確認流程
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: NightScaffold(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSign(),
              const SizedBox(height: 12),
              _buildHud(),
              const SizedBox(height: 8),
              _buildTimeBar(),
              const SizedBox(height: 12),
              Expanded(child: _buildBoard()),
              const SizedBox(height: 10),
              Text(
                _message,
                key: const ValueKey('message'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _AdButton(
                key: const ValueKey('peek'),
                label: '看廣告：偷看全部 2 秒',
                onPressed: _game.canPeek && !_paused ? _onPeek : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSign() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
      decoration: BoxDecoration(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NightColors.glow, width: 2),
        boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.25), blurRadius: 24)],
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('back'),
            tooltip: '返回',
            onPressed: _onBack,
            color: NightColors.paper,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _game.level.name,
                  style: TextStyle(
                    color: NightColors.glow,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    shadows: [Shadow(color: NightColors.glow.withValues(alpha: 0.55), blurRadius: 12)],
                  ),
                ),
                Text(
                  '第 ${_levelIndex + 1} 攤・${_game.level.city}',
                  style: const TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1),
                ),
              ],
            ),
          ),
          CoinBadge(coins: _store.coins),
        ],
      ),
    );
  }

  Widget _buildHud() {
    Widget cell(String label, String value, Key key) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Text(label, style: const TextStyle(color: NightColors.mist, fontSize: 11, letterSpacing: 1.5)),
                Text(
                  value,
                  key: key,
                  style: const TextStyle(
                    color: NightColors.paper,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        cell('時間', '${_game.timeLeft}', const ValueKey('time')),
        const SizedBox(width: 8),
        cell('分數', '${_game.score}', const ValueKey('score')),
        const SizedBox(width: 8),
        cell('連擊', '×${_game.combo}', const ValueKey('combo')),
      ],
    );
  }

  Widget _buildTimeBar() {
    final low = _game.timeLeft <= 10;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: _game.timeLeft / max(_game.level.seconds, _game.timeLeft),
        minHeight: 6,
        backgroundColor: NightColors.stall,
        color: low ? NightColors.lantern : NightColors.glow,
      ),
    );
  }

  Widget _buildBoard() {
    const gap = 8.0;
    final count = _game.cards.length;
    final skin = skinById(_store.equippedSkin);
    return LayoutBuilder(builder: (context, constraints) {
      // 試 4～6 欄，選卡片最大的排法。卡片比例 3:4，取「寬度放得下」和「高度放得下」中較小的尺寸
      var columns = 4;
      var cardWidth = 0.0;
      for (var c = 4; c <= 6; c++) {
        final rows = (count / c).ceil();
        final byWidth = (constraints.maxWidth - gap * (c - 1)) / c;
        final byHeight = (constraints.maxHeight - gap * (rows - 1)) / rows * 3 / 4;
        final w = min(byWidth, byHeight);
        if (w > cardWidth + 0.5) {
          columns = c;
          cardWidth = w;
        }
      }
      final cardHeight = cardWidth * 4 / 3;
      return Center(
        // 每局換新的 key，讓卡片整組重建；否則換關時會播放上一局卡片蓋回去的動畫
        key: ObjectKey(_game),
        child: SizedBox(
          width: cardWidth * columns + gap * (columns - 1),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: CardWidget(
                    key: ValueKey('card_$i'),
                    food: _game.cards[i],
                    isShow: _game.isFaceUp(i),
                    isMatched: _game.isMatched[i],
                    skin: skin,
                    width: cardWidth,
                    onTap: () => _onCardTap(i),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// 有「廣告」標籤的按鈕，讓玩家一眼看出按了會播廣告。
class _AdButton extends StatelessWidget {
  const _AdButton({super.key, required this.label, required this.onPressed, this.onPaper = false});

  final String label;
  final VoidCallback? onPressed;

  /// 放在米色結果視窗上時改用深一點的顏色。
  final bool onPaper;

  @override
  Widget build(BuildContext context) {
    final color = onPaper ? const Color(0xFFA2580A) : NightColors.glow;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: 0.4),
        side: BorderSide(color: onPressed == null ? color.withValues(alpha: 0.3) : color, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: onPressed == null ? color.withValues(alpha: 0.4) : color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '廣告',
              style: TextStyle(fontSize: 11, color: onPaper ? NightColors.paper : NightColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// 過關／時間到的結果視窗，菜單紙風格。關閉時回傳玩家的選擇。
class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.title,
    required this.lines,
    required this.primaryLabel,
    required this.leaveLabel,
    this.adLabel,
    this.stars,
  });

  final String title;
  final List<String> lines;
  final String primaryLabel;
  final String leaveLabel;
  final String? adLabel;
  final int? stars;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NightColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NightColors.ink, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (stars != null) ...[
              const SizedBox(height: 8),
              Text(
                '${'★' * stars!}${'☆' * (3 - stars!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD9A21B), fontSize: 30, letterSpacing: 6),
              ),
            ],
            const SizedBox(height: 10),
            for (final line in lines)
              Text(line, textAlign: TextAlign.center, style: const TextStyle(color: NightColors.ink, height: 1.6)),
            const SizedBox(height: 16),
            if (adLabel != null) ...[
              _AdButton(
                key: const ValueKey('dialog_ad'),
                label: adLabel!,
                onPaper: true,
                onPressed: () => Navigator.of(context).pop(_Choice.watchAd),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_Choice.primary),
              style: FilledButton.styleFrom(
                backgroundColor: NightColors.glow,
                foregroundColor: NightColors.ink,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('dialog_leave'),
              onPressed: () => Navigator.of(context).pop(_Choice.leave),
              child: Text(leaveLabel, style: const TextStyle(color: NightColors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}
