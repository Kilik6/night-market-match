import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/matching_game.dart';
import '../game/night_market_data.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/lanterns.dart';

/// 夜市翻牌主畫面：招牌、夜市選單、時間／分數／連擊、牌桌。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.random});

  /// 測試時傳入固定種子，讓洗牌結果可預測。
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // 進度先放在記憶體，第 4 步再加存檔。
  int _coins = 0;
  int _unlocked = 1;
  int _levelIndex = 0;

  late MatchingGame _game;
  Timer? _clock;
  Timer? _hideTimer;
  String _message = '翻兩張一樣的小吃就能配對';

  @override
  void initState() {
    super.initState();
    _startLevel(0);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startLevel(int index) {
    _clock?.cancel();
    _hideTimer?.cancel();
    _levelIndex = index;
    _game = MatchingGame(level: levels[index], random: widget.random);
    _message = '翻兩張一樣的小吃就能配對';
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    final timeUp = _game.tick();
    setState(() {});
    if (timeUp) {
      _clock?.cancel();
      _hideTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _showLoseDialog();
      });
    }
  }

  void _onCardTap(int index) {
    final result = _game.pick(index);
    if (result == PickResult.ignored) return;

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

  Future<void> _showWinDialog() async {
    final earned = _game.coinsEarned;
    final hasNext = _levelIndex + 1 < levels.length;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResultDialog(
        title: '收攤！${_game.level.name}完成',
        stars: _game.stars,
        lines: [
          '剩餘 ${_game.timeLeft} 秒，時間獎勵 +${_game.timeBonus}',
          '總分 ${_game.score}，獲得 🪙 $earned',
        ],
        primaryLabel: hasNext ? '前往下一攤：${levels[_levelIndex + 1].name}' : '再玩一次',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _coins += earned;
      if (hasNext) {
        _unlocked = max(_unlocked, _levelIndex + 2);
        _startLevel(_levelIndex + 1);
      } else {
        _startLevel(_levelIndex);
      }
    });
  }

  Future<void> _showLoseDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResultDialog(
        title: '時間到了',
        lines: ['還差 ${_game.pairsLeft} 組就收攤了'],
        primaryLabel: '重新開始這一攤',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
    if (!mounted) return;
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
            '🪙 $_coins',
            key: const ValueKey('coins'),
            style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelMap() {
    return Row(
      children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              key: ValueKey('level_$i'),
              onPressed: i < _unlocked && i != _levelIndex ? () => setState(() => _startLevel(i)) : null,
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
                child: Text('${i < _unlocked ? '' : '🔒 '}${levels[i].name}', style: const TextStyle(fontSize: 13)),
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
        value: _game.timeLeft / _game.level.seconds,
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
                    isShow: _game.isOpen[i],
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

/// 過關／時間到的結果視窗，菜單紙風格。
class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.title,
    required this.lines,
    required this.primaryLabel,
    required this.onPrimary,
    this.stars,
  });

  final String title;
  final List<String> lines;
  final String primaryLabel;
  final VoidCallback onPrimary;
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
                style: const TextStyle(color: Color(0xFFD9A21B), fontSize: 30, letterSpacing: 6),
              ),
            ],
            const SizedBox(height: 10),
            for (final line in lines)
              Text(line, textAlign: TextAlign.center, style: const TextStyle(color: NightColors.ink, height: 1.6)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: NightColors.glow,
                  foregroundColor: NightColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
