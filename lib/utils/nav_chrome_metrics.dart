/// 记录全局导航栏在宽屏布局中应预留的宽度。
///
/// Master-Detail 的断点使用整窗 [MediaQuery]，但实际内容区还要扣掉侧边
/// Rail。这里由 AdaptiveScaffold 写入 Rail 形态宽度，让布局判定与最终
/// 分配空间保持同一口径。
class NavChromeMetrics {
  NavChromeMetrics._();

  static double railWidth = 72.0;

  static double reservedWidth({required bool showRailByBreakpoint}) {
    return showRailByBreakpoint ? railWidth : 0.0;
  }
}
