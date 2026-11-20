import 'dart:math';

import 'package:flutter/material.dart';

import '../game/wheel.dart';
import '../theme.dart';
import 'coin.dart';

/// 夜市轉盤：八格獎品，上方有指針。呼叫 [PrizeWheelState.spinTo] 轉到指定的格子，停下來時呼叫 [onStopped]。
class PrizeWheel extends StatefulWidget {
  const PrizeWheel({super.key, required this.size, required this.onStopped});

  final double size;
  final ValueChanged<int> onStopped;

  /// 轉多久。
  static const spinDuration = Duration(milliseconds: 3200);

  @override
  State<PrizeWheel> createState() => PrizeWheelState();
}

class PrizeWheelState extends State<PrizeWheel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: PrizeWheel.spinDuration);

  /// 目前停的角度（弧度）和這一次要轉到的角度。
  double _from = 0;
  double _to = 0;
  int _target = 0;
  final _random = Random();

  bool get spinning => _controller.isAnimating;

  static double get _slice => 2 * pi / wheelPrizes.length;

  /// 轉到第 [index] 格：先轉好幾圈再慢慢停下，停在格子裡的隨機位置（不會剛好停在線上）。
  void spinTo(int index) {
    if (spinning) return;
    _target = index;
    _from = _to % (2 * pi);
    final jitter = (_random.nextDouble() - 0.5) * _slice * 0.6;
    // 第 index 格的中心在 index × slice（從正上方順時針）；轉盤轉 r 之後它在 index × slice + r，要轉到正上方（0）
    final land = (2 * pi - index * _slice + jitter) % (2 * pi);
    _to = _from + 6 * 2 * pi + ((land - _from) % (2 * pi));
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      setState(() {});
      widget.onStopped(index);
      return;
    }
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) widget.onStopped(_target);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size + 14,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 14,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = Curves.easeOutQuart.transform(_controller.value);
                return Transform.rotate(angle: _from + (_to - _from) * t, child: child);
              },
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _WheelPainter())),
                    // 每一格的獎品，朝外排
                    for (var i = 0; i < wheelPrizes.length; i++)
                      Positioned.fill(
                        child: Transform.rotate(
                          angle: i * _slice,
                          child: Align(
                            alignment: const Alignment(0, -0.62),
                            child: _label(wheelPrizes[i], size),
                          ),
                        ),
                      ),
                    Center(
                      child: Container(
                        width: size * 0.16,
                        height: size * 0.16,
                        decoration: BoxDecoration(
                          color: NightColors.night,
                          shape: BoxShape.circle,
                          border: Border.all(color: NightColors.glow, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 指針：正上方往下指的三角形
          CustomPaint(size: const Size(26, 26), painter: _PointerPainter()),
        ],
      ),
    );
  }

  Widget _label(WheelPrize prize, double size) {
    final style = TextStyle(
      color: NightColors.ink,
      fontSize: size * 0.07,
      fontWeight: FontWeight.w800,
    );
    if (prize.coins > 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoinIcon(size: size * 0.08),
          Text('${prize.coins}', style: style),
        ],
      );
    }
    return Text(prize.label, style: TextStyle(fontSize: size * 0.11));
  }
}

class _WheelPainter extends CustomPainter {
  static const _colors = [Color(0xFFFFD873), Color(0xFFF2735F), Color(0xFFFBF1DC), Color(0xFFFFB547)];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final slice = 2 * pi / wheelPrizes.length;
    for (var i = 0; i < wheelPrizes.length; i++) {
      // 第 i 格以正上方順時針 i × slice 為中心
      final start = -pi / 2 + i * slice - slice / 2;
      canvas.drawArc(rect, start, slice, true, Paint()..color = _colors[i % _colors.length]);
    }
    final line = Paint()
      ..color = NightColors.lantern.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    for (var i = 0; i < wheelPrizes.length; i++) {
      final a = -pi / 2 + i * slice - slice / 2;
      canvas.drawLine(center, center + Offset(cos(a), sin(a)) * radius, line);
    }
    canvas.drawCircle(
      center,
      radius - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = NightColors.lantern,
    );
    // 外圈的小燈泡
    for (var i = 0; i < 16; i++) {
      final a = i * pi / 8;
      canvas.drawCircle(center + Offset(cos(a), sin(a)) * (radius - 3), 3, Paint()..color = NightColors.glow);
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => false;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = NightColors.paper);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = NightColors.lantern,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => false;
}
