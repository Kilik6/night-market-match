import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'progress_store.dart';
import 'purchase_service.dart';

/// 串接 App Store／Google Play 的應用程式內購買。
///
/// 付款結果是從商店的購買串流傳來的，可能很晚才到（App 中途被關掉、Android 的超商付款），
/// 所以由這個服務自己發放商品（[deliversContent] 是 true），不管結果什麼時候到都會發：
/// - 有人在等 [buy] 的結果：發放後回傳 [PurchaseResult.success]，由畫面顯示「購買成功」。
/// - 沒人在等（晚到的付款）：發放後從 [deliveredLater] 通知，App 顯示提示。
///
/// 同一筆交易只發一次（交易編號記在存檔），發放後才通知商店交易完成；
/// 發放前 App 被關掉的話，商店下次開啟會重送，不會讓玩家付了錢沒拿到。
///
/// 沒有自己的伺服器驗證收據：這是單機遊戲，被破解的損失有限，之後營收夠大再加。
class StorePurchaseService implements PurchaseService {
  StorePurchaseService(this._store, {InAppPurchase? iap, this.restoreWait = const Duration(seconds: 3)})
      : _iap = iap ?? InAppPurchase.instance;

  final ProgressStore _store;
  final InAppPurchase _iap;

  /// 恢復購買時等商店回傳的時間（商店不會告訴我們「已經全部傳完」）。
  final Duration restoreWait;

  final Map<String, ProductDetails> _products = {};
  final Map<String, Completer<PurchaseResult>> _waiting = {};
  final Set<String> _restored = {};
  final _later = StreamController<String>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _available = false;

  /// 沒人在等的付款（晚到、待處理後完成）發放後，送出商品 id。
  Stream<String> get deliveredLater => _later.stream;

  @override
  bool get open => true;

  @override
  bool get deliversContent => true;

  @override
  String? price(String productId) => _products[productId]?.price;

  /// App 一開始就呼叫：先開始聽購買串流（才收得到上次沒處理完的付款），再載入商品和價格。
  Future<void> init() async {
    _subscription ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('購買串流錯誤：$e'),
    );
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      final response = await _iap.queryProductDetails(allProductIds);
      for (final p in response.productDetails) {
        _products[p.id] = p;
      }
      if (response.notFoundIDs.isNotEmpty) debugPrint('商店找不到這些商品：${response.notFoundIDs}');
    } catch (e) {
      debugPrint('載入商品失敗：$e');
    }
  }

  @override
  Future<PurchaseResult> buy(String productId) async {
    if (!_available) return PurchaseResult.unavailable;
    final product = _products[productId];
    if (product == null) return PurchaseResult.unavailable;
    if (_waiting.containsKey(productId)) return PurchaseResult.failed; // 同一個商品正在付款
    final done = Completer<PurchaseResult>();
    _waiting[productId] = done;
    try {
      final param = PurchaseParam(productDetails: product);
      final started = nonConsumableProductIds.contains(productId)
          ? await _iap.buyNonConsumable(purchaseParam: param)
          : await _iap.buyConsumable(purchaseParam: param);
      if (!started) _finish(productId, PurchaseResult.failed);
    } on PlatformException catch (e) {
      debugPrint('購買失敗：${e.code} ${e.message}');
      _finish(productId, PurchaseResult.failed);
    }
    return done.future;
  }

  @override
  Future<Set<String>?> restore() async {
    if (!_available) return null;
    _restored.clear();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('恢復購買失敗：$e');
      return null;
    }
    await Future<void>.delayed(restoreWait);
    return {..._restored};
  }

  void _finish(String productId, PurchaseResult result) => _waiting.remove(productId)?.complete(result);

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      try {
        await _handle(p);
      } catch (e) {
        // 發放失敗就不通知商店交易完成，下次開啟商店會再送一次
        debugPrint('處理購買失敗：${p.productID} $e');
        _finish(p.productID, PurchaseResult.failed);
      }
    }
  }

  Future<void> _handle(PurchaseDetails p) async {
    switch (p.status) {
      case PurchaseStatus.pending:
        _finish(p.productID, PurchaseResult.pending);
        return; // 還沒付款完成，不能通知交易完成
      case PurchaseStatus.purchased:
        final id = p.purchaseID ?? '${p.productID}@${p.transactionDate}';
        if (!_store.isPurchaseDelivered(id)) {
          await deliverPurchase(_store, p.productID);
          await _store.markPurchaseDelivered(id);
          if (!_waiting.containsKey(p.productID)) _later.add(p.productID);
        }
        _finish(p.productID, PurchaseResult.success);
      case PurchaseStatus.restored:
        _restored.add(p.productID);
        await restoreNonConsumable(_store, p.productID);
      case PurchaseStatus.canceled:
        _finish(p.productID, PurchaseResult.cancelled);
      case PurchaseStatus.error:
        debugPrint('購買錯誤：${p.productID} ${p.error?.code} ${p.error?.message}');
        _finish(p.productID, PurchaseResult.failed);
    }
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _later.close();
  }
}
