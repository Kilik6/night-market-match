import 'package:flutter/material.dart';

import '../game/night_market_data.dart';

/// 小吃圖案：有專屬圖片就用圖片，否則用 emoji。
class FoodIcon extends StatelessWidget {
  const FoodIcon({super.key, required this.food, required this.size});

  final Food food;

  /// emoji 的字級。圖片沒有 emoji 周圍的留白，所以畫大一點，兩者看起來才一樣大。
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = food.image;
    if (image == null) return Text(food.emoji, style: TextStyle(fontSize: size));
    return Image.asset(
      image,
      key: ValueKey(image),
      width: size * 1.75,
      height: size * 1.75,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: food.name,
    );
  }
}
