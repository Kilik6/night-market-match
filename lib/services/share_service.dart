import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// 分享圖上的成績。
class ScoreCard {
  const ScoreCard({
    required this.title,
    required this.score,
    required this.matches,
    required this.bestCombo,
    this.allClears = 0,
    this.isRecord = false,
  });

  /// 「夜市大胃王」或「每日挑戰」。
  final String title;
  final int score;
  final int matches;
  final int bestCombo;
  final int allClears;
  final bool isRecord;

  /// 跟圖片一起分享的文字。
  String get message => '我在《夜市翻牌》的$title吃了 $score 分！你能吃多少？';
}

/// 分享成績。畫面只依賴這個介面，測試時換成假的。
abstract class ScoreShareService {
  /// 產生分享圖並叫出系統的分享選單。[origin] 是分享按鈕的位置（iPad 的分享選單要從這裡彈出）。
  Future<void> share(ScoreCard card, {Rect? origin});
}

/// 畫一張分享圖存到暫存資料夾，再用系統的分享選單分享。
class ImageScoreShareService implements ScoreShareService {
  const ImageScoreShareService();

  @override
  Future<void> share(ScoreCard card, {Rect? origin}) async {
    final png = await renderScoreCard(card);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/night_market_score.png');
    await file.writeAsBytes(png);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: card.message,
      sharePositionOrigin: origin,
    ));
  }
}

/// 分享圖的大小（直式 4:5，IG 貼文和限時動態都好用）。
const scoreCardSize = Size(1080, 1350);

/// 畫分享圖，回傳 PNG。
Future<List<int>> renderScoreCard(ScoreCard card) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = scoreCardSize;
  final rect = Offset.zero & size;

  // 夜空背景，上方一圈暖光
  canvas.drawRect(rect, Paint()..color = NightColors.night);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, 0),
        size.height * 0.75,
        [NightColors.glow.withValues(alpha: 0.28), NightColors.glow.withValues(alpha: 0)],
      ),
  );

  // 上方一排燈籠
  final wire = Paint()
    ..color = NightColors.mist.withValues(alpha: 0.4)
    ..strokeWidth = 3;
  canvas.drawLine(const Offset(0, 90), Offset(size.width, 90), wire);
  for (var i = 0; i < 7; i++) {
    final x = 90.0 + i * (size.width - 180) / 6;
    final lantern = Rect.fromCenter(center: Offset(x, 150), width: 70, height: 90);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lantern, const Radius.circular(30)),
      Paint()
        ..color = NightColors.lantern
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 14),
    );
    canvas.drawLine(Offset(x, 90), Offset(x, 105), wire);
  }

  void text(String s, double fontSize, Color color, double y,
      {FontWeight weight = FontWeight.w800, double letterSpacing = 0, List<Shadow>? shadows}) {
    final painter = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          shadows: shadows,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 120);
    painter.paint(canvas, Offset((size.width - painter.width) / 2, y));
    painter.dispose();
  }

  final glow = [
    Shadow(color: NightColors.glow.withValues(alpha: 0.8), blurRadius: 40),
    Shadow(color: NightColors.lantern.withValues(alpha: 0.6), blurRadius: 80),
  ];
  text('夜市翻牌', 120, NightColors.glow, 260, letterSpacing: 16, shadows: glow);
  text(card.title, 56, NightColors.paper, 430, letterSpacing: 8);
  if (card.isRecord) text('🎉 新紀錄！', 48, NightColors.glow, 530);

  // 大分數：先用 260 號字量寬度，放不下一行就等比縮小
  final scoreStyle = TextStyle(fontSize: 260, fontWeight: FontWeight.w900, shadows: glow);
  final probe = TextPainter(
    text: TextSpan(text: '${card.score}', style: scoreStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  final double scoreSize = 260 * min(1.0, (size.width - 140) / probe.width);
  probe.dispose();
  text('${card.score}', scoreSize, NightColors.paper, 600 + (260 - scoreSize) / 2,
      weight: FontWeight.w900, shadows: glow);

  final details = [
    '吃了 ${card.matches} 組・最高 ${card.bestCombo} 連擊',
    if (card.allClears > 0) '全部吃光 ${card.allClears} 次',
  ];
  for (var i = 0; i < details.length; i++) {
    text(details[i], 48, NightColors.mist, 930 + i * 70.0, weight: FontWeight.w600);
  }

  text('你能吃多少？', 64, NightColors.glow, 1130, letterSpacing: 4);
  text('Night Market Match', 36, NightColors.mist.withValues(alpha: 0.7), 1240, weight: FontWeight.w600);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
