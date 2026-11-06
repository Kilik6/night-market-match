import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 當 [trigger] 變大時，讓 child 放大再彈回，可以同時發光。
/// 用在配對成功的卡片、分數和連擊數字。
class PulseOnIncrease extends StatefulWidget {
  const PulseOnIncrease({
    super.key,
    required this.trigger,
    required this.child,
    this.scale = 1.15,
    this.duration = const Duration(milliseconds: 300),
    this.delay = 0,
    this.glow,
    this.borderRadius = 10,
  });

  final num trigger;
  final Widget child;

  /// 最大放大倍率。
  final double scale;
  final Duration duration;

  /// 動畫開始前等待的比例（0～1，佔 [duration]），例如等翻牌動畫跑完。
  final double delay;

  /// 發光顏色，null 表示不發光。
  final Color? glow;
  final double borderRadius;

  @override
  State<PulseOnIncrease> createState() => _PulseOnIncreaseState();
}

class _PulseOnIncreaseState extends State<PulseOnIncrease> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);

  @override
  void didUpdateWidget(PulseOnIncrease old) {
    super.didUpdateWidget(old);
    if (widget.trigger > old.trigger && !MediaQuery.of(context).disableAnimations) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // 跳過 delay 的部分，之後走半個正弦波：0 → 1 → 0
        final v = _controller.value;
        final t = v <= widget.delay ? 0.0 : (v - widget.delay) / (1 - widget.delay);
        final wave = _controller.isAnimating ? sin(pi * t) : 0.0;
        return Transform.scale(
          scale: 1 + (widget.scale - 1) * wave,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: widget.glow == null || wave == 0
                  ? null
                  : [BoxShadow(color: widget.glow!.withValues(alpha: 0.8 * wave), blurRadius: 22, spreadRadius: 3)],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// 配對成功時的特效：向外噴的粒子、擴散的光環，以及往上飄的分數。
class MatchBurst extends StatefulWidget {
  const MatchBurst({
    super.key,
    required this.intensity,
    required this.seed,
    required this.onDone,
    this.label,
    this.sublabel,
  });

  /// 特效大小。1 是一般配對，連擊越高越大。
  final int intensity;
  final int seed;
  final VoidCallback onDone;

  /// 飄字，例如「+300」。
  final String? label;

  /// 第二行飄字，例如「3 連擊」。
  final String? sublabel;

  /// 特效的繪製範圍（邊長）。
  static const size = 220.0;

  /// 特效總長度。
  static const duration = Duration(milliseconds: 1000);

  @override
  State<MatchBurst> createState() => _MatchBurstState();
}

class _MatchBurstState extends State<MatchBurst> with SingleTickerProviderStateMixin {
  /// 前 25% 的時間等翻牌動畫跑完。
  static const _delay = 0.25;

  late final AnimationController _controller = AnimationController(vsync: this, duration: MatchBurst.duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  late final List<_Particle> _particles = _makeParticles();

  List<_Particle> _makeParticles() {
    final random = Random(widget.seed);
    final count = min(10 + widget.intensity * 3, 28);
    const colors = [NightColors.glow, NightColors.lantern, NightColors.jade, NightColors.paper];
    return List.generate(count, (i) {
      return _Particle(
        angle: i / count * 2 * pi + random.nextDouble() * 0.5,
        distance: 44 + random.nextDouble() * (34 + widget.intensity * 6),
        size: 2.5 + random.nextDouble() * 3.5,
        color: colors[i % colors.length],
        isStar: i % 3 == 0,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        final t = v <= _delay ? 0.0 : (v - _delay) / (1 - _delay);
        return SizedBox.square(
          dimension: MatchBurst.size,
          child: v <= _delay
              ? null
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(MatchBurst.size),
                      painter: _BurstPainter(_particles, t),
                    ),
                    if (widget.label != null) _floatingText(t),
                  ],
                ),
        );
      },
    );
  }

  Widget _floatingText(double t) {
    final rise = Curves.easeOut.transform(t) * 58;
    final opacity = t < 0.65 ? 1.0 : (1 - (t - 0.65) / 0.35).clamp(0.0, 1.0);
    final pop = Curves.elasticOut.transform((t / 0.4).clamp(0.0, 1.0));
    final fontSize = 24.0 + min(widget.intensity, 7) * 2;
    return Transform.translate(
      offset: Offset(0, -rise),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: 0.6 + 0.4 * pop,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label!,
                style: TextStyle(
                  color: NightColors.glow,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
              ),
              if (widget.sublabel != null)
                Text(
                  widget.sublabel!,
                  style: const TextStyle(
                    color: NightColors.paper,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.isStar,
  });

  final double angle;
  final double distance;
  final double size;
  final Color color;
  final bool isStar;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final fade = (1 - t * t).clamp(0.0, 1.0);

    // 擴散的光環
    canvas.drawCircle(
      center,
      20 + 70 * Curves.easeOut.transform(t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - t)
        ..color = NightColors.glow.withValues(alpha: 0.7 * fade),
    );

    // 向外噴的粒子，飛出去時速度變慢，並往下掉一點
    final travel = Curves.easeOutCubic.transform(t);
    for (final p in particles) {
      final offset = center +
          Offset(cos(p.angle), sin(p.angle)) * (p.distance * travel) +
          Offset(0, 14 * t * t);
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      final radius = p.size * (1 - t * 0.5);
      if (p.isStar) {
        canvas.drawPath(_star(offset, radius * 1.8), paint);
      } else {
        canvas.drawCircle(offset, radius, paint);
      }
    }
  }

  /// 四角星。
  Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.35;
      final a = i * pi / 4;
      final point = c + Offset(cos(a), sin(a)) * radius;
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
