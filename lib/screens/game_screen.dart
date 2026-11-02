import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/matching_game.dart';
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/lanterns.dart';

/// 夜市翻牌主畫面：招牌、夜市選單、時間／分數／連擊、牌桌、廣告按鈕。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.store, required this.ads, required this.sounds, this.random});

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

  /// 測試時傳入固定種子，讓洗牌結果可預測。
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _Choice { primary, watchAd }

class _GameScreenState extends State<GameScreen> {
  /// 每過幾關播一次插頁式廣告。
  static const interstitialEvery = 3;
  static const peekDuration = Duration(seconds: 2);

  int _levelIndex = 0;
  late MatchingGame _game;
  Timer? _clock;
  Timer? _hideTimer;
  Timer? _peekTimer;

  /// 播廣告時暫停倒數。
  bool _paused = false;
  String _message = '翻兩張一樣的小吃就能配對';

  ProgressStore get _store => widget.store;
  SoundService get _sounds => widget.sounds;

  void _toggleMute() {
    final muted = !_sounds.muted;
    _sounds.muted = muted;
    _store.setMuted(muted);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // 從上次解鎖到的最後一攤開始
    _startLevel(_store.unlocked.clamp(1, levels.length) - 1);
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

  /// 播放獎勵型廣告，播放期間暫停倒數。
  Future<bool> _watchRewarded() async {
    setState(() => _paused = true);
    final earned = await widget.ads.showRewarded();
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
    final choice = await showDialog<_Choice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResultDialog(
        title: '收攤！${_game.level.name}完成',
        stars: _game.stars,
        lines: [
          '剩餘 ${_game.timeLeft} 秒，時間獎勵 +${_game.timeBonus}',
          '總分 ${_game.score}，獲得 🪙 $earned',
        ],
        adLabel: '看廣告，金幣 ×2',
        primaryLabel: hasNext ? '前往下一攤：${levels[_levelIndex + 1].name}' : '再玩一次',
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
      await widget.ads.showInterstitial();
      if (!mounted) return;
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
      ),
    );
    if (!mounted) return;

    if (choice == _Choice.watchAd) {
      final earned = await _watchRewarded();
      if (!mounted) return;
      if (earned && _game.revive()) {
        setState(() => _message = '多 ${MatchingGame.reviveSeconds} 秒，加油！');
        _startClock();
      } else {
        await _showLoseDialog(); // 廣告沒播成功，回到時間到的視窗
      }
      return;
    }
    setState(() => _startLevel(_levelIndex));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NightColors.night,
      body: DecoratedBox(
        // 頂端燈光暈染
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.0,
            colors: [Color(0x29FFB547), Color(0x00FFB547)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Lanterns(),
                const SizedBox(height: 6),
                _buildSign(),
                const SizedBox(height: 12),
                _buildLevelMap(),
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
      ),
    );
  }

  Widget _buildSign() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NightColors.glow, width: 2),
        boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.25), blurRadius: 24)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '夜市翻牌',
                  style: TextStyle(
                    color: NightColors.glow,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    shadows: [Shadow(color: NightColors.glow.withValues(alpha: 0.55), blurRadius: 12)],
                  ),
                ),
                Text(
                  '第 ${_levelIndex + 1} 攤・${_game.level.name}',
                  style: const TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1),
                ),
              ],
            ),
          ),
          Text(
            '🪙 ${_store.coins}',
            key: const ValueKey('coins'),
            style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          IconButton(
            key: const ValueKey('mute'),
            tooltip: _sounds.muted ? '開啟音效' : '關閉音效',
            onPressed: _toggleMute,
            color: NightColors.mist,
            icon: Icon(_sounds.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelMap() {
    final unlocked = _store.unlocked;
    return Row(
      children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              key: ValueKey('level_$i'),
              onPressed:
                  i < unlocked && i != _levelIndex && !_paused ? () => setState(() => _startLevel(i)) : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                foregroundColor: NightColors.mist,
                disabledForegroundColor:
                    i == _levelIndex ? NightColors.glow : NightColors.mist.withValues(alpha: 0.35),
                side: BorderSide(
                  color: i == _levelIndex ? NightColors.glow : NightColors.paper.withValues(alpha: 0.18),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${i < unlocked ? '' : '🔒 '}${levels[i].name}', style: const TextStyle(fontSize: 13)),
              ),
            ),
          ),
        ],
      ],
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
    const columns = 4;
    const gap = 8.0;
    final rows = (_game.cards.length / columns).ceil();
    return LayoutBuilder(builder: (context, constraints) {
      // 卡片比例 3:4，取「寬度放得下」和「高度放得下」中較小的尺寸
      final byWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final byHeight = (constraints.maxHeight - gap * (rows - 1)) / rows * 3 / 4;
      final cardWidth = min(byWidth, byHeight);
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
              for (var i = 0; i < _game.cards.length; i++)
                SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: CardWidget(
                    key: ValueKey('card_$i'),
                    food: _game.cards[i],
                    isShow: _game.isFaceUp(i),
                    isMatched: _game.isMatched[i],
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

/// 有「廣告」標籤的虛線風格按鈕，讓玩家一眼看出按了會播廣告。
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
    this.adLabel,
    this.stars,
  });

  final String title;
  final List<String> lines;
  final String primaryLabel;
  final String? adLabel;
  final int? stars;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NightColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
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
          ],
        ),
      ),
    );
  }
}
