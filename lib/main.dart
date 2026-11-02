import 'package:flutter/material.dart';

import 'screens/game_screen.dart';
import 'theme.dart';

void main() {
  runApp(const NightMarketMatchApp());
}

class NightMarketMatchApp extends StatelessWidget {
  const NightMarketMatchApp({super.key});

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
      home: const GameScreen(),
    );
  }
}
