import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/night_market_data.dart';
import '../theme.dart';
import '../widgets/food_icon.dart';

/// 開場動畫：夜市開張。遮雨棚降下、燈籠一盞盞亮起、招牌跳出來、小吃一攤攤擺上。
///
/// 動畫和載入（音效、小吃圖片）同時進行，兩邊都好了才淡入 [next]。
/// 載入比動畫快就等動畫播完；載入比較慢，畫面停在「攤位準備中」繼續等，
/// 但最多等 [maxWait]，避免哪個資源卡住讓玩家進不了遊戲。
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.next,
    this.loading,
    this.images,
    this.minDuration = const Duration(milliseconds: 2400),
    this.maxWait = const Duration(seconds: 6),
  });

  /// 載入完成後要進入的畫面。
  final WidgetBuilder next;

  /// 要等的載入工作（例如音效初始化）。
  final Future<void>? loading;

  /// 要先載入記憶體的圖片，預設是所有小吃圖片。測試時可以給空的。
  final List<String>? images;

  /// 開場動畫至少播多久。
  final Duration minDuration;

  /// 載入最多等多久。
  final Duration maxWait;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  /// 開場的主時間軸，只播一次。
  late final AnimationController _intro = AnimationController(vsync: this, duration: widget.minDuration);

  /// 燈籠搖晃、燈光閃爍、載入中的點點，持續循環。
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  bool _started = false;
  bool _loaded = false;
  bool _leaving = false;

  /// 招牌下面展示的六樣小吃。
  static final _showcase = foods.take(6).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _intro.value = 1;
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
    if (_started) return;
    _started = true;
    if (!reduceMotion) _intro.forward();
    _load();
  }

  Future<void> _load() async {
    final images = widget.images ?? [for (final f in foods) if (f.image != null) f.image!];
    final work = Future.wait<void>([
      if (widget.loading != null) widget.loading!,
      for (final path in images) precacheImage(AssetImage(path), context),
    ]);
    try {
      await Future.wait<void>([
        work.timeout(widget.maxWait, onTimeout: () => <void>[]),
        Future<void>.delayed(widget.minDuration),
      ]);
    } catch (e) {
      // 某個資源載入失敗也照樣進遊戲，進去後缺的音效或圖片會自己略過。
      debugPrint('開場載入失敗：$e');
    }
    if (!mounted) return;
    setState(() => _loaded = true);
    // 讓「開市囉！」停留約一秒再換頁
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (mounted) _goNext();
  }

  void _goNext() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, _, __) => widget.next(context),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    ));
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// 主時間軸中 [begin]～[end] 這一段的進度，套上 [curve]。
  double _phase(double begin, double end, [Curve curve = Curves.easeOutCubic]) {
    final t = ((_intro.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('splash'),
      backgroundColor: NightColors.night,
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _loop]),
        builder: (context, _) {
          final awning = _phase(0.0, 0.22, Curves.easeOutBack);
          final title = _phase(0.38, 0.62, Curves.elasticOut);
          final titleFade = _phase(0.38, 0.48);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.6),
                radius: 1.1,
                colors: [
                  // 燈籠亮起來後，夜空也跟著暖起來
                  Color.lerp(const Color(0x00FFB547), const Color(0x38FFB547), _phase(0.15, 0.6))!,
                  const Color(0x00FFB547),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // 遮雨棚從上面降下來
                  ClipRect(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: awning.clamp(0.0, 1.0),
                      child: const SizedBox(
                        height: 46,
                        width: double.infinity,
                        child: CustomPaint(painter: _AwningPainter()),
                      ),
                    ),
                  ),
                  _LanternString(
                    count: 7,
                    // 第 i 盞在 0.18 + i*0.05 開始亮
                    lightOf: (i) => _phase(0.18 + i * 0.05, 0.28 + i * 0.05),
                    sway: _loop.value,
                  ),
                  const Spacer(flex: 3),
                  Opacity(
                    opacity: titleFade,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * title,
                      child: _Signboard(flicker: _loop.value),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // 窄螢幕放不下六樣小吃時整排縮小
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _FoodRow(
                        foods: _showcase,
                        progressOf: (i) => _phase(0.55 + i * 0.06, 0.72 + i * 0.06, Curves.easeOutBack),
                        bob: _loop.value,
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                  _LoadingLabel(loaded: _loaded, tick: _loop.value, visible: _phase(0.7, 0.85)),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 紅白條紋的攤位遮雨棚，下緣是一個個半圓。
class _AwningPainter extends CustomPainter {
  const _AwningPainter();

  static const _stripes = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / _stripes;
    final r = w / 2;
    final body = size.height - r;
    for (var i = 0; i < _stripes; i++) {
      final paint = Paint()..color = i.isEven ? NightColors.lantern : NightColors.paper;
      final left = i * w;
      final path = Path()
        ..addRect(Rect.fromLTWH(left, 0, w, body))
        ..addArc(Rect.fromCircle(center: Offset(left + r, body), radius: r), 0, pi);
      canvas.drawPath(path, paint);
    }
    // 下緣一點陰影，讓遮雨棚有厚度
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 4),
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_AwningPainter oldDelegate) => false;
}

/// 掛在遮雨棚下的一串燈籠，依序點亮。
class _LanternString extends StatelessWidget {
  const _LanternString({required this.count, required this.lightOf, required this.sway});

  final int count;

  /// 第 i 盞燈籠亮的程度，0 是暗、1 是全亮。
  final double Function(int i) lightOf;

  /// 循環動畫的進度，用來搖晃燈籠。
  final double sway;

  static const _unlit = Color(0xFF4A2430);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < count; i++)
            Transform.rotate(
              angle: sin(sway * 2 * pi + i * 1.3) * 5 * pi / 180,
              alignment: Alignment.topCenter,
              child: _lantern(lightOf(i), i.isEven ? 18.0 : 30.0),
            ),
        ],
      ),
    );
  }

  Widget _lantern(double light, double rope) {
    final color = Color.lerp(_unlit, NightColors.lantern, light)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1.5, height: rope, color: NightColors.paper.withValues(alpha: 0.3)),
        Container(width: 14, height: 4, color: const Color(0xFF3A2A1E)),
        Container(
          width: 30,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: NightColors.lantern.withValues(alpha: 0.75 * light),
                blurRadius: 22 * light,
                spreadRadius: 2 * light,
              ),
            ],
          ),
          child: Center(
            // 燈籠中間的燈芯
            child: Container(
              width: 10,
              height: 18,
              decoration: BoxDecoration(
                color: NightColors.glow.withValues(alpha: 0.85 * light),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
        Container(width: 14, height: 4, color: const Color(0xFF3A2A1E)),
        Container(width: 3, height: 10, color: NightColors.glow.withValues(alpha: 0.4 + 0.5 * light)),
      ],
    );
  }
}

/// 發光的「夜市翻牌」招牌。
class _Signboard extends StatelessWidget {
  const _Signboard({required this.flicker});

  final double flicker;

  @override
  Widget build(BuildContext context) {
    // 霓虹燈輕微閃爍
    final glow = 0.75 + 0.25 * sin(flicker * 2 * pi * 2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NightColors.glow.withValues(alpha: 0.8 * glow), width: 2),
        boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.35 * glow), blurRadius: 28)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '夜市翻牌',
            style: TextStyle(
              color: NightColors.paper,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              shadows: [
                Shadow(color: NightColors.glow.withValues(alpha: glow), blurRadius: 18),
                Shadow(color: NightColors.lantern.withValues(alpha: 0.6 * glow), blurRadius: 36),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '翻開每一攤的好味道',
            style: TextStyle(color: NightColors.mist, fontSize: 14, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

/// 一排小吃依序從下面彈上來，之後輕輕上下浮動。
class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.foods, required this.progressOf, required this.bob});

  final List<Food> foods;
  final double Function(int i) progressOf;
  final double bob;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < foods.length; i++)
          Builder(builder: (context) {
            final p = progressOf(i);
            final float = sin(bob * 2 * pi + i * 0.9) * 3 * p;
            return Opacity(
              opacity: p.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - p) * 40 + float),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FoodIcon(food: foods[i], size: 26),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// 最下面的載入狀態：「攤位準備中…」，好了變成「開市囉！」。
class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.loaded, required this.tick, required this.visible});

  final bool loaded;
  final double tick;
  final double visible;

  @override
  Widget build(BuildContext context) {
    final dots = '．' * (1 + (tick * 6).floor() % 3);
    return Opacity(
      opacity: loaded ? 1 : visible,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          loaded ? '開市囉！' : '攤位準備中${dots.padRight(3, '　')}',
          key: ValueKey(loaded ? 'open' : 'loading'),
          style: TextStyle(
            color: loaded ? NightColors.glow : NightColors.mist,
            fontSize: loaded ? 20 : 15,
            fontWeight: loaded ? FontWeight.w800 : FontWeight.w500,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
