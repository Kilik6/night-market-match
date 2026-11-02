import 'package:flutter/material.dart';

import 'screens/game_screen.dart';

/// 程式進入點，對應 React Native 版的 index.js（AppRegistry.registerComponent）。
void main() {
  runApp(const NightMarketMatchApp());
}

class NightMarketMatchApp extends StatelessWidget {
  const NightMarketMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FC Matching Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const GameScreen(),
    );
  }
}
