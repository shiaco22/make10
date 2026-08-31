import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 画面の向き（縦向き固定 or 自由回転）の決定は Make10App.build() 側で行う
  // （仕様 §9.2）。ここではまだ MediaQuery が存在せず、電話かタブレットかを
  // 判定する基準（ビューポートの短辺）を読めないため。
  runApp(const ProviderScope(child: Make10App()));
}
