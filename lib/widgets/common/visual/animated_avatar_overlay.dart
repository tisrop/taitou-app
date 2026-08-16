import 'package:flutter/material.dart';

import '../../../services/discourse_cache_manager.dart';

/// 动图头像播放 overlay:压在静态首帧之上的圆形动图层。
///
/// ready(下载 gif 原件 + 全帧 Rust 解码,首次可达数百 ms)之前完全
/// 透明 —— 底下的静态模板小图(几 KB 秒出)先顶住观感,ready 后原位
/// 开始播放;出错保持透明,底图兜底。RepaintBoundary 把逐帧重绘限制
/// 在头像小区域。
///
/// [onReadyChanged] 供宿主收起静态打底层:透明 gif 的帧挡不住底图,
/// 静态层若一直垫着,会从透明像素后面透出来,呈现“静态+动态双影”。
class AnimatedAvatarOverlay extends StatefulWidget {
  const AnimatedAvatarOverlay({
    super.key,
    required this.url,
    this.onReadyChanged,
  });

  /// 动画头像原件 URL(gif 全文件)
  final String url;

  /// 首帧就绪(true)/回退(false)通知。
  final ValueChanged<bool>? onReadyChanged;

  @override
  State<AnimatedAvatarOverlay> createState() => _AnimatedAvatarOverlayState();
}

class _AnimatedAvatarOverlayState extends State<AnimatedAvatarOverlay> {
  bool _reportedReady = false;

  void _reportReady(bool ready) {
    if (ready == _reportedReady) return;
    _reportedReady = ready;
    if (widget.onReadyChanged == null) return;

    // frameBuilder/errorBuilder 在 build 期间执行，宿主可能在回调中
    // setState，因此延迟到帧末；状态已再次变化时丢弃过期通知。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedReady == ready) {
        widget.onReadyChanged?.call(ready);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedAvatarOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _reportReady(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipOval(
        child: Image(
          image: discourseImageProvider(widget.url),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSync) {
            final ready = wasSync || frame != null;
            _reportReady(ready);
            return ready ? child : const SizedBox.expand();
          },
          errorBuilder: (_, _, _) {
            _reportReady(false);
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }
}

/// 静态打底 + 动图 overlay 的组合；动图首帧就绪后收起静态层。
class AnimatedAvatarStack extends StatefulWidget {
  const AnimatedAvatarStack({
    super.key,
    required this.animatedUrl,
    required this.base,
    required this.size,
  });

  final String animatedUrl;
  final Widget base;
  final double size;

  @override
  State<AnimatedAvatarStack> createState() => _AnimatedAvatarStackState();
}

class _AnimatedAvatarStackState extends State<AnimatedAvatarStack> {
  bool _animatedReady = false;

  @override
  void didUpdateWidget(covariant AnimatedAvatarStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animatedUrl != widget.animatedUrl) {
      _animatedReady = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_animatedReady) widget.base,
          AnimatedAvatarOverlay(
            url: widget.animatedUrl,
            onReadyChanged: (ready) {
              if (ready != _animatedReady) {
                setState(() => _animatedReady = ready);
              }
            },
          ),
        ],
      ),
    );
  }
}
