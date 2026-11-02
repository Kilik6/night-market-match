import 'package:flutter/material.dart';

/// 單張卡片，對應 React Native 版的 Card.tsx。
class CardWidget extends StatelessWidget {
  const CardWidget({
    super.key,
    required this.title,
    required this.isShow,
    required this.onTap,
    this.cover = '?',
    this.fontSize = 30,
    this.size = 58,
  });

  final String title;
  final String cover;
  final bool isShow;
  final double fontSize;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x5BE2D594), // RN 版的 '#e2d5945b'（RGBA 轉成 Flutter 的 ARGB）
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(isShow ? title : cover, style: TextStyle(fontSize: fontSize)),
          ),
        ),
      ),
    );
  }
}
