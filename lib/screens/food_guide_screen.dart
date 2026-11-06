import 'package:flutter/material.dart';

import '../game/night_market_data.dart';
import '../services/progress_store.dart';
import '../theme.dart';
import '../widgets/food_icon.dart';
import '../widgets/night_scaffold.dart';

/// 小吃圖鑑：配對過的小吃會收錄，點開看介紹。
class FoodGuideScreen extends StatelessWidget {
  const FoodGuideScreen({super.key, required this.store});

  final ProgressStore store;

  void _show(BuildContext context, Food food) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: Row(
          children: [
            FoodIcon(food: food, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(food.name, style: const TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Text(food.description, style: const TextStyle(color: NightColors.ink, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉', style: TextStyle(color: NightColors.ink)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final found = store.discoveredFoods;
    return NightScaffold(
      title: '小吃圖鑑 ${found.length} / ${foods.length}',
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
        ),
        itemCount: foods.length,
        itemBuilder: (context, i) {
          final food = foods[i];
          final isFound = found.contains(food.name);
          return Material(
            color: isFound ? NightColors.paper : NightColors.stall,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: ValueKey('food_$i'),
              borderRadius: BorderRadius.circular(10),
              onTap: isFound ? () => _show(context, food) : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isFound)
                      FoodIcon(food: food, size: 30)
                    else
                      const Text('❓', style: TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isFound ? food.name : '尚未收錄',
                        style: TextStyle(
                          color: isFound ? NightColors.ink : NightColors.mist,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
