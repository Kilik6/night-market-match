import 'dart:math';

import 'items.dart';

/// 夜市轉盤的一格獎品：金幣或道具。
class WheelPrize {
  const WheelPrize({required this.label, this.coins = 0, this.item, required this.weight});

  /// 轉盤上的字（金幣用 🪙 開頭，畫面用自畫的金幣圖示）。
  final String label;
  final int coins;
  final ItemType? item;

  /// 抽中的機率權重。
  final int weight;
}

/// 夜市轉盤：每天免費轉一次，看廣告可以再轉 [wheelAdSpinsPerDay] 次。
/// 八格平均約 100 枚金幣，另外有機會抽到道具。
const wheelPrizes = <WheelPrize>[
  WheelPrize(label: '🪙 50', coins: 50, weight: 24),
  WheelPrize(label: '🪙 100', coins: 100, weight: 20),
  WheelPrize(label: '🔍', item: ItemType.magnifier, weight: 12),
  WheelPrize(label: '🪙 200', coins: 200, weight: 12),
  WheelPrize(label: '🧧', item: ItemType.charm, weight: 12),
  WheelPrize(label: '🪙 300', coins: 300, weight: 8),
  WheelPrize(label: '⏳', item: ItemType.hourglass, weight: 8),
  WheelPrize(label: '🪙 500', coins: 500, weight: 4),
];

/// 每天看廣告可以多轉幾次。
const wheelAdSpinsPerDay = 3;

/// 商店每天看廣告領金幣的次數和每次的金幣。
const shopAdCoinsPerDay = 5;
const shopAdCoins = 100;

/// 依權重抽一格，回傳 [wheelPrizes] 的索引。
int spinWheel(Random random) {
  final total = wheelPrizes.fold(0, (sum, p) => sum + p.weight);
  var roll = random.nextInt(total);
  for (var i = 0; i < wheelPrizes.length; i++) {
    roll -= wheelPrizes[i].weight;
    if (roll < 0) return i;
  }
  return wheelPrizes.length - 1;
}
