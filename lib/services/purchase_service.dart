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

  /// 付款失敗（網路、商店錯誤）。
  failed,

  /// 這個版本還不能儲值。
  unavailable,
}

/// 商店付款。畫面只依賴這個介面：開發時用 [DevPurchaseService]，之後換成串接 App Store／Google Play 的版本。
abstract class PurchaseService {
  /// 購買商品。
  Future<PurchaseResult> buy(String productId);

  /// 恢復購買：回傳玩家買過的非消耗型商品 id（例如移除廣告）。無法使用時回傳 null。
  Future<Set<String>?> restore();
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
    if (productId == removeAdsProductId) _owned.add(productId);
    return PurchaseResult.success;
  }

  @override
  Future<Set<String>?> restore() async => enabled ? {..._owned} : null;
}

/// 買金幣：付款成功就把金幣加進存檔。
Future<PurchaseResult> buyCoinPack(PurchaseService purchases, ProgressStore store, CoinPack pack) async {
  final result = await purchases.buy(pack.id);
  if (result == PurchaseResult.success) await store.addCoins(pack.coins);
  return result;
}

/// 買月卡：付款成功就延長天數並給立即金幣。剩餘天數太多時不能買，回傳 null。
Future<PurchaseResult?> buyMonthCard(PurchaseService purchases, ProgressStore store) async {
  if (!store.canBuyMonthCard) return null;
  final result = await purchases.buy(monthCardProductId);
  if (result == PurchaseResult.success) await store.activateMonthCard();
  return result;
}

/// 買永久移除廣告：付款成功就記進存檔。
Future<PurchaseResult> buyRemoveAds(PurchaseService purchases, ProgressStore store) async {
  if (store.adsRemoved) return PurchaseResult.success;
  final result = await purchases.buy(removeAdsProductId);
  if (result == PurchaseResult.success) await store.setAdsRemoved(true);
  return result;
}

/// 恢復購買。回傳是否恢復了移除廣告；無法使用時回傳 null。
Future<bool?> restorePurchases(PurchaseService purchases, ProgressStore store) async {
  final owned = await purchases.restore();
  if (owned == null) return null;
  if (!owned.contains(removeAdsProductId)) return false;
  await store.setAdsRemoved(true);
  return true;
}
