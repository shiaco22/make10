import 'package:flutter/material.dart';

import 'home_screen.dart';

class Make10App extends StatelessWidget {
  const Make10App({super.key});

  static const Color _seedColor = Colors.indigo;

  /// アプリの実際のライトテーマ。build() と、テスト側が「実物のテーマ」を
  /// 手で組み直さずに参照できるよう、トップレベルの定数として公開する。
  static final ThemeData lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    useMaterial3: true,
  );

  /// 同じシード色から作るダークテーマ。
  static final ThemeData darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAKE 10',
      theme: lightTheme,
      // themeMode は既定 (ThemeMode.system) のままにして、明暗はシステム
      // 設定に委ねる。
      darkTheme: darkTheme,
      home: const HomeScreen(),
    );
  }
}
