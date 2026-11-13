import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';

/// 卡背的花紋。只畫底紋，外框、內框和中間的圖案由 [CardBack] 負責。
///
/// 花紋大小依卡片寬度等比縮放，但有最小尺寸：卡片很小時花紋變少變大，不會糊成一片。
/// 隨機散布的花紋（星點、紙花）用固定的種子，每次畫出來都一樣。
class CardPatternPainter extends CustomPainter {
  const CardPatternPainter(this.skin);

  final CardSkin skin;

  Color _lighter(Color c, double t) => Color.lerp(c, Colors.white, t)!;
  Color _darker(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final w = size.width;
    final base = skin.base;
    final light = _lighter(base, 0.18);
    final dark = _darker(base, 0.22);
    final paint = Paint()..isAntiAlias = true;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final random = Random(skin.id.hashCode);

    switch (skin.pattern) {
      case CardPattern.plain:
        break;

      case CardPattern.lattice:
        // 菱格窗花：斜線交錯，交點有小亮點
        final step = max(w / 8.5, 9.0);
        stroke
          ..color = _darker(base, 0.28).withValues(alpha: 0.7)
          ..strokeWidth = max(w / 110, 1);
        for (var x = -r.height; x < r.width + r.height; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x + r.height, r.height), stroke);
          canvas.drawLine(Offset(x, r.height), Offset(x + r.height, 0), stroke);
        }
        paint.color = _lighter(base, 0.45);
        var row = 0;
        for (var y = 0.0; y < r.height; y += step / 2, row++) {
          for (var x = row.isEven ? 0.0 : step / 2; x < r.width; x += step) {
            canvas.drawCircle(Offset(x, y), max(w / 90, 1), paint);
          }
        }

      case CardPattern.stars:
        // 散落的星點和一彎月亮
        final count = (w * w / 900).clamp(10, 55).round();
        for (var i = 0; i < count; i++) {
          paint.color = const Color(0xFFFFD873).withValues(alpha: 0.35 + random.nextDouble() * 0.6);
          canvas.drawCircle(
            Offset(random.nextDouble() * r.width, random.nextDouble() * r.height),
            max(w / 140, 0.8) * (0.6 + random.nextDouble()),
            paint,
          );
        }
        final moon = Offset(r.width * 0.8, r.height * 0.13);
        final mr = max(w / 15, 3.0);
        paint.color = light;
        canvas.drawCircle(moon, mr, paint);
        paint.color = base;
        canvas.drawCircle(moon + Offset(mr * 0.45, -mr * 0.2), mr * 0.95, paint);

      case CardPattern.mahjong:
        // 真的麻將牌面：萬子、條子、筒子、東南西北、紅中、白板
        const faces = ['1w', 'c5', 'b3', 'E', '7w', 'b6', 'Z', 'c2', 'S', '9w', 'P', 'c9', 'W', 'b4', '4w', 'N', 'c8', 'b5', '6w', 'c3', 'b7', 'F', 'c6', 'b9', '3w', 'c4', 'b8', 'c7', 'b2', '2w', 'c1', '8w', '5w'];
        final tw = max(w / 6.8, 14.0);
        final th = tw * 1.36;
        final gap = tw * 0.12;
        var k = 0;
        var row = 0;
        for (var y = gap; y < r.height; y += th * 1.08 + gap, row++) {
          for (var x = row.isEven ? gap : gap - tw / 2; x < r.width; x += tw + gap) {
            _tile(canvas, faces[k % faces.length], Rect.fromLTWH(x, y, tw, th));
            k++;
          }
          k += 5;
        }

      case CardPattern.poke:
        // 戳戳樂：一格一格的紙洞，有幾格被戳破、露出小星星
        final s = max(w / 9, 9.0);
        var row = 0;
        for (var y = s * 0.15; y < r.height; y += s, row++) {
          var col = 0;
          for (var x = s * 0.15; x < r.width; x += s, col++) {
            final hole = Rect.fromLTWH(x + s * 0.12, y + s * 0.12, s * 0.76, s * 0.76);
            if ((row * 7 + col * 3) % 5 == 0) {
              paint.color = const Color(0xFF7A2E3A);
              canvas.drawOval(hole, paint);
              paint.color = const Color(0xFFFFE27A);
              canvas.drawPath(_star(hole.center, hole.width * 0.33, 5), paint);
            } else {
              paint.color = const Color(0xFFFFF6DA);
              canvas.drawOval(hole, paint);
              stroke
                ..color = const Color(0xFFE84A5F).withValues(alpha: 0.75)
                ..strokeWidth = max(w / 150, 0.8);
              canvas.drawOval(hole, stroke);
            }
          }
        }

      case CardPattern.waves:
        // 水波紋
        final step = max(w / 11, 7.0);
        stroke
          ..color = _lighter(base, 0.35).withValues(alpha: 0.8)
          ..strokeWidth = max(w / 75, 1.2);
        for (var y = step / 2; y < r.height; y += step) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x < r.width; x += step * 1.2) {
            path.cubicTo(x + step * 0.3, y - step * 0.4, x + step * 0.9, y + step * 0.4, x + step * 1.2, y);
          }
          canvas.drawPath(path, stroke);
        }

      case CardPattern.confetti:
        // 彩色紙花
        const colors = [Color(0xFFFFD873), Color(0xFF7FD3F7), Color(0xFFFFFFFF), Color(0xFF8BE38B), Color(0xFFFF9F43)];
        final count = (w * w / 700).clamp(12, 70).round();
        final u = max(w / 60, 1.6);
        for (var i = 0; i < count; i++) {
          paint.color = colors[i % colors.length].withValues(alpha: 0.85);
          final p = Offset(random.nextDouble() * r.width, random.nextDouble() * r.height);
          if (i % 3 == 0) {
            canvas.drawCircle(p, u * 0.9, paint);
          } else {
            canvas.drawRRect(
                RRect.fromRectAndRadius(Rect.fromLTWH(p.dx, p.dy, u * 2.6, u), Radius.circular(u / 2)), paint);
          }
        }

      case CardPattern.rings:
        // 套圈圈的靶紋：同心圓
        final step = max(w / 14, 5.0);
        var i = 0;
        for (var rad = r.height; rad > 0; rad -= step, i++) {
          paint.color = i.isEven ? light : dark;
          canvas.drawCircle(r.center, rad, paint);
        }

      case CardPattern.checker:
        // 格子紋加一圈金色內框
        final s = max(w / 10, 7.0);
        var row = 0;
        for (var y = 0.0; y < r.height; y += s, row++) {
          var col = 0;
          for (var x = 0.0; x < r.width; x += s, col++) {
            paint.color = (row + col).isEven ? light : dark;
            canvas.drawRect(Rect.fromLTWH(x, y, s, s), paint);
          }
        }
        stroke
          ..color = skin.edge.withValues(alpha: 0.9)
          ..strokeWidth = max(w / 110, 1);
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(w * 0.045), Radius.circular(w * 0.03)), stroke);

      case CardPattern.map:
        // 地圖格線加一條黃色虛線路線
        final step = max(w / 11, 7.0);
        stroke
          ..color = _lighter(base, 0.25).withValues(alpha: 0.6)
          ..strokeWidth = max(w / 220, 0.6);
        for (var x = 0.0; x < r.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, r.height), stroke);
        }
        for (var y = 0.0; y < r.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(r.width, y), stroke);
        }
        final route = Path()
          ..moveTo(r.width * 0.1, r.height * 0.9)
          ..cubicTo(r.width * 1.05, r.height * 0.85, -r.width * 0.05, r.height * 0.15, r.width * 0.9, r.height * 0.1);
        final dash = Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFFFD873)
          ..strokeWidth = max(w / 75, 1.2);
        for (final metric in route.computeMetrics()) {
          final seg = max(w / 28, 3.0);
          for (var d = 0.0; d < metric.length; d += seg * 1.8) {
            canvas.drawPath(metric.extractPath(d, d + seg), dash);
          }
        }

      case CardPattern.rays:
        // 金色放射光芒
        _rays(canvas, r, const Color(0xFFFFB547).withValues(alpha: 0.28), 24, paint);

      case CardPattern.chevron:
        // 人字紋
        final step = max(w / 10, 7.0);
        stroke
          ..color = light
          ..strokeWidth = max(w / 45, 1.5);
        for (var y = -step; y < r.height + step; y += step) {
          final path = Path()..moveTo(0, y);
          var up = true;
          for (var x = step * 0.8; x < r.width + step; x += step * 0.8, up = !up) {
            path.lineTo(x, y + (up ? -step * 0.5 : 0));
          }
          canvas.drawPath(path, stroke);
        }

      case CardPattern.pinstripe:
        // 金色細斜紋
        final step = max(w / 16, 5.0);
        stroke
          ..color = const Color(0xFFFFD43B).withValues(alpha: 0.35)
          ..strokeWidth = max(w / 110, 0.8);
        for (var x = -r.height; x < r.width; x += step) {
          canvas.drawLine(Offset(x, r.height), Offset(x + r.height, 0), stroke);
        }

      case CardPattern.sparkle:
        // 可愛風：柔和的大圓點和閃亮小星星
        final step = max(w / 5.5, 12.0);
        paint.color = Colors.white.withValues(alpha: 0.18);
        var row = 0;
        for (var y = step * 0.3; y < r.height; y += step * 0.85, row++) {
          for (var x = row.isEven ? step * 0.25 : step * 0.75; x < r.width; x += step) {
            canvas.drawCircle(Offset(x, y), step * 0.2, paint);
          }
        }
        paint.color = Colors.white.withValues(alpha: 0.9);
        const spots = [(0.18, 0.15, 1.0), (0.8, 0.1, 0.8), (0.12, 0.65, 0.7), (0.88, 0.75, 1.0), (0.5, 0.92, 0.7)];
        for (final (fx, fy, s) in spots) {
          canvas.drawPath(_star(Offset(r.width * fx, r.height * fy), max(w / 24, 3) * s, 4, inner: 0.3), paint);
        }
    }
  }

  void _rays(Canvas canvas, Rect r, Color color, int n, Paint paint) {
    paint.color = color;
    final c = r.center;
    final len = r.longestSide;
    for (var i = 0; i < n; i += 2) {
      final a1 = i / n * 2 * pi, a2 = (i + 1) / n * 2 * pi;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + len * cos(a1), c.dy + len * sin(a1))
          ..lineTo(c.dx + len * cos(a2), c.dy + len * sin(a2))
          ..close(),
        paint,
      );
    }
  }

  Path _star(Offset c, double radius, int points, {double inner = 0.43}) {
    final path = Path();
    for (var k = 0; k < points * 2; k++) {
      final rr = k.isEven ? radius : radius * inner;
      final a = k * pi / points - pi / 2;
      final p = Offset(c.dx + rr * cos(a), c.dy + rr * sin(a));
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static const _numbers = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

  void _text(Canvas canvas, String t, double size, Color color, Offset center) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static const _blue = Color(0xFF1F5FAF);
  static const _green = Color(0xFF1E8A4C);
  static const _red = Color(0xFFC62828);
  static const _ink = Color(0xFF1A1A1A);

  /// 傳統麻將的筒子排法：每個圓的位置（以牌面中心為原點、單位是牌面寬度）和顏色。
  static const _circleLayouts = <int, List<(double, double, Color)>>{
    2: [(0, -0.22, _green), (0, 0.22, _blue)],
    3: [(-0.24, -0.3, _blue), (0, 0, _red), (0.24, 0.3, _green)],
    4: [(-0.2, -0.2, _blue), (0.2, -0.2, _green), (-0.2, 0.2, _green), (0.2, 0.2, _blue)],
    5: [(-0.22, -0.27, _blue), (0.22, -0.27, _green), (0, 0, _red), (-0.22, 0.27, _green), (0.22, 0.27, _blue)],
    6: [(-0.2, -0.3, _green), (0.2, -0.3, _green), (-0.2, 0.05, _red), (0.2, 0.05, _red), (-0.2, 0.33, _red), (0.2, 0.33, _red)],
    7: [(-0.25, -0.38, _green), (0, -0.25, _green), (0.25, -0.12, _green), (-0.2, 0.12, _red), (0.2, 0.12, _red), (-0.2, 0.36, _red), (0.2, 0.36, _red)],
    8: [(-0.2, -0.36, _blue), (0.2, -0.36, _blue), (-0.2, -0.12, _blue), (0.2, -0.12, _blue), (-0.2, 0.12, _blue), (0.2, 0.12, _blue), (-0.2, 0.36, _blue), (0.2, 0.36, _blue)],
    9: [(-0.26, -0.3, _green), (0, -0.3, _green), (0.26, -0.3, _green), (-0.26, 0, _red), (0, 0, _red), (0.26, 0, _red), (-0.26, 0.3, _blue), (0, 0.3, _blue), (0.26, 0.3, _blue)],
  };

  /// 傳統麻將的條子排法：每根竹子的中心位置、顏色，以及是否斜放（八條）。
  static const _bambooLayouts = <int, List<(double, double, Color, double)>>{
    2: [(0, -0.22, _green, 0), (0, 0.22, _blue, 0)],
    3: [(0, -0.22, _green, 0), (-0.18, 0.22, _blue, 0), (0.18, 0.22, _blue, 0)],
    4: [(-0.18, -0.22, _green, 0), (0.18, -0.22, _blue, 0), (-0.18, 0.22, _blue, 0), (0.18, 0.22, _green, 0)],
    5: [(-0.24, -0.22, _green, 0), (0.24, -0.22, _blue, 0), (0, 0, _red, 0), (-0.24, 0.22, _blue, 0), (0.24, 0.22, _green, 0)],
    6: [(-0.26, -0.22, _green, 0), (0, -0.22, _green, 0), (0.26, -0.22, _green, 0), (-0.26, 0.22, _blue, 0), (0, 0.22, _blue, 0), (0.26, 0.22, _blue, 0)],
    7: [(0, -0.33, _red, 0), (-0.26, 0, _green, 0), (0, 0, _green, 0), (0.26, 0, _green, 0), (-0.26, 0.33, _blue, 0), (0, 0.33, _blue, 0), (0.26, 0.33, _blue, 0)],
    8: [(-0.3, -0.22, _green, 0), (-0.12, -0.22, _green, 0.5), (0.12, -0.22, _green, -0.5), (0.3, -0.22, _green, 0), (-0.3, 0.22, _blue, 0), (-0.12, 0.22, _blue, -0.5), (0.12, 0.22, _blue, 0.5), (0.3, 0.22, _blue, 0)],
    9: [(-0.26, -0.33, _green, 0), (0, -0.33, _red, 0), (0.26, -0.33, _blue, 0), (-0.26, 0, _green, 0), (0, 0, _red, 0), (0.26, 0, _blue, 0), (-0.26, 0.33, _green, 0), (0, 0.33, _red, 0), (0.26, 0.33, _blue, 0)],
  };

  /// 一個筒子：彩色圓、白色內環、中心點，加上四個小白點。
  void _circle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()..isAntiAlias = true;
    p.color = color;
    canvas.drawCircle(c, r, p);
    p
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.22;
    canvas.drawCircle(c, r * 0.62, p);
    p
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawCircle(c, r * 0.26, p);
    p.color = Colors.white;
    for (var k = 0; k < 4; k++) {
      final a = pi / 4 + k * pi / 2;
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * r * 0.62, r * 0.09, p);
    }
  }

  /// 一根竹子：圓角長條，中間有竹節。
  void _bamboo(Canvas canvas, Offset c, double w, double h, Color color, double tilt) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(w / 2));
    canvas.drawRRect(body, Paint()..color = color);
    // 竹節：中間細一點的深色節、上下兩端的亮色
    final node = Paint()..color = Color.lerp(color, Colors.black, 0.35)!;
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: h * 0.1), node);
    final hi = Paint()..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTWH(-w * 0.12, -h * 0.42, w * 0.24, h * 0.3), hi);
    canvas.drawRect(Rect.fromLTWH(-w * 0.12, h * 0.1, w * 0.24, h * 0.3), hi);
    canvas.restore();
  }

  /// 畫一張麻將牌：白色牌面、底下一條藍綠色的牌背厚度。
  /// face：「3w」三萬、「b5」五條、「c4」四筒、E/S/W/N 東南西北、Z 紅中、F 發、P 白板。
  void _tile(Canvas canvas, String face, Rect t) {
    final radius = Radius.circular(t.width * 0.14);
    // 牌背厚度（藍綠色），在牌面下方露出一截
    canvas.drawRRect(RRect.fromRectAndRadius(t.translate(0, t.height * 0.08), radius),
        Paint()..color = const Color(0xFF1B8FB3));
    final faceRect = t;
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, radius),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE9EEF0)],
        ).createShader(faceRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, t.width * 0.03)
        ..color = const Color(0xFFB8C4C9),
    );
    // 牌面內容的區域
    final f = faceRect.deflate(t.width * 0.1);
    final c = f.center;
    final fw = f.width;

    if (face.endsWith('w')) {
      final n = int.parse(face.substring(0, face.length - 1));
      _text(canvas, _numbers[n], fw * 0.62, _ink, c - Offset(0, f.height * 0.22));
      _text(canvas, '萬', fw * 0.66, _red, c + Offset(0, f.height * 0.2));
    } else if (face.startsWith('c')) {
      final n = int.parse(face.substring(1));
      if (n == 1) {
        _circle(canvas, c, fw * 0.46, _green);
        _circle(canvas, c, fw * 0.2, _red);
      } else {
        final rr = fw * (n >= 7 ? 0.15 : 0.18);
        for (final (dx, dy, color) in _circleLayouts[n]!) {
          _circle(canvas, c + Offset(dx * fw, dy * f.height), rr, color);
        }
      }
    } else if (face.startsWith('b')) {
      final n = int.parse(face.substring(1));
      final sw = fw * 0.16, sh = f.height * (n >= 7 ? 0.27 : 0.36);
      for (final (dx, dy, color, tilt) in _bambooLayouts[n]!) {
        _bamboo(canvas, c + Offset(dx * fw, dy * f.height), sw, sh, color, tilt);
      }
    } else if (face == 'Z') {
      _text(canvas, '中', fw * 0.95, _red, c);
    } else if (face == 'F') {
      _text(canvas, '發', fw * 0.95, _green, c);
    } else if (face == 'P') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(f.deflate(fw * 0.08), Radius.circular(fw * 0.08)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.8, fw * 0.1)
          ..color = _blue,
      );
    } else {
      const winds = {'E': '東', 'S': '南', 'W': '西', 'N': '北'};
      _text(canvas, winds[face] ?? '', fw * 0.95, _ink, c);
    }
  }

  @override
  bool shouldRepaint(CardPatternPainter oldDelegate) => oldDelegate.skin.id != skin.id;
}
