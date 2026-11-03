import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/ad_service.dart';
import 'services/progress_store.dart';
import 'services/sound_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.load();
  final ads = AdMobService();
  ads.init(); // 不等廣告載入完，先讓畫面出來
  final sounds = AudioSoundService(muted: store.muted, musicOn: store.musicOn);
  sounds.init();
  runApp(NightMarketMatchApp(store: store, ads: ads, sounds: sounds));
}

class NightMarketMatchApp extends StatefulWidget {
  const NightMarketMatchApp({super.key, required this.store, required this.ads, required this.sounds});

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

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
      home: HomeScreen(store: widget.store, ads: widget.ads, sounds: widget.sounds),
    );
  }
}
