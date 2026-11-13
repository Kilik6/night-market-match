import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/night_market_data.dart';
import '../theme.dart';
import 'card_patterns.dart';
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
  });

  final Food food;
  final bool isShow;
  final bool isMatched;
  final VoidCallback onTap;
  final double width;

  /// 沒指定就用預設的紅燈籠。
  final CardSkin? skin;

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

  Widget _back() => CardBack(skin: skin ?? cardSkins.first, width: width);

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
///
/// 紅燈籠是單色底加大字；其他卡背是「花紋＋內框和四角裝飾＋中間的圓形徽章」，
/// 摸麻將的中間是一張大大的「發」牌。
class CardBack extends StatelessWidget {
  const CardBack({super.key, required this.skin, required this.width});

  final CardSkin skin;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (skin.pattern == CardPattern.plain) return _plain();
    return Container(
      decoration: BoxDecoration(
        color: skin.base,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.edge, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 花紋只畫一次，翻牌動畫時不重畫
            RepaintBoundary(child: CustomPaint(painter: CardPatternPainter(skin))),
            CustomPaint(painter: _FramePainter(color: skin.markColor, width: width)),
            Center(child: skin.pattern == CardPattern.mahjong ? _mahjongTile() : _medallion()),
          ],
        ),
      ),
    );
  }

  /// 原本的樣子：單色底、細內框、中間大字。
  Widget _plain() {
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
        padding: const EdgeInsets.all(2),
        // 小卡片放不下時縮小，不會超出卡背
        child: FittedBox(fit: BoxFit.scaleDown, child: _markText(width * 0.32 * skin.markScale)),
      ),
    );
  }

  Widget _markText(double fontSize) => Text(
        skin.mark,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: skin.markColor.withValues(alpha: 0.9),
        ),
      );

  /// 中間的圓形徽章：深一點的底、外圈、細內圈和光暈，讓圖案在花紋上也清楚。
  Widget _medallion() {
    final d = width * 0.58;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: Color.lerp(skin.base, Colors.black, 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: skin.edge, width: max(1.5, width / 75)),
        boxShadow: [BoxShadow(color: skin.edge.withValues(alpha: 0.7), blurRadius: d * 0.18)],
      ),
      padding: EdgeInsets.all(d * 0.05),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: skin.markColor.withValues(alpha: 0.45), width: max(0.8, width / 220)),
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.all(d * 0.02),
        child: FittedBox(fit: BoxFit.scaleDown, child: _markText(d * 0.5 * skin.markScale)),
      ),
    );
  }

  /// 摸麻將的中間：一張大大的「發」牌，白色牌面、底下露出藍綠色的牌背厚度。
  Widget _mahjongTile() {
    final h = width * 0.56;
    final radius = BorderRadius.circular(h * 0.12);
    return Container(
      width: h * 0.76,
      height: h,
      padding: EdgeInsets.only(bottom: h * 0.08),
      decoration: BoxDecoration(
        color: const Color(0xFF1B8FB3),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: const Color(0xFFFFF3C4).withValues(alpha: 0.85), blurRadius: h * 0.2),
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), offset: Offset(h * 0.03, h * 0.05)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: const Color(0xFFB8C4C9), width: max(0.6, h * 0.02)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFE9EEF0)],
          ),
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.all(h * 0.06),
        child: FittedBox(fit: BoxFit.scaleDown, child: _markText(h * 0.62)),
      ),
    );
  }
}

/// 卡背的細內框和四個角的菱形小裝飾。
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = max(3.0, width * 0.055);
    final rect = (Offset.zero & size).deflate(inset);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(max(3.0, width * 0.045))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, width / 150)
        ..color = color.withValues(alpha: 0.55),
    );
    final d = max(1.5, width / 37);
    final fill = Paint()..color = color.withValues(alpha: 0.85);
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - d)
          ..lineTo(c.dx + d, c.dy)
          ..lineTo(c.dx, c.dy + d)
          ..lineTo(c.dx - d, c.dy)
          ..close(),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.color != color || oldDelegate.width != width;
}
