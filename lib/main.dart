import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/ad_service.dart';
import 'services/progress_store.dart';
import 'services/purchase_service.dart';
import 'services/reminder_service.dart';
import 'services/sound_service.dart';
import 'services/store_purchase_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.load();
  final ads = AdMobService();
  final sounds = AudioSoundService(
    muted: store.muted,
    musicOn: store.musicOn,
    musicVolume: store.musicVolume(defaultMusicVolume),
    sfxVolume: store.sfxVolume(defaultSfxVolume),
  );
  // 音效在開場動畫播放時載入，動畫播完、音效也好了才進首頁
  final soundsReady = sounds.init();
  // 儲值：正式版串接 App Store／Google Play；debug 版用假商店（不會扣款），
  // 要在 debug 版測真的商店時加 --dart-define=REAL_STORE=true
  final PurchaseService purchases;
  if (kReleaseMode || const bool.fromEnvironment('REAL_STORE')) {
    final storePurchases = StorePurchaseService(store);
    storePurchases.init(); // 先聽購買串流，才收得到上次沒處理完的付款；不等商品載入
    purchases = storePurchases;
  } else {
    purchases = DevPurchaseService();
  }
  // 每日提醒：設定時區和通知（不會跳權限詢問），有開提醒的話依今天的進度重排
  final reminders = LocalReminderService();
  reminders.init().then((_) {
    if (store.reminderOn) reminders.reschedule(store);
  });
  runApp(NightMarketMatchApp(
    store: store,
    ads: ads,
    sounds: sounds,
    purchases: purchases,
    reminders: reminders,
    loading: soundsReady,
  ));
  // 畫面出來後才取得廣告同意（歐洲等地區會跳出 Google 的同意表單）、載入廣告，不擋開場動畫
  ads.init();
}

class NightMarketMatchApp extends StatefulWidget {
  const NightMarketMatchApp({
    super.key,
    required this.store,
    required this.ads,
    required this.sounds,
    required this.purchases,
    this.reminders,
    this.loading,
  });

  final ReminderService? reminders;

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

  /// 開場動畫期間要等完的載入工作。
  final Future<void>? loading;
  final PurchaseService purchases;

  @override
  State<NightMarketMatchApp> createState() => _NightMarketMatchAppState();
}

class _NightMarketMatchAppState extends State<NightMarketMatchApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _deliveredLater;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 晚到的付款（App 中途被關掉、待處理付款完成）發放後提示玩家
    final purchases = widget.purchases;
    if (purchases is StorePurchaseService) {
      _deliveredLater = purchases.deliveredLater.listen((_) {
        _messenger.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('購買完成，商品已經發放囉！')));
      });
    }
  }

  @override
  void dispose() {
    _deliveredLater?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App 切到背景時停音樂（Android 不會自動停），回來時恢復。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.sounds.resumeMusic();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      widget.sounds.pauseMusic();
      // 離開 App 時依最新進度重排提醒（例如已經簽到了，就改成明天提醒）
      if (widget.store.reminderOn) widget.reminders?.reschedule(widget.store);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messenger,
      title: '夜市翻牌',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: NightColors.night,
        colorScheme: ColorScheme.fromSeed(
          seedColor: NightColors.lantern,
          brightness: Brightness.dark,
        ),
      ),
      home: SplashScreen(
        loading: widget.loading,
        next: (_) => HomeScreen(
          store: widget.store,
          ads: widget.ads,
          sounds: widget.sounds,
          purchases: widget.purchases,
          reminders: widget.reminders,
        ),
      ),
    );
  }
}
