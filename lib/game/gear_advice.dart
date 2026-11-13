import 'items.dart';

/// 時間到的時候，依這一局的情況建議玩家升級哪一件裝備。
class GearAdvice {
  const GearAdvice({required this.type, required this.nextLevel, required this.cost, required this.message});

  final GearType type;

  /// 升級後的等級。
  final int nextLevel;

  /// 升到 [nextLevel] 要花的金幣。
  final int cost;

  /// 給玩家看的建議（含金幣符號 🪙，畫面用 CoinText 顯示）。
  final String message;
}

/// 翻錯幾次以上，就優先建議幫助記憶的裝備。
const manyMistakes = 3;

/// 依情況挑一件還能升級的裝備；全部升滿回傳 null（就不顯示「強化裝備」選項）。
///
/// - 夜市走透透只差 1～2 組就過關：建議帽子（多時間）。
/// - 連擊衝到上限：建議攤車（提高連擊上限）。
/// - 翻錯很多次：建議老花眼鏡（多記憶時間），再來是保溫便當袋（連擊不容易斷）。
/// - 其他：照模式的預設順序，挑第一個還沒升滿的。只在大胃王有效的裝備不會建議給走透透。
GearAdvice? adviseGear({
  required int Function(GearType) levelOf,
  required int coins,
  required bool endless,
  int pairsLeft = 0,
  int bestCombo = 0,
  int comboCap = 5,
  int mistakes = 0,
}) {
  bool usable(GearType t) => (endless || !t.endlessOnly) && levelOf(t) < t.maxLevel;

  final closeToWin = !endless && pairsLeft > 0 && pairsLeft <= 2;
  final hitComboCap = bestCombo >= comboCap;
  final forgetful = mistakes >= manyMistakes;

  final order = <GearType>[
    if (closeToWin) GearType.hat,
    if (hitComboCap) GearType.cart,
    if (forgetful) ...[GearType.glasses, GearType.lunchBag],
    ...endless
        ? const [
            GearType.hat,
            GearType.backpack,
            GearType.cart,
            GearType.glasses,
            GearType.lunchBag,
            GearType.favor,
            GearType.abacus,
          ]
        : const [GearType.hat, GearType.glasses, GearType.cart, GearType.lunchBag, GearType.abacus],
  ];
  final candidates = order.where(usable);
  if (candidates.isEmpty) return null;
  final type = candidates.first;

  final current = levelOf(type);
  final next = current + 1;
  final cost = type.costs[current];
  final reason = switch (type) {
    GearType.hat when closeToWin => '只差 $pairsLeft 組就收攤了！',
    GearType.cart when hitComboCap => '連擊已經衝到上限 ×$comboCap！',
    GearType.glasses || GearType.lunchBag when forgetful => '這一局翻錯了 $mistakes 次！',
    _ => '',
  };
  final upgrade = '${type.label}升到 Lv.$next，';
  final effect = switch (type) {
    GearType.hat => endless
        ? '每一輪時間 +${GearEffects.bonusSeconds(next) - GearEffects.bonusSeconds(current)} 秒，能多吃幾桌'
        : '每局時間 +${GearEffects.bonusSeconds(next) - GearEffects.bonusSeconds(current)} 秒',
    GearType.cart => '連擊上限提高到 ×${GearEffects.comboCap(next)}，分數更高',
    GearType.abacus =>
      '金幣再 +${((GearEffects.coinMultiplier(next) - GearEffects.coinMultiplier(current)) * 100).round()}%',
    GearType.glasses =>
      '開局翻牌記憶多 ${GearEffects.previewBonusSeconds(next) - GearEffects.previewBonusSeconds(current)} 秒，更容易記住',
    GearType.lunchBag => next >= 2 ? '每局第一次翻錯完全不扣連擊' : '翻錯時連擊只少 1 段，不會歸零',
    GearType.backpack =>
      '清桌獎勵再 +${((GearEffects.clearBonusMultiplier(next) - GearEffects.clearBonusMultiplier(current)) * 100).round()}%',
    GearType.favor => '老闆提示的冷卻再少 1 組，卡住時更快拿到提示',
  };
  final price = coins >= cost ? '（🪙 $cost，現在就升得起）' : '（🪙 $cost）';
  return GearAdvice(type: type, nextLevel: next, cost: cost, message: '$reason$upgrade$effect$price');
}
