import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/night_market_data.dart';
import '../theme.dart';
import 'food_icon.dart';
import 'match_effects.dart';

/// 單張夜市卡片：卡背依造型（預設紅色寫「夜」），翻開是小吃 emoji 和名稱，有 3D 翻牌動畫。
class CardWidget extends StatelessWidget {
  const CardWidget({
    super.key,
    required this.food,
    required this.isShow,
    required this.isMatched,
    required this.onTap,
    required this.width,
    this.skin,
    this.badge,
  });

  final Food food;
  final bool isShow;
  final bool isMatched;
  final VoidCallback onTap;
  final double width;

  /// 沒指定就用預設的紅燈籠。
  final CardSkin? skin;

  /// 卡背右上角的小標籤（例如「新」），翻開時不顯示。
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return PulseOnIncrease(
      // 配對成功時彈跳發光；delay 是等翻牌動畫跑完
      trigger: isMatched ? 1 : 0,
      scale: 1.16,
      duration: const Duration(milliseconds: 750),
      delay: 0.35,
      glow: NightColors.jade,
      child: Semantics(
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
      ),
    );
  }

  Widget _back() {
    final back = CardBack(skin: skin ?? cardSkins.first, width: width);
    if (badge == null) return back;
    return Stack(
      children: [
        Positioned.fill(child: back),
        Positioned(
          top: 3,
          right: 3,
          child: Container(
            key: const ValueKey('card_badge'),
            padding: EdgeInsets.symmetric(horizontal: max(3, width * 0.05), vertical: 1),
            decoration: BoxDecoration(
              color: NightColors.glow,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
            ),
            child: Text(
              badge!,
              style: TextStyle(color: NightColors.ink, fontSize: max(9, width * 0.15), fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
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
          FoodIcon(food: food, size: width * 0.4),
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

/// 卡背，也用在商店的預覽。
class CardBack extends StatelessWidget {
  const CardBack({super.key, required this.skin, required this.width});

  final CardSkin skin;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: skin.base,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.edge, width: 2),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: skin.markColor.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Text(
          skin.mark,
          style: TextStyle(
            fontSize: width * 0.32,
            fontWeight: FontWeight.w700,
            color: skin.markColor.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
