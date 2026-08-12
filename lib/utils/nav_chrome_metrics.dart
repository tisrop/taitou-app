import 'package:flutter/widgets.dart';

/// 提供当前上下文应预留的导航 chrome 宽度（侧边 Rail）。
///
/// 双栏判定使用整窗 [MediaQuery]，但内容区实际要扣掉侧边 Rail。
/// [NavChromeScope] 由 AdaptiveScaffold 挂载，只在其子树内生效；独立
/// push 路由（rootNavigator 新路由，不在 scaffold 的 Element 树内）读不到
/// scope，按无 Rail 处理，不再误读全局残留宽度。
class NavChromeScope extends InheritedWidget {
  const NavChromeScope({
    super.key,
    required this.railWidth,
    required super.child,
  });

  /// 当前 Rail 形态的宽度（collapsed 72 / extended 180）。
  final double railWidth;

  static NavChromeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NavChromeScope>();
  }

  @override
  bool updateShouldNotify(NavChromeScope oldWidget) {
    return railWidth != oldWidget.railWidth;
  }
}

/// 计算布局判定时应预留的 chrome 宽度。
///
/// [showRailByBreakpoint] 表示断点判定下侧边栏可见；实际是否要扣除宽度
/// 取决于当前上下文是否处于 [NavChromeScope] 内（即是否在
/// AdaptiveScaffold 的子树中）。
double navChromeReservedWidth(
  BuildContext context, {
  required bool showRailByBreakpoint,
}) {
  final scope = NavChromeScope.maybeOf(context);
  return showRailByBreakpoint && scope != null ? scope.railWidth : 0.0;
}
