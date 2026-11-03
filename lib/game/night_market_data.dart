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
  Food('🍢', '黑輪'),
  Food('🍤', '炸蝦'),
  Food('🍦', '霜淇淋'),
  Food('🍖', '烤肉串'),
  Food('🧇', '雞蛋糕'),
  Food('🍮', '布丁'),
  Food('🥤', '木瓜牛奶'),
  Food('🍙', '飯糰'),
];

class Level {
  const Level({required this.name, required this.city, required this.pairs, required this.seconds});
  final String name;
  final String city;
  final int pairs;
  final int seconds;
}

/// 難度：前 6 攤逐步增加牌數；之後牌數最多 24 張（小螢幕也點得到），
/// 主要靠縮短時間增加難度，平均每組可用的秒數從 10 秒逐漸降到 4 秒。
const levels = <Level>[
  Level(name: '逢甲夜市', city: '台中', pairs: 6, seconds: 60),
  Level(name: '士林夜市', city: '台北', pairs: 8, seconds: 70),
  Level(name: '六合夜市', city: '高雄', pairs: 10, seconds: 85),
  Level(name: '饒河街夜市', city: '台北', pairs: 10, seconds: 70),
  Level(name: '花園夜市', city: '台南', pairs: 12, seconds: 95),
  Level(name: '羅東夜市', city: '宜蘭', pairs: 12, seconds: 80),
  Level(name: '寧夏夜市', city: '台北', pairs: 8, seconds: 45),
  Level(name: '華西街夜市', city: '台北', pairs: 10, seconds: 60),
  Level(name: '基隆廟口夜市', city: '基隆', pairs: 12, seconds: 75),
  Level(name: '一中街', city: '台中', pairs: 10, seconds: 50),
  Level(name: '樂華夜市', city: '新北', pairs: 12, seconds: 70),
  Level(name: '中壢觀光夜市', city: '桃園', pairs: 12, seconds: 65),
  Level(name: '城隍廟夜市', city: '新竹', pairs: 12, seconds: 62),
  Level(name: '文化路夜市', city: '嘉義', pairs: 12, seconds: 58),
  Level(name: '大東夜市', city: '台南', pairs: 12, seconds: 55),
  Level(name: '瑞豐夜市', city: '高雄', pairs: 12, seconds: 52),
  Level(name: '東大門夜市', city: '花蓮', pairs: 12, seconds: 50),
  Level(name: '南機場夜市', city: '台北', pairs: 12, seconds: 48),
];
