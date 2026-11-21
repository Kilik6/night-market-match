import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:night_market_match/services/progress_store.dart';
import 'package:night_market_match/services/purchase_service.dart';
import 'package:night_market_match/services/store_purchase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假的商店：記錄買了什麼、通知了哪些交易完成，購買結果由測試從 [emit] 送出。
class FakeIap implements InAppPurchase {
  FakeIap({this.available = true, Set<String>? missing}) : missing = missing ?? {};

  final bool available;
  final Set<String> missing;
  final _stream = StreamController<List<PurchaseDetails>>.broadcast();
  final bought = <String>[];
  final completed = <String>[];
  List<PurchaseDetails> toRestore = [];

  void emit(List<PurchaseDetails> list) => _stream.add(list);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async => ProductDetailsResponse(
        productDetails: [
          for (final id in identifiers.difference(missing))
            ProductDetails(
                id: id, title: id, description: '', price: 'NT\$${id.length}', rawPrice: 1, currencyCode: 'TWD'),
        ],
        notFoundIDs: missing.toList(),
      );

  @override
  Future<bool> buyConsumable({required PurchaseParam purchaseParam, bool autoConsume = true}) async {
    bought.add(purchaseParam.productDetails.id);
    return true;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add('${purchaseParam.productDetails.id}(永久)');
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed.add(purchase.purchaseID ?? '');

  @override
  Future<void> restorePurchases({String? applicationUserName}) async => emit(toRestore);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PurchaseDetails purchase(String productId, PurchaseStatus status, {String id = 'tx1'}) => PurchaseDetails(
      purchaseID: id,
      productID: productId,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'test'),
      transactionDate: '1',
      status: status,
    )..pendingCompletePurchase = status != PurchaseStatus.pending;

void main() {
  late ProgressStore store;
  late FakeIap iap;
  late StorePurchaseService service;

  Future<void> setUp0({bool available = true, Set<String>? missing}) async {
    SharedPreferences.setMockInitialValues({});
    store = await ProgressStore.load();
    iap = FakeIap(available: available, missing: missing);
    service = StorePurchaseService(store, iap: iap, restoreWait: Duration.zero);
    await service.init();
  }

  /// 等購買串流的事件處理完。
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('買金幣：付款成功才發金幣、通知交易完成；價格用商店回傳的', () async {
    await setUp0();
    expect(service.deliversContent, isTrue);
    expect(service.price('coins_30'), 'NT\$8', reason: '用商店的價格字串');
    final result = buyCoinPack(service, store, coinPacks.first);
    await flush();
    expect(iap.bought, ['coins_30']);
    expect(store.coins, 0, reason: '還沒付款完成');
    iap.emit([purchase('coins_30', PurchaseStatus.purchased)]);
    expect(await result, PurchaseResult.success);
    expect(store.coins, coinPacks.first.coins, reason: '只發一次（服務發放，呼叫的地方不再發）');
    expect(iap.completed, ['tx1']);
  });

  test('同一筆交易重送不會重複發放，但還是會通知交易完成', () async {
    await setUp0();
    iap.emit([purchase('coins_90', PurchaseStatus.purchased)]);
    await flush();
    iap.emit([purchase('coins_90', PurchaseStatus.purchased)]);
    await flush();
    expect(store.coins, coinPacks[1].coins);
    expect(iap.completed, ['tx1', 'tx1']);
  });

  test('待處理付款：先回傳處理中，之後付款完成自動發放並通知畫面', () async {
    await setUp0();
    final later = <String>[];
    service.deliveredLater.listen(later.add);
    final result = service.buy('month_card');
    await flush();
    iap.emit([purchase('month_card', PurchaseStatus.pending)]);
    expect(await result, PurchaseResult.pending);
    expect(iap.completed, isEmpty, reason: '還沒付款完成，不能通知交易完成');
    iap.emit([purchase('month_card', PurchaseStatus.purchased)]);
    await flush();
    expect(store.monthCardActive, isTrue);
    expect(later, ['month_card']);
  });

  test('上次沒處理完的付款（App 中途被關掉），下次開啟時發放', () async {
    await setUp0();
    final later = <String>[];
    service.deliveredLater.listen(later.add);
    iap.emit([purchase('starter_pack', PurchaseStatus.purchased, id: 'old')]);
    await flush();
    expect(store.starterPackBought, isTrue);
    expect(later, ['starter_pack']);
  });

  test('取消和失敗：不發放', () async {
    await setUp0();
    final cancel = service.buy('coins_30');
    await flush();
    iap.emit([purchase('coins_30', PurchaseStatus.canceled)]);
    expect(await cancel, PurchaseResult.cancelled);
    final fail = service.buy('coins_30');
    await flush();
    iap.emit([purchase('coins_30', PurchaseStatus.error)]);
    expect(await fail, PurchaseResult.failed);
    expect(store.coins, 0);
  });

  test('非消耗型商品用永久購買；商店沒有的商品或商店不能用時回傳無法使用', () async {
    await setUp0(missing: {'coins_990'});
    final r = buyRemoveAds(service, store);
    await flush();
    expect(iap.bought, ['remove_ads(永久)']);
    iap.emit([purchase('remove_ads', PurchaseStatus.purchased)]);
    expect(await r, PurchaseResult.success);
    expect(store.adsRemoved, isTrue);
    expect(await service.buy('coins_990'), PurchaseResult.unavailable);
    expect(service.price('coins_990'), isNull);
    expect(defaultPriceLabel('coins_990'), 'NT\$990', reason: '畫面改顯示預設價格');

    await setUp0(available: false);
    expect(await service.buy('coins_30'), PurchaseResult.unavailable);
    expect(await service.restore(), isNull);
  });

  test('恢復購買：拿回移除廣告和禮包卡背，不會再發一次金幣', () async {
    await setUp0();
    iap.toRestore = [
      purchase('remove_ads', PurchaseStatus.restored, id: 'a'),
      purchase('starter_pack', PurchaseStatus.restored, id: 'b'),
    ];
    expect(await restorePurchases(service, store), isTrue);
    expect(store.adsRemoved, isTrue);
    expect(store.ownedSkins, contains(starterPackSkinId));
    expect(store.coins, 0);
    expect(iap.completed, ['a', 'b']);
  });
}
