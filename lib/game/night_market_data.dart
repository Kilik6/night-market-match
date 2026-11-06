/// 夜市小吃與關卡資料。
class Food {
  const Food(this.emoji, this.name, this.description, {this.image});
  final String emoji;
  final String name;

  /// 小吃圖鑑的介紹。
  final String description;

  /// 專屬圖片。emoji 在各平台長得不一樣，也不一定像台灣小吃，這時就用圖片。
  final String? image;

  @override
  String toString() => name;
}

/// name 會寫進存檔（圖鑑收集），上架後不要改。
const foods = <Food>[
  Food('🍗', '雞排', '夜市人氣王，炸得酥脆再撒上胡椒鹽，有些攤位的雞排比臉還大。', image: 'assets/foods/chicken_cutlet.png'),
  Food('🧋', '珍珠奶茶', '1980 年代誕生於台灣的手搖飲，Q 彈的粉圓現在紅遍全世界。', image: 'assets/foods/bubble_tea.png'),
  Food('🦪', '蚵仔煎', '鮮蚵加上地瓜粉漿和雞蛋煎成，淋上甜辣醬是經典吃法。', image: 'assets/foods/oyster_omelette.png'),
  Food('🦑', '烤魷魚', '刷上醬料在炭火上烤，還沒走到攤位就先聞到香味。', image: 'assets/foods/grilled_squid.png'),
  Food('🥟', '小籠包', '薄皮裡包著鮮肉和湯汁，咬開前要小心燙口。', image: 'assets/foods/xiaolongbao.png'),
  Food('🍜', '牛肉麵', '紅燒或清燉的湯頭配上大塊牛肉，是台灣代表性的麵食。', image: 'assets/foods/beef_noodles.png'),
  Food('🍡', '糖葫蘆', '水果裹上一層薄薄的糖衣，咬下去又脆又酸甜。', image: 'assets/foods/tanghulu.png'),
  Food('🌽', '烤玉米', '一邊烤一邊刷上特製醬料，帶點焦香是好吃的關鍵。', image: 'assets/foods/grilled_corn.png'),
  Food('🍧', '芒果冰', '綿密的冰品鋪上大塊芒果，是台灣夏天最受歡迎的甜點。', image: 'assets/foods/mango_ice.png'),
  Food('🌭', '大腸包小腸', '用糯米腸當麵包夾住台式香腸，再加上蒜片和酸菜。', image: 'assets/foods/sausage_bun.png'),
  Food('🍠', '地瓜球', '用剪刀壓一壓就會膨起來，外酥內 Q，一口一顆剛剛好。', image: 'assets/foods/sweet_potato_balls.png'),
  Food('🥚', '茶葉蛋', '用茶葉和滷料慢慢浸煮，蛋白上有漂亮的大理石紋路。', image: 'assets/foods/tea_egg.png'),
  Food('🍢', '黑輪', '源自日本關東煮的魚漿製品，沾上甜辣醬，冬天吃特別暖。', image: 'assets/foods/heilun.png'),
  Food('🍤', '炸蝦', '裹粉炸得金黃酥脆，連蝦殼都能一起吃下去。', image: 'assets/foods/fried_shrimp.png'),
  Food('🍦', '霜淇淋', '綿密的口感在夜市很受歡迎，常見牛奶和抹茶口味。', image: 'assets/foods/soft_serve.png'),
  Food('🍖', '烤肉串', '肉串烤得滋滋作響，撒上孜然或胡椒粉一起吃。', image: 'assets/foods/meat_skewer.png'),
  Food('🧇', '雞蛋糕', '用各種造型的模具烤成小蛋糕，外皮香、裡面鬆軟。', image: 'assets/foods/egg_cake.png'),
  Food('🍮', '布丁', '滑嫩的雞蛋布丁配上焦糖，有些攤位還會現場烤。', image: 'assets/foods/pudding.png'),
  Food('🥤', '木瓜牛奶', '新鮮木瓜和牛奶打成的飲品，是夜市常見的果汁攤招牌。', image: 'assets/foods/papaya_milk.png'),
  Food('🍙', '飯糰', '糯米包著油條、肉鬆和菜脯，台式飯糰一個就很有飽足感。', image: 'assets/foods/rice_roll.png'),
];

class Level {
  const Level({required this.name, required this.city, required this.pairs, required this.seconds});
  final String name;
  final String city;
  final int pairs;
  final int seconds;
}

/// 夜市依知名度排序：前面是比較冷門的，最熱門的放在最後最難的關卡。
/// 難度：前 6 攤逐步增加牌數；之後牌數最多 24 張（小螢幕也點得到），
/// 主要靠縮短時間增加難度，平均每組可用的秒數從 10 秒逐漸降到 4 秒。
const levels = <Level>[
  Level(name: '南機場夜市', city: '台北', pairs: 6, seconds: 60),
  Level(name: '城隍廟夜市', city: '新竹', pairs: 8, seconds: 70),
  Level(name: '中壢觀光夜市', city: '桃園', pairs: 10, seconds: 85),
  Level(name: '樂華夜市', city: '新北', pairs: 10, seconds: 70),
  Level(name: '華西街夜市', city: '台北', pairs: 12, seconds: 95),
  Level(name: '大東夜市', city: '台南', pairs: 12, seconds: 80),
  Level(name: '文化路夜市', city: '嘉義', pairs: 8, seconds: 45),
  Level(name: '東大門夜市', city: '花蓮', pairs: 10, seconds: 60),
  Level(name: '一中街', city: '台中', pairs: 12, seconds: 75),
  Level(name: '瑞豐夜市', city: '高雄', pairs: 10, seconds: 50),
  Level(name: '寧夏夜市', city: '台北', pairs: 12, seconds: 70),
  Level(name: '羅東夜市', city: '宜蘭', pairs: 12, seconds: 65),
  Level(name: '基隆廟口夜市', city: '基隆', pairs: 12, seconds: 62),
  Level(name: '花園夜市', city: '台南', pairs: 12, seconds: 58),
  Level(name: '六合夜市', city: '高雄', pairs: 12, seconds: 55),
  Level(name: '饒河街夜市', city: '台北', pairs: 12, seconds: 52),
  Level(name: '逢甲夜市', city: '台中', pairs: 12, seconds: 50),
  Level(name: '士林夜市', city: '台北', pairs: 12, seconds: 48),
];
