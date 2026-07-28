import 'package:flutter/foundation.dart';

/// 平台工具类 — 统一平台检测逻辑
class PlatformUtils {
  PlatformUtils._();

  @visibleForTesting
  static bool? debugDesktopOverride;

  /// 生产环境只支持 Android；测试可临时覆盖布局模式。
  static bool get isDesktop => debugDesktopOverride ?? false;

  static bool get isMobile => !(debugDesktopOverride ?? false);
}
