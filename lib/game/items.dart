/// 道具：用金幣購買，帶進關卡使用，用一次少一個。每局每種限用一次。
/// 價格約是一關收入的一半（走透透一關約 300～500 枚，看廣告翻倍）。
/// enum 的 name 會寫進存檔，上架後不要改。
enum ItemType {
  magnifier('🔍', '放大鏡', '自動配對一組牌', 250),
  hourglass('⏳', '沙漏', '時間 +10 秒', 300),
  charm('🧧', '護身符', '下一次翻錯不會中斷連擊', 200),
  luckyCat('🐱', '招財貓', '這一局金幣 ×1.5', 600);

  const ItemType(this.emoji, this.label, this.description, this.price);

  final String emoji;
  final String label;
  final String description;
  final int price;
}

/// 裝備：用金幣升級，效果永久有效。enum 的 name 會寫進存檔，上架後不要改。
enum GearType {
  hat('🧢', '老闆的帽子', [2000, 4000, 7000]),
  abacus('🧮', '算盤', [2000, 4000, 7000]),
  cart('🛒', '攤車', [3000, 8000]),
  glasses('👓', '老花眼鏡', [2500, 5000, 8000]),
  lunchBag('🍱', '保溫便當袋', [3000, 9000]),
  backpack('🎒', '大胃王背包', [2000, 4500, 8000], endlessOnly: true),
  favor('🧧', '老闆的人情', [2500, 6000], endlessOnly: true);

  const GearType(this.emoji, this.label, this.costs, {this.endlessOnly = false});

  final String emoji;
  final String label;

  /// 只在夜市大胃王有效果。
  final bool endlessOnly;

  /// 每一級的升級費用，長度就是最高等級。
  final List<int> costs;

  int get maxLevel => costs.length;

  /// 目前等級的效果說明。
  String effect(int level) => switch (this) {
        GearType.hat => '每局時間 +${level * 2} 秒',
        GearType.abacus => '過關金幣 +${level * 10}%',
        GearType.cart => '連擊上限 ×${5 + level}',
        GearType.glasses => '開局翻牌記憶 +${GearEffects.previewBonusSeconds(level)} 秒',
        GearType.lunchBag => level >= 2 ? '翻錯時連擊只少 1 段，每局第一次翻錯不扣' : '翻錯時連擊只少 1 段，不會歸零',
        GearType.backpack => '大胃王清桌獎勵 +${level * 10}%',
        GearType.favor => '大胃王老闆提示的冷卻少 ${GearEffects.bossHintCooldownCut(level)} 組',
      };
}

/// 把裝備等級換算成遊戲數值。
abstract final class GearEffects {
  static int bonusSeconds(int hatLevel) => hatLevel * 2;
  static double coinMultiplier(int abacusLevel) => 1 + abacusLevel * 0.1;
  static int comboCap(int cartLevel) => 5 + cartLevel;

  /// 老花眼鏡：開局翻牌記憶多幾秒。
  static int previewBonusSeconds(int glassesLevel) => glassesLevel;

  /// 保溫便當袋 Lv.1 起：翻錯時連擊只少 1 段，不會歸零。
  static bool comboKeepOnMiss(int lunchBagLevel) => lunchBagLevel >= 1;

  /// 保溫便當袋 Lv.2：每局第一次翻錯完全不扣連擊。
  static bool firstMissForgiven(int lunchBagLevel) => lunchBagLevel >= 2;

  /// 大胃王背包：清桌獎勵倍率。
  static double clearBonusMultiplier(int backpackLevel) => 1 + backpackLevel * 0.1;

  /// 老闆的人情：老闆提示的冷卻少幾組。
  static int bossHintCooldownCut(int favorLevel) => favorLevel;
}
