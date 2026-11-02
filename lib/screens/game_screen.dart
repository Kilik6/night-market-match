import 'dart:async';

import 'package:flutter/material.dart';

import '../game/matching_game.dart';
import '../widgets/card_widget.dart';

/// 遊戲畫面，對應 React Native 版 App.tsx 的 render()。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.game});

  /// 測試時可以傳入固定洗牌結果的遊戲。
  final MatchingGame? game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final MatchingGame _game = widget.game ?? MatchingGame();
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onCardTap(int index) {
    final result = _game.pick(index);
    if (result == PickResult.ignored) return;
    setState(() {});

    if (result == PickResult.mismatched) {
      // 對應 RN 版的 setTimeout(..., 1000)
      _hideTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(_game.hideMismatched);
      });
    }
  }

  void _resetGame() {
    _hideTimer?.cancel();
    setState(_game.reset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 頁首：遊戲標題（RN 版 flex: 1）
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFEEEEEE),
                  image: DecorationImage(
                    image: AssetImage('assets/images/pencil.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'FC Matching Game',
                  style: TextStyle(color: Color(0xFF423838), fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // 頁身：遊戲主板（RN 版 flex: 3）
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: Colors.white,
                child: Center(child: _buildBoard()),
              ),
            ),
            // 頁尾：步數統計與重玩按鈕（RN 版 flex: 1）
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/pencil_01.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: _buildFooter(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard() {
    // RN 版用 flexWrap 排成每列 4 張；這裡固定 4 欄，間距依螢幕寬度計算
    const cardSize = 58.0;
    return LayoutBuilder(builder: (context, constraints) {
      final gap = ((constraints.maxWidth - cardSize * 4) / 6).clamp(8.0, 24.0);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < _game.cards.length; i++)
            SizedBox(
              width: cardSize,
              height: cardSize,
              child: CardWidget(
                key: ValueKey('card_$i'),
                title: _game.cards[i],
                isShow: _game.isOpen[i],
                size: cardSize,
                onTap: () => _onCardTap(i),
              ),
            ),
        ],
      ).constrainedTo(cardSize * 4 + gap * 3);
    });
  }

  Widget _buildFooter() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _game.isEnded
              ? 'Congrats! You have completed in ${_game.steps} steps.'
              : 'You have tried ${_game.steps} time(s).',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20),
        ),
        if (_game.isEnded)
          Flexible(
            child: GestureDetector(
              onTap: _resetGame,
              child: Container(
                width: 160,
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/gray-button.png'),
                    fit: BoxFit.contain,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('Try Again', style: TextStyle(fontSize: 22)),
              ),
            ),
          ),
      ],
    );
  }
}

extension on Widget {
  /// 限制最大寬度，讓 Wrap 剛好排成 4 欄。
  Widget constrainedTo(double maxWidth) =>
      ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: this);
}
