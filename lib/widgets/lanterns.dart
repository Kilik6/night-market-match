import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 畫面頂端一排會輕輕搖晃的紅燈籠。
class Lanterns extends StatefulWidget {
  const Lanterns({super.key, this.count = 6});
  final int count;

  @override
  State<Lanterns> createState() => _LanternsState();
}

class _LanternsState extends State<Lanterns> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Stack(
        children: [
          // 掛燈籠的線
          Positioned(
            left: 0,
            right: 0,
            top: 4,
            child: Container(height: 1, color: NightColors.paper.withValues(alpha: 0.25)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.count; i++)
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final phase = _controller.value * 2 * pi + i * 1.7;
                    return Transform.rotate(
                      angle: sin(phase) * 4 * pi / 180,
                      alignment: Alignment.topCenter,
                      child: child,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 22,
                      height: 28,
                      decoration: BoxDecoration(
                        color: NightColors.lantern,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(color: NightColors.lantern.withValues(alpha: 0.7), blurRadius: 14),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
