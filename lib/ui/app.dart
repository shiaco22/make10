import 'package:flutter/material.dart';

import 'home_screen.dart';

class Make10App extends StatelessWidget {
  const Make10App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAKE 10',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // 同じシード色からダークパレットを作る。themeMode は既定
      // (ThemeMode.system) のままにして、明暗はシステム設定に委ねる。
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
