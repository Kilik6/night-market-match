import 'package:flutter/material.dart';

import '../theme.dart';
import 'coin.dart';

/// 所有畫面共用的夜空背景：深色底加上方暖色燈光暈染。
class NightScaffold extends StatelessWidget {
  const NightScaffold({super.key, required this.child, this.title, this.actions});

  final Widget child;

  /// 有標題時顯示頂端列（含返回鍵）。
  final String? title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NightColors.night,
      appBar: title == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: NightColors.paper,
              title: Text(title!, style: const TextStyle(fontWeight: FontWeight.w700)),
              actions: actions,
            ),
      extendBodyBehindAppBar: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.0,
            colors: [Color(0x29FFB547), Color(0x00FFB547)],
          ),
        ),
        child: SafeArea(child: child),
      ),
    );
  }
}

/// 首頁的大按鈕。primary 是亮黃底，其他是外框。
class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.subtitle,
    this.primary = false,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? NightColors.ink : NightColors.paper;
    final child = Row(
      children: [
        Icon(icon, size: 26, color: primary ? NightColors.ink : NightColors.glow),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 13, color: primary ? NightColors.ink.withValues(alpha: 0.7) : NightColors.mist),
                ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: fg.withValues(alpha: 0.6)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: NightColors.glow,
              padding: padding,
              shape: shape,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: NightColors.stall,
              side: BorderSide(color: NightColors.paper.withValues(alpha: 0.15)),
              padding: padding,
              shape: shape,
            ),
            child: child,
          );
  }
}

/// 金幣數量標籤。
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coins, this.onTopUp});
  final int coins;

  /// 有給的話，顯示成金色膠囊加上發光的「＋」，點下去去儲值（首頁用）。
  final VoidCallback? onTopUp;

  @override
  Widget build(BuildContext context) {
    final text = CoinText(
      '🪙 $coins',
      key: const ValueKey('coins'),
      style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w700),
    );
    final onTopUp = this.onTopUp;
    if (onTopUp == null) return text;
    return Semantics(
      button: true,
      label: '儲值金幣',
      child: Material(
        color: NightColors.stall,
        shape: StadiumBorder(side: BorderSide(color: NightColors.glow.withValues(alpha: 0.75), width: 1.5)),
        child: InkWell(
          key: const ValueKey('top_up'),
          customBorder: const StadiumBorder(),
          onTap: onTopUp,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [text, const SizedBox(width: 8), const _GlowingPlus()],
            ),
          ),
        ),
      ),
    );
  }
}

/// 儲值膠囊尾端的「＋」：亮黃色圓形，光暈慢慢一明一暗。
class _GlowingPlus extends StatefulWidget {
  const _GlowingPlus();

  @override
  State<_GlowingPlus> createState() => _GlowingPlusState();
}

class _GlowingPlusState extends State<_GlowingPlus> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 0.5;
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
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
      builder: (context, child) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: NightColors.glow,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: NightColors.glow.withValues(alpha: 0.35 + 0.45 * _controller.value),
              blurRadius: 6 + 10 * _controller.value,
            ),
          ],
        ),
        child: child,
      ),
      child: const Icon(Icons.add_rounded, size: 20, color: NightColors.ink),
    );
  }
}
