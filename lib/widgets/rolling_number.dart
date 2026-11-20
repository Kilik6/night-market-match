import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 像拉霸機一樣滾動的數字：數字變大時，每一位由個位數開始、依序往高位數滾到新的數字。
///
/// - 從個位數到最高有變的那一位，每一位都會轉（數字沒變的也轉一整圈停回原數字），看起來比較像拉霸；
///   新多出來的位數從 0 滾上來。
/// - 轉得快的時候上下加一點動態模糊，停下來時輕輕超過一點再彈回定位。
/// - 還在滾的時候又加分，從畫面上當下的位置接著滾，不會先跳格。
/// - 「減少動態效果」時直接顯示新數字。
class RollingNumber extends StatefulWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.style,
    this.digitDuration = const Duration(milliseconds: 750),
    this.stagger = const Duration(milliseconds: 90),
  });

  final int value;
  final TextStyle style;

  /// 每一位滾動的時間。
  final Duration digitDuration;

  /// 下一位（往高位）比前一位晚多久開始滾。
  final Duration stagger;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)..value = 1;

  /// 目前要停的數字。
  late int _to = widget.value;

  /// 每一位（索引 0 是個位數）這一次從哪個位置開始轉、總共轉幾格。位置用 0～10 的小數表示（9.5 是 9 往 0 轉到一半）。
  late List<double> _start = _digitsOf(widget.value);
  late List<double> _steps = List.filled(_start.length, 0);

  /// 一個數字的大小，換字型時才重新量。
  Size? _digitSize;
  TextStyle? _measuredStyle;

  /// 數字由個位數開始排的每一位。
  static List<double> _digitsOf(int value) => '$value'.split('').reversed.map((c) => double.parse(c)).toList();

  /// 停下來的曲線：前段快、後段慢慢減速，最後輕輕超過一點再彈回（[t] 是 0～1，回傳 0～1 再加一點彈跳）。
  static double _ease(double t) => 1 - pow(1 - t, 4).toDouble();
  static double _settle(double t) {
    final s = ((t - 0.72) / 0.28).clamp(0.0, 1.0);
    return 0.22 * sin(pi * s) * (1 - s);
  }

  /// 曲線的斜率，用來算轉得多快（動態模糊的強度）。
  static double _speed(double t) => 4 * pow(1 - t, 3).toDouble();

  /// 第 [place] 位這一次動畫進行到哪裡（0～1）。
  double _t(int place) {
    if (_controller.value >= 1) return 1;
    final total = _controller.duration!.inMicroseconds;
    final start = widget.stagger.inMicroseconds * place / total;
    final end = (widget.stagger.inMicroseconds * place + widget.digitDuration.inMicroseconds) / total;
    return ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  /// 第 [place] 位目前在畫面上的位置。
  double _position(int place) {
    if (place >= _start.length) return 0;
    final t = _t(place);
    final steps = _steps[place];
    return _start[place] + steps * _ease(t) + (steps > 0.5 ? _settle(t) : 0);
  }

  @override
  void didUpdateWidget(RollingNumber old) {
    super.didUpdateWidget(old);
    if (widget.value == _to) return;
    final target = _digitsOf(widget.value);
    if (MediaQuery.of(context).disableAnimations || widget.value < _to) {
      _to = widget.value;
      _start = target;
      _steps = List.filled(target.length, 0);
      _controller.value = 1;
      return;
    }
    // 從畫面上當下的位置接著滾，不會先跳到上一次的目標
    final current = [for (var p = 0; p < target.length; p++) _position(p) % 10];
    final previous = _digitsOf(_to);
    var highestChanged = -1;
    for (var p = 0; p < target.length; p++) {
      if (p >= previous.length || previous[p] != target[p]) highestChanged = p;
    }
    _to = widget.value;
    _start = current;
    _steps = [
      for (var p = 0; p < target.length; p++)
        // 要轉的位數多轉一圈再停到新數字（數字沒變的就剛好轉一圈）
        ((target[p] - current[p]) % 10 + 10) % 10 + (p <= highestChanged ? 10 : 0),
    ];
    _controller.duration = widget.digitDuration + widget.stagger * (target.length - 1);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Size _measure(TextStyle style) {
    if (_digitSize == null || _measuredStyle != style) {
      final painter = TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr)..layout();
      _digitSize = Size(painter.width, painter.height);
      _measuredStyle = style;
      painter.dispose();
    }
    return _digitSize!;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final size = _measure(style);
    final length = '$_to'.length;
    return Semantics(
      label: '$_to',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 由最高位排到個位數；個位數最先滾，往左每一位晚 [stagger]
            for (var place = length - 1; place >= 0; place--) _digit(place, size, style),
          ],
        ),
      ),
    );
  }

  Widget _digit(int place, Size size, TextStyle style) {
    final position = _position(place);
    final current = position.floor() % 10;
    final next = (current + 1) % 10;
    final fraction = position - position.floor();
    // 每秒轉幾格，越快越模糊
    final t = _t(place);
    final perSecond =
        _steps.length > place && t < 1 ? _steps[place] * _speed(t) / (widget.digitDuration.inMicroseconds / 1e6) : 0.0;
    final blur = (perSecond / 30).clamp(0.0, 1.0) * size.height * 0.06;
    Widget glyph(int d) => Text('$d', style: style, textHeightBehavior: const TextHeightBehavior());
    Widget reel = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(left: 0, top: -fraction * size.height, child: glyph(current)),
        if (fraction > 0.001) Positioned(left: 0, top: (1 - fraction) * size.height, child: glyph(next)),
      ],
    );
    if (blur > 0.3) {
      reel = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 0, sigmaY: blur), child: reel);
    }
    return SizedBox(
      width: size.width,
      height: size.height,
      // 左右不裁切，發光效果才不會被切成一格一格
      child: ClipRect(clipper: _VerticalClipper(), child: reel),
    );
  }
}

/// 只裁上下、左右放寬，讓發光的陰影不會被每一位的邊界切掉。
class _VerticalClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(-size.width, 0, size.width * 2, size.height);

  @override
  bool shouldReclip(_VerticalClipper oldClipper) => false;
}
