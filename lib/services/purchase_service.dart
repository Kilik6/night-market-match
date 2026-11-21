import 'package:flutter/foundation.dart';

import 'progress_store.dart';

/// 儲值金幣方案。id 是商店後台（App Store Connect、Google Play Console）的商品 ID，上架後不要改。
class CoinPack {
  const CoinPack({
    required this.id,
    required this.name,
    required this.emoji,
    required this.priceNtd,
    required this.coins,
  });

  final String id;
  final String name;
  final String emoji;

  /// 新台幣價格。正式上架後以商店回傳的價格字串為準。
  final int priceNtd;
  final int coins;

  String get priceLabel => 'NT\$$priceNtd';

  /// 跟最小方案相比多送的比例（0.03 = 多送 3%）。
  double get bonus => coins / priceNtd / (coinPacks.first.coins / coinPacks.first.priceNtd) - 1;
}

/// 六種儲值方案，由小到大。基本換算 NT$1 約 33 枚，買越多送越多，最多多送約 15%。
const coinPacks = <CoinPack>[
  CoinPack(id: 'coins_30', name: '一把零錢', emoji: '🪙', priceNtd: 30, coins: 1000),
  CoinPack(id: 'coins_90', name: '小紅包', emoji: '🧧', priceNtd: 90, coins: 3100),
  CoinPack(id: 'coins_170', name: '錢袋', emoji: '💰', priceNtd: 170, coins: 6000),
  CoinPack(id: 'coins_330', name: '聚寶盆', emoji: '🏺', priceNtd: 330, coins: 12000),
  CoinPack(id: 'coins_590', name: '金元寶箱', emoji: '🧰', priceNtd: 590, coins: 22000),
  CoinPack(id: 'coins_990', name: '老闆的錢櫃', emoji: '🏪', priceNtd: 990, coins: 38000),
];

/// 新手禮包：每個人只能買一次的超值包，金幣、每種道具各幾個，加上限定卡背。
const starterPackProductId = 'starter_pack';
const starterPackPriceNtd = 60;
const starterPackCoins = 3000;
const starterPackItemsEach = 3;
const starterPackSkinId = 'grand_opening';

/// 夜市月卡：買下馬上得到 [monthCardInstantCoins]，之後 [monthCardDays] 天（含購買當天）
/// 每天到「每日任務」領 [monthCardDailyCoins]，沒領的那天就沒有了。
/// 在商店後台是一般的消耗型商品（不是自動續訂），玩家想續就再買一次，天數接在後面。
const monthCardProductId = 'month_card';
const monthCardPriceNtd = 150;
const monthCardInstantCoins = 1500;
const monthCardDailyCoins = 300;
const monthCardDays = 30;

/// 月卡全部領完的總金幣（每 NT\$1 約 70 枚，是一般金幣方案的兩倍，但要每天上線領）。
const monthCardTotalCoins = monthCardInstantCoins + monthCardDailyCoins * monthCardDays;

/// 永久移除廣告：只移除自動跳出的插頁廣告，玩家自己點的獎勵廣告保留。
const removeAdsProductId = 'remove_ads';
const removeAdsPriceNtd = 180;

enum PurchaseResult {
  success,

  /// 玩家自己取消。
  cancelled,

  /// 付款處理中（例如 Android 的超商付款），完成後會自動發放。
  pending,

  /// 付款失敗（網路、商店錯誤）。
  failed,

  /// 這個版本還不能儲值。
  unavailable,
}

/// 商店付款。畫面只依賴這個介面：開發時用 [DevPurchaseService]，正式版用串接 App Store／Google Play 的
/// StorePurchaseService（lib/services/store_purchase_service.dart）。
abstract class PurchaseService {
  /// 購買商品。
  Future<PurchaseResult> buy(String productId);

  /// 恢復購買：回傳玩家買過的非消耗型商品 id（例如移除廣告）。無法使用時回傳 null。
  Future<Set<String>?> restore();

  /// 商店回傳、依玩家所在地區顯示的價格（例如「NT$30」）；還沒載入或假商店回傳 null，畫面改顯示預設價格。
  String? price(String productId);

  /// true：付款成功時服務自己就把商品發給玩家（真的商店，付款結果可能很晚才到）；
  /// false：由呼叫的地方在 [buy] 成功後發放（假商店）。
  bool get deliversContent;
}

/// 商品的預設價格（商店價格還沒載入時顯示）。
String defaultPriceLabel(String productId) {
  final ntd = switch (productId) {
    starterPackProductId => starterPackPriceNtd,
    monthCardProductId => monthCardPriceNtd,
    removeAdsProductId => removeAdsPriceNtd,
    _ => coinPacks.firstWhere((p) => p.id == productId).priceNtd,
  };
  return 'NT\$$ntd';
}

/// 所有商品 id。
final allProductIds = {
  for (final p in coinPacks) p.id,
  starterPackProductId,
  monthCardProductId,
  removeAdsProductId,
};

/// 非消耗型商品：買一次永久擁有，可以恢復購買。其他都是消耗型（可以重複買）。
const nonConsumableProductIds = {removeAdsProductId, starterPackProductId};

/// 把買到的商品發給玩家。
Future<void> deliverPurchase(ProgressStore store, String productId) async {
  switch (productId) {
    case removeAdsProductId:
      await store.setAdsRemoved(true);
    case starterPackProductId:
      await store.grantStarterPack();
    case monthCardProductId:
      await store.activateMonthCard();
    default:
      final pack = coinPacks.where((p) => p.id == productId).firstOrNull;
      if (pack != null) await store.addCoins(pack.coins);
  }
}

/// 恢復非消耗型商品（換手機時）：只拿回「移除廣告」和新手禮包的卡背，不會再發一次金幣和道具。
Future<void> restoreNonConsumable(ProgressStore store, String productId) async {
  if (productId == removeAdsProductId) await store.setAdsRemoved(true);
  if (productId == starterPackProductId) await store.restoreStarterPack();
}

/// 開發測試用的假商店，不會真的扣款。
///
/// 只有 debug 版會購買成功；release 版一律回傳 [PurchaseResult.unavailable]，
/// 避免忘記換成真的付款就上架，讓玩家免費拿到金幣。
class DevPurchaseService implements PurchaseService {
  DevPurchaseService({bool? enabled}) : enabled = enabled ?? kDebugMode;

  final bool enabled;

  /// 這次開啟 App 期間買過的非消耗型商品（假商店不會記到下次開啟）。
  final Set<String> _owned = {};

  @override
  Future<PurchaseResult> buy(String productId) async {
    if (!enabled) return PurchaseResult.unavailable;
    if (productId == removeAdsProductId || productId == starterPackProductId) _owned.add(productId);
    return PurchaseResult.success;
  }

  @override
  Future<Set<String>?> restore() async => enabled ? {..._owned} : null;

  @override
  String? price(String productId) => null;

  @override
  bool get deliversContent => false;
}

/// 付款成功、而且購買服務沒有自己發放時，由這裡發放。
Future<void> _deliverIfNeeded(PurchaseService purchases, ProgressStore store, String productId, PurchaseResult result) async {
  if (result == PurchaseResult.success && !purchases.deliversContent) await deliverPurchase(store, productId);
}

/// 買金幣：付款成功就把金幣加進存檔。
Future<PurchaseResult> buyCoinPack(PurchaseService purchases, ProgressStore store, CoinPack pack) async {
  final result = await purchases.buy(pack.id);
  await _deliverIfNeeded(purchases, store, pack.id, result);
  return result;
}

/// 買月卡：付款成功就延長天數並給立即金幣。剩餘天數太多時不能買，回傳 null。
Future<PurchaseResult?> buyMonthCard(PurchaseService purchases, ProgressStore store) async {
  if (!store.canBuyMonthCard) return null;
  final result = await purchases.buy(monthCardProductId);
  await _deliverIfNeeded(purchases, store, monthCardProductId, result);
  return result;
}

/// 買新手禮包：付款成功就發金幣、道具和卡背。已經買過回傳 null。
Future<PurchaseResult?> buyStarterPack(PurchaseService purchases, ProgressStore store) async {
  if (store.starterPackBought) return null;
  final result = await purchases.buy(starterPackProductId);
  await _deliverIfNeeded(purchases, store, starterPackProductId, result);
  return result;
}

/// 買永久移除廣告：付款成功就記進存檔。
Future<PurchaseResult> buyRemoveAds(PurchaseService purchases, ProgressStore store) async {
  if (store.adsRemoved) return PurchaseResult.success;
  final result = await purchases.buy(removeAdsProductId);
  await _deliverIfNeeded(purchases, store, removeAdsProductId, result);
  return result;
}

/// 恢復購買：拿回「永久移除廣告」和新手禮包的限定卡背（金幣和道具是消耗品，不會恢復）。
/// 回傳是否恢復了任何東西；無法使用時回傳 null。
Future<bool?> restorePurchases(PurchaseService purchases, ProgressStore store) async {
  final owned = await purchases.restore();
  if (owned == null) return null;
  var restored = false;
  for (final id in owned.intersection(nonConsumableProductIds)) {
    await restoreNonConsumable(store, id);
    restored = true;
  }
  return restored;
}
