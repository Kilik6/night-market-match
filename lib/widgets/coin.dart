import 'dart:math';

import 'package:flutter/material.dart';

/// 卡通風格的金幣圖示：亮黃色圓形、深金色外框、中間一道凸起的直條，左上角有反光。
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _CoinPainter()),
    );
  }
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();

  static const _rim = Color(0xFFC77800); // 外框深金
  static const _edge = Color(0xFFF2A900); // 外圈
  static const _face = Color(0xFFFFD43B); // 金幣面
  static const _faceLight = Color(0xFFFFEB80); // 金幣面亮部
  static const _emboss = Color(0xFFE59A00); // 凸起直條的陰影

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // 外框和外圈
    canvas.drawCircle(c, r, Paint()..color = _rim);
    canvas.drawCircle(c, r * 0.88, Paint()..color = _edge);

    // 金幣面：左上亮、右下暗的漸層
    final face = Rect.fromCircle(center: c, radius: r * 0.72);
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 1.0,
          colors: [_faceLight, _face],
        ).createShader(face),
    );

    // 中間凸起的直條：先畫陰影再畫亮面，看起來有立體感
    final barW = r * 0.28;
    final barH = r * 0.9;
    RRect bar(Offset o) => RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + o, width: barW, height: barH),
          Radius.circular(barW / 2),
        );
    canvas.drawRRect(bar(Offset(r * 0.05, r * 0.05)), Paint()..color = _emboss);
    canvas.drawRRect(bar(Offset.zero), Paint()..color = _faceLight);

    // 左上角反光
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.8),
      pi * 1.05,
      pi * 0.4,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, r * 0.12)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CoinPainter oldDelegate) => false;
}

/// 顯示文字，把裡面的「🪙」換成 [CoinIcon]。文字照常用「🪙 300」寫，顯示時自動換成金幣圖示。
class CoinText extends StatelessWidget {
  const CoinText(this.text, {super.key, this.style, this.textAlign});

  static const marker = '🪙';

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (!text.contains(marker)) return Text(text, style: style, textAlign: textAlign);
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final iconSize = (effective.fontSize ?? 14) * 1.05;
    final parts = text.split(marker);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: CoinIcon(size: iconSize),
              ),
            if (parts[i].isNotEmpty) TextSpan(text: parts[i]),
          ],
        ],
      ),
      textAlign: textAlign,
      semanticsLabel: text.replaceAll(marker, '金幣'),
    );
  }
}
