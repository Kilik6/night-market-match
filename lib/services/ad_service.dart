import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 遊戲用到的廣告功能。畫面只依賴這個介面，測試時可以換成假的。
abstract class AdService {
  /// 播放獎勵型廣告。看完拿到獎勵回傳 true；沒有廣告可播或中途關掉回傳 false。
  Future<bool> showRewarded();

  /// 播放插頁式廣告（沒有準備好就直接略過）。
  Future<void> showInterstitial();
}

/// 廣告單元 ID。目前全部是 Google 官方的測試用 ID，
/// 上架前要換成自己 AdMob 帳號裡建立的 ID，否則不會有收益。
abstract final class AdUnitIds {
  static String get rewarded => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  static String get interstitial => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';
}

/// 串接 Google AdMob 的實作：啟動時先預載廣告，播完再自動載入下一則。
class AdMobService implements AdService {
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;

  Future<void> init() async {
    await MobileAds.instance.initialize();
    _loadRewarded();
    _loadInterstitial();
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (error) {
          debugPrint('獎勵型廣告載入失敗：$error');
          _rewarded = null;
          Future.delayed(const Duration(seconds: 30), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) {
          debugPrint('插頁式廣告載入失敗：$error');
          _interstitial = null;
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  @override
  Future<bool> showRewarded() {
    final ad = _rewarded;
    if (ad == null) return Future.value(false);
    _rewarded = null;

    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }

  @override
  Future<void> showInterstitial() {
    final ad = _interstitial;
    if (ad == null) return Future.value();
    _interstitial = null;

    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
    );
    ad.show();
    return done.future;
  }
}
