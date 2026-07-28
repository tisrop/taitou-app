/// 选区放大镜 —— 拖拽手柄时显示放大预览,看清手指下的字。
///
/// 使用 Flutter SDK 的 Android Material [TextMagnifier] 配置。
/// 视觉与跟随动画由 SDK 组件管理，本类只负责喂 [MagnifierInfo] 四字段
/// 并管理 [MagnifierController] 的 show/hide。
library;

import 'package:flutter/material.dart';

class SelectionMagnifier {
  SelectionMagnifier(this.context);

  final BuildContext context;

  final MagnifierController _controller = MagnifierController();

  /// Android TextMagnifier 会监听它重定位，show 后只需更新 value。
  final ValueNotifier<MagnifierInfo> _info = ValueNotifier<MagnifierInfo>(
    MagnifierInfo.empty,
  );

  bool get isShowing => _controller.overlayEntry != null;

  /// 显示/更新放大镜。
  ///
  /// - [gestureGlobal]:拖拽点全局坐标，镜子 X 跟随它。
  /// - [caretRect]:被拖端点的 caret 全局矩形(焦点锁其**行中心**,对齐 SDK
  ///   MagnifierInfo.caretRect —— 焦点指文字,不指手指)。
  /// - [currentLineBoundaries]:被拖端所在行的全局矩形(Material 镜子 X 夹在
  ///   行首尾之间)。
  /// - [fieldBounds]:内容区全局矩形(Material 焦点 X 不出内容区)。
  /// - [below]:插到该 OverlayEntry 之下，使镜内不映出拖拽手柄。
  void show({
    required Offset gestureGlobal,
    required Rect caretRect,
    required Rect currentLineBoundaries,
    required Rect fieldBounds,
    OverlayEntry? below,
  }) {
    _info.value = MagnifierInfo(
      globalGesturePosition: gestureGlobal,
      caretRect: caretRect,
      currentLineBoundaries: currentLineBoundaries,
      fieldBounds: fieldBounds,
    );
    if (_controller.overlayEntry != null) return; // 已在 overlay,listener 自更

    // 使用 SDK 的 Android Material 放大镜配置。
    final magnifier = TextMagnifier.adaptiveMagnifierConfiguration
        .magnifierBuilder(context, _controller, _info);
    if (magnifier == null) return;

    _controller.show(
      context: context,
      below:
          TextMagnifier
              .adaptiveMagnifierConfiguration
              .shouldDisplayHandlesInMagnifier
          ? null
          : below,
      builder: (_) => magnifier,
    );
  }

  void hide() {
    if (_controller.overlayEntry == null) return;
    _controller.hide();
  }
}
