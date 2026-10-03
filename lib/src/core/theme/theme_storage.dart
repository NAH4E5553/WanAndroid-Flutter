import 'package:flutter/material.dart' show ThemeMode;
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

typedef ThemeSelection = ({WanPalette palette, ThemeMode mode});

/// 持久化的外观选择。存储失败时抛出异常,以便调用方
/// 回滚可见状态,而不是报告虚假的成功。
abstract interface class ThemeStorage {
  Future<ThemeSelection?> read();

  /// 将 [palette] 与 [mode] 作为一个逻辑值持久化。
  Future<void> write(WanPalette palette, ThemeMode mode);
}
