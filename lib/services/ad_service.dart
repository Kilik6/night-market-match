import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 遊戲用到的廣告功能。畫面只依賴這個介面，測試時可以換成假的。
abstract class AdService {
  /// 播放獎勵型廣告。看完拿到獎勵回傳 true；沒有廣告可播或中途關掉回傳 false。
  Future<bool> showRewarded();

  /// 播放插頁式廣告（沒有準備好就直接略過）。
  Future<void> showInterstitial();
}

/// 廣告隱私權選項：歐洲等地區依法要讓玩家隨時可以改變廣告同意的選擇（設定頁用）。
abstract class AdPrivacy {
  /// 玩家所在地區需要提供「廣告隱私權設定」入口。
  bool get privacyOptionsRequired;

  /// 打開 Google 的廣告同意表單，讓玩家重新選擇。
  Future<void> showPrivacyOptions();
}

/// 廣告單元 ID：正式版（release）用自己 AdMob 帳號的 ID 才有收益；
/// debug 版（開發、模擬器）一律用 Google 官方的測試 ID，避免開發時點到自己的正式廣告被判無效流量。
abstract final class AdUnitIds {
  static String get rewarded => kReleaseMode
      ? (Platform.isIOS ? 'ca-app-pub-3699832160827795/9913475340' : 'ca-app-pub-3699832160827795/7018176707')
      : (Platform.isIOS ? 'ca-app-pub-3940256099942544/1712485313' : 'ca-app-pub-3940256099942544/5224354917');

  static String get interstitial => kReleaseMode
      ? (Platform.isIOS ? 'ca-app-pub-3699832160827795/6852197733' : 'ca-app-pub-3699832160827795/8058514371')
      : (Platform.isIOS ? 'ca-app-pub-3940256099942544/4411468910' : 'ca-app-pub-3940256099942544/1033173712');
}

/// 串接 Google AdMob 的實作：啟動時先取得廣告同意，再預載廣告，播完再自動載入下一則。
///
/// 同意流程（Google UMP）：歐洲、英國等地區的玩家第一次開啟時會看到 Google 的同意表單
/// （表單內容在 AdMob「隱私權與訊息」設定）；其他地區不會跳出。iPhone 接著詢問是否允許追蹤（ATT）。
/// 玩家拒絕個人化廣告時仍可以播一般廣告，只有完全不能請求廣告時才不載入。
class AdMobService implements AdService, AdPrivacy {
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  bool _started = false;
  bool _privacyOptionsRequired = false;

  /// debug 版用 `--dart-define=CONSENT_EEA=true` 假裝在歐洲，測試同意表單會不會跳出；
  /// 實體手機或模擬器要再用 `--dart-define=CONSENT_TEST_DEVICE=<雜湊 ID>` 設成測試裝置（ID 在 logcat 的 UserMessagingPlatform 訊息裡）。
  static const _debugEea = bool.fromEnvironment('CONSENT_EEA');
  static const _testDevice = String.fromEnvironment('CONSENT_TEST_DEVICE');

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// App 畫面出來後呼叫（同意表單要蓋在畫面上）。
  Future<void> init() async {
    await _gatherConsent();
    await _requestTracking();
    _privacyOptionsRequired = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    await _startIfAllowed();
  }

  /// 更新同意狀態，需要的話跳出 Google 的同意表單。網路失敗等錯誤都不擋遊戲。
  Future<void> _gatherConsent() async {
    // 測試歐洲模式時每次都從頭來，才看得到第一次開啟的表單
    if (kDebugMode && _debugEea) await ConsentInformation.instance.reset();
    final done = Completer<void>();
    final params = ConsentRequestParameters(
      consentDebugSettings: kDebugMode && _debugEea
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: [if (_testDevice.isNotEmpty) _testDevice],
            )
          : null,
    );
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        // 上次已經同意過的話，不用等表單就可以先開始載廣告
        await _startIfAllowed();
        if (kDebugMode) debugPrint('廣告同意狀態：${await ConsentInformation.instance.getConsentStatus()}');
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('廣告同意表單：${error.errorCode} ${error.message}');
          if (!done.isCompleted) done.complete();
        });
      },
      (error) {
        debugPrint('廣告同意資訊更新失敗：${error.errorCode} ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
  }

  /// iPhone：還沒問過的話，詢問是否允許追蹤（系統一輩子只會問一次）。
  Future<void> _requestTracking() async {
    if (!Platform.isIOS) return;
    try {
      if (await AppTrackingTransparency.trackingAuthorizationStatus == TrackingStatus.notDetermined) {
        // 剛關掉同意表單時 App 可能還不在前景，等一下系統視窗才跳得出來
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      debugPrint('追蹤權限詢問失敗：$e');
    }
  }

  /// 可以請求廣告才初始化 SDK 並預載（只做一次）。
  Future<void> _startIfAllowed() async {
    if (_started || !await ConsentInformation.instance.canRequestAds()) return;
    _started = true;
    await MobileAds.instance.initialize();
    _loadRewarded();
    _loadInterstitial();
  }

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('廣告隱私權選項：${error.errorCode} ${error.message}');
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    // 改完選擇後如果變成可以請求廣告，開始載入
    await _startIfAllowed();
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
