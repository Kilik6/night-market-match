import 'package:flutter/material.dart';

import '../theme.dart';
import 'coin.dart';

/// 所有畫面共用的夜空背景：深色底加上方暖色燈光暈染。
class NightScaffold extends StatelessWidget {
  const NightScaffold({super.key, required this.child, this.title, this.actions, this.glow = defaultGlow});

  /// 上方暈染的顏色（每日挑戰用月光的藍色）。
  final Color glow;
  static const defaultGlow = Color(0xFFFFB547);

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
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.0,
            colors: [glow.withValues(alpha: 0.16), glow.withValues(alpha: 0)],
          ),
        ),
        child: SafeArea(child: child),
      ),
    );
  }
}

/// 立體按鈕：底下露出一條較深的厚邊，按下時整塊往下陷，放開再彈回來。
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.face,
    required this.edge,
    required this.onTap,
    required this.child,
    this.radius = 16,
    this.depth = 4,
    this.padding = EdgeInsets.zero,
  });

  final Color face;
  final Color edge;
  final VoidCallback? onTap;
  final Widget child;
  final double radius;

  /// 厚邊的高度，也是按下去會陷的距離。
  final double depth;
  final EdgeInsetsGeometry padding;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final d = widget.depth;
    final radius = BorderRadius.circular(widget.radius);
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _press(true) : null,
        onTapUp: enabled ? (_) => _press(false) : null,
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        // passthrough：放在拉伸的 Row 裡時，按鈕面跟著撐滿整格高度
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // 厚邊：從 depth 開始往下畫，按鈕面浮起來時只露出底下那一條
            Positioned.fill(
              top: d,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.edge,
                  borderRadius: radius,
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              margin: EdgeInsets.only(top: _down ? d : 0, bottom: _down ? 0 : d),
              padding: widget.padding,
              decoration: BoxDecoration(color: widget.face, borderRadius: radius),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

/// 首頁的大按鈕。primary 是金黃色的立體按鈕，其他是深藍紫色。
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
    final fg = primary ? ChunkyColors.goldInk : Colors.white;
    return ChunkyButton(
      face: primary ? ChunkyColors.goldFace : ChunkyColors.tileFace,
      edge: primary ? ChunkyColors.goldEdge : ChunkyColors.tileEdge,
      depth: 5,
      radius: 18,
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 26, color: primary ? fg : ChunkyColors.tileIcon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.75))),
              ],
            ),
          ),
          Icon(Icons.play_arrow_rounded, size: 28, color: fg.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

/// 金幣數量標籤。
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coins, this.onTopUp, this.topUpLabel = '儲值金幣'});
  final int coins;

  /// 有給的話，顯示成金色膠囊加上發光的「＋」，點下去去儲值（首頁用）。
  final VoidCallback? onTopUp;

  /// 「＋」給螢幕報讀用的說明。
  final String topUpLabel;

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
      label: topUpLabel,
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
