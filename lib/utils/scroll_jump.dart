import 'package:flutter/rendering.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// 已渲染目标的瞬时定位（替代 scroll_to_index 的 1ms animateTo）。
extension AutoScrollJump on AutoScrollController {
  /// 顶对齐跳到已渲染的 [scrollIndex]；几何测不到时回退 scrollToIndex。
  ///
  /// 1ms animateTo 仍会产生动画速度。若落点附近重新布局导致
  /// maxScrollExtent 收缩，滚动物理会暂时保留越界位置，动画结束后再
  /// 弹回。已渲染目标可直接测量并 jumpTo，避免留下这段动画窗口。
  Future<void> jumpToRenderedScrollIndex(int scrollIndex) async {
    final offset = topAlignOffsetForScrollIndex(scrollIndex);
    if (offset == null) {
      await scrollToIndex(
        scrollIndex,
        preferPosition: AutoScrollPosition.begin,
        duration: const Duration(milliseconds: 1),
      );
      return;
    }

    jumpTo(offset.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  /// [scrollIndex] 顶对齐视口顶部所需的滚动位置；无法测量时返回 null。
  double? topAlignOffsetForScrollIndex(int scrollIndex) {
    if (!hasClients) return null;

    final context = tagMap[scrollIndex]?.context;
    if (context == null || !context.mounted) return null;

    final RenderObject? renderObject;
    try {
      renderObject = context.findRenderObject();
    } catch (_) {
      return null;
    }
    if (renderObject == null || !renderObject.attached) return null;
    if (renderObject is RenderBox && !renderObject.hasSize) return null;

    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(renderObject, 0).offset;
  }
}
