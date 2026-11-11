import 'package:flutter/material.dart';

import '../theme.dart';

/// 結算視窗的選項。
enum ResultChoice { primary, watchAd, leave }

/// 道具列的一格：圖示、名稱、數量（或「廣告」標籤）。
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.emoji, required this.label, required this.badge, required this.onTap});

  final String emoji;
  final String label;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: const TextStyle(color: NightColors.paper, fontSize: 11)),
                ),
                Text(badge, style: const TextStyle(color: NightColors.glow, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 有「廣告」標籤的按鈕，讓玩家一眼看出按了會播廣告。
class AdButton extends StatelessWidget {
  const AdButton({super.key, required this.label, required this.onPressed, this.onPaper = false});

  final String label;
  final VoidCallback? onPressed;

  /// 放在米色結果視窗上時改用深一點的顏色。
  final bool onPaper;

  @override
  Widget build(BuildContext context) {
    final color = onPaper ? const Color(0xFFA2580A) : NightColors.glow;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: 0.4),
        side: BorderSide(color: onPressed == null ? color.withValues(alpha: 0.3) : color, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: onPressed == null ? color.withValues(alpha: 0.4) : color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '廣告',
              style: TextStyle(fontSize: 11, color: onPaper ? NightColors.paper : NightColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// 過關／時間到的結果視窗，菜單紙風格。關閉時回傳玩家的選擇。
class ResultDialog extends StatelessWidget {
  const ResultDialog({
    super.key,
    required this.title,
    required this.lines,
    required this.primaryLabel,
    required this.leaveLabel,
    this.adLabel,
    this.stars,
  });

  final String title;
  final List<String> lines;
  final String primaryLabel;
  final String leaveLabel;
  final String? adLabel;
  final int? stars;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NightColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NightColors.ink, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (stars != null) ...[
              const SizedBox(height: 8),
              Text(
                '${'★' * stars!}${'☆' * (3 - stars!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD9A21B), fontSize: 30, letterSpacing: 6),
              ),
            ],
            const SizedBox(height: 10),
            for (final line in lines)
              Text(line, textAlign: TextAlign.center, style: const TextStyle(color: NightColors.ink, height: 1.6)),
            const SizedBox(height: 16),
            if (adLabel != null) ...[
              AdButton(
                key: const ValueKey('dialog_ad'),
                label: adLabel!,
                onPaper: true,
                onPressed: () => Navigator.of(context).pop(ResultChoice.watchAd),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ResultChoice.primary),
              style: FilledButton.styleFrom(
                backgroundColor: NightColors.glow,
                foregroundColor: NightColors.ink,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('dialog_leave'),
              onPressed: () => Navigator.of(context).pop(ResultChoice.leave),
              child: Text(leaveLabel, style: const TextStyle(color: NightColors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 開局翻開全部牌讓玩家記位置的秒數。
const previewMemorizeSeconds = 5;

/// 開局時蓋在牌桌正中央的提示框：「記住所有卡牌！」和倒數數字。
/// 底下的牌是翻開的，所以框做得小而透明，盡量不擋到要記的牌。
class PreviewHint extends StatelessWidget {
  const PreviewHint({super.key, required this.secondsLeft});

  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Container(
      key: const ValueKey('preview_hint'),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: NightColors.paper.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NightColors.glow.withValues(alpha: 0.7), width: 2),
        boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.2), blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '記住所有卡牌！',
            style: TextStyle(color: NightColors.ink, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          // 每換一個數字就重建，從大縮回正常大小
          TweenAnimationBuilder<double>(
            key: ValueKey(secondsLeft),
            tween: Tween(begin: reduceMotion ? 1 : 1.6, end: 1),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Text(
              '$secondsLeft',
              key: const ValueKey('preview_seconds'),
              style: const TextStyle(
                color: Color(0xFFC0392B),
                fontSize: 40,
                height: 1.1,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
