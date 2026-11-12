import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/ad_service.dart';
import 'services/progress_store.dart';
import 'services/purchase_service.dart';
import 'services/sound_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.load();
  final ads = AdMobService();
  ads.init(); // 不等廣告載入完，先讓畫面出來
  final sounds = AudioSoundService(muted: store.muted, musicOn: store.musicOn);
  // 音效在開場動畫播放時載入，動畫播完、音效也好了才進首頁
  final soundsReady = sounds.init();
  // 儲值目前用開發測試的假商店（只有 debug 版會成功），之後換成串接 App Store／Google Play 的版本
  final purchases = DevPurchaseService();
  runApp(NightMarketMatchApp(store: store, ads: ads, sounds: sounds, purchases: purchases, loading: soundsReady));
}

class NightMarketMatchApp extends StatefulWidget {
  const NightMarketMatchApp({
    super.key,
    required this.store,
    required this.ads,
    required this.sounds,
    required this.purchases,
    this.loading,
  });

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        next: (_) => HomeScreen(store: widget.store, ads: widget.ads, sounds: widget.sounds, purchases: widget.purchases),
      ),
    );
  }
}
