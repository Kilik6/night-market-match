import 'package:flutter/material.dart';

import 'screens/game_screen.dart';
import 'services/ad_service.dart';
import 'services/progress_store.dart';
import 'services/sound_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.load();
  final ads = AdMobService();
  ads.init(); // 不等廣告載入完，先讓遊戲畫面出來
  final sounds = AudioSoundService(muted: store.muted);
  sounds.init();
  runApp(NightMarketMatchApp(store: store, ads: ads, sounds: sounds));
}

class NightMarketMatchApp extends StatelessWidget {
  const NightMarketMatchApp({super.key, required this.store, required this.ads, required this.sounds});

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

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
      home: GameScreen(store: store, ads: ads, sounds: sounds),
    );
  }
}
