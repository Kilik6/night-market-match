import 'dart:math';

import 'package:flutter/material.dart';

import '../game/night_market_data.dart';
import '../theme.dart';

/// 單張夜市卡片：紅色卡背寫「夜」，翻開是小吃 emoji 和名稱，有 3D 翻牌動畫。
class CardWidget extends StatelessWidget {
  const CardWidget({
    super.key,
    required this.food,
    required this.isShow,
    required this.isMatched,
    required this.onTap,
    required this.width,
  });

  final Food food;
  final bool isShow;
  final bool isMatched;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      label: isShow ? food.name : '蓋著的卡片',
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: isShow ? pi : 0),
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          builder: (context, angle, _) {
            final showFront = angle > pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(angle),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(pi),
                      child: _front(),
                    )
                  : _back(),
            );
          },
        ),
      ),
    );
  }

  Widget _back() {
    return Container(
      decoration: BoxDecoration(
        color: NightColors.lantern,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF2735F), width: 2),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: NightColors.paper.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Text(
          '夜',
          style: TextStyle(
            fontSize: width * 0.32,
            fontWeight: FontWeight.w700,
            color: NightColors.paper.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _front() {
    return Container(
      decoration: BoxDecoration(
        color: isMatched ? NightColors.matched : NightColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: isMatched ? Border.all(color: NightColors.jade, width: 2) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(food.emoji, style: TextStyle(fontSize: width * 0.4)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              food.name,
              style: TextStyle(
                fontSize: max(10, width * 0.15),
                fontWeight: FontWeight.w700,
                color: NightColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
