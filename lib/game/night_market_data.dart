/// 夜市小吃與關卡資料。
class Food {
  const Food(this.emoji, this.name);
  final String emoji;
  final String name;

  @override
  String toString() => name;
}

const foods = <Food>[
  Food('🍗', '雞排'),
  Food('🧋', '珍珠奶茶'),
  Food('🦪', '蚵仔煎'),
  Food('🦑', '烤魷魚'),
  Food('🥟', '小籠包'),
  Food('🍜', '牛肉麵'),
  Food('🍡', '糖葫蘆'),
  Food('🌽', '烤玉米'),
  Food('🍧', '芒果冰'),
  Food('🌭', '大腸包小腸'),
  Food('🍠', '地瓜球'),
  Food('🥚', '茶葉蛋'),
];

class Level {
  const Level({required this.name, required this.pairs, required this.seconds});
  final String name;
  final int pairs;
  final int seconds;
}

const levels = <Level>[
  Level(name: '逢甲夜市', pairs: 6, seconds: 60),
  Level(name: '士林夜市', pairs: 8, seconds: 70),
  Level(name: '六合夜市', pairs: 10, seconds: 85),
];
