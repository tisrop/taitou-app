import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';
import 'png_encoder.dart';
import 'share_utils.dart';

/// Widget 截图工具类
class ScreenshotUtils {
  ScreenshotUtils._();

  /// GPU 最大纹理尺寸安全上限（保守值，兼容低端设备）
  static const int _maxTextureSize = 4096;

  /// 截取 Widget 为图片字节
  /// [key] - Widget 的 GlobalKey（需要包裹在 RepaintBoundary 中）
  /// [pixelRatio] - 像素比率，默认 2.0（参考 linuxdo-scripts）
  ///
  /// 内部自动判断：纹理尺寸未超限时直接截图，超限时分块截图拼接，
  /// 始终保持原始 pixelRatio，不降低画质。
  static Future<Uint8List?> captureWidget(GlobalKey key, {double pixelRatio = 2.0}) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[ScreenshotUtils] RenderRepaintBoundary not found');
        return null;
      }

      final widgetWidth = boundary.size.width;
      final widgetHeight = boundary.size.height;
      final textureWidth = widgetWidth * pixelRatio;
      final textureHeight = widgetHeight * pixelRatio;

      // 纹理尺寸未超限，直接截图
      if (textureWidth <= _maxTextureSize && textureHeight <= _maxTextureSize) {
        debugPrint('[ScreenshotUtils] 直接截图 (${widgetWidth}x$widgetHeight @ $pixelRatio)');
        return _captureDirectly(boundary, pixelRatio);
      }

      // 纹理超限，分块截图拼接，保持原始 pixelRatio
      debugPrint('[ScreenshotUtils] 分块截图 (${widgetWidth}x$widgetHeight @ $pixelRatio)');
      return _captureInChunks(boundary, pixelRatio);
    } catch (e) {
      debugPrint('[ScreenshotUtils] captureWidget error: $e');
      return null;
    }
  }

  /// 直接截图（用于纹理尺寸不超限的情况）
  static Future<Uint8List?> _captureDirectly(RenderRepaintBoundary boundary, double pixelRatio) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('[ScreenshotUtils] Failed to get byte data');
        return null;
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// 分块截图拼接（用于超长帖）
  /// 在 CPU 端用 [PngEncoder] 拼接各块的 RGBA 像素,避免最终合成时再次触碰
  /// GPU 纹理限制。各块像素逐行 memcpy 到全幅画布。
  static Future<Uint8List?> _captureInChunks(RenderRepaintBoundary boundary, double pixelRatio) async {
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer) {
      debugPrint('[ScreenshotUtils] layer is not OffsetLayer');
      return null;
    }

    final widgetWidth = boundary.size.width;
    final widgetHeight = boundary.size.height;
    // 每块的最大逻辑高度（确保每块纹理高度不超限）
    final chunkLogicalHeight = (_maxTextureSize / pixelRatio).floorToDouble();
    final chunkCount = (widgetHeight / chunkLogicalHeight).ceil();

    final totalPixelWidth = (widgetWidth * pixelRatio).ceil();
    final totalPixelHeight = (widgetHeight * pixelRatio).ceil();

    debugPrint('[ScreenshotUtils] 分块截图：$chunkCount 块，每块逻辑高度 $chunkLogicalHeight');

    // CPU 端画布:RGBA8888,逐行 memcpy 各块像素
    final fullCanvas = Uint8List(totalPixelWidth * totalPixelHeight * 4);
    final rowBytes = totalPixelWidth * 4;

    for (int i = 0; i < chunkCount; i++) {
      final top = i * chunkLogicalHeight;
      final height = (top + chunkLogicalHeight > widgetHeight)
          ? widgetHeight - top
          : chunkLogicalHeight;

      final bounds = Rect.fromLTWH(0, top, widgetWidth, height);
      final chunkImage = await layer.toImage(bounds, pixelRatio: pixelRatio);

      try {
        final byteData = await chunkImage.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) continue;

        final chunkPixelWidth = chunkImage.width;
        final chunkPixelHeight = chunkImage.height;
        final pixels = byteData.buffer.asUint8List();
        final yOffset = (top * pixelRatio).round();
        final chunkRowBytes = chunkPixelWidth * 4;

        // 逐行 memcpy(宽度一致时整行拷贝;若块宽度因取整略小则按块宽拷)
        final copyWidth = chunkPixelWidth < totalPixelWidth ? chunkPixelWidth : totalPixelWidth;
        final copyBytes = copyWidth * 4;
        for (int y = 0; y < chunkPixelHeight; y++) {
          final destY = yOffset + y;
          if (destY >= totalPixelHeight) break;
          final srcOffset = y * chunkRowBytes;
          final dstOffset = destY * rowBytes;
          fullCanvas.setRange(dstOffset, dstOffset + copyBytes, pixels, srcOffset);
        }
      } finally {
        chunkImage.dispose();
      }
    }

    // CPU 端编码为 PNG
    return const PngEncoder().encodeRgba(fullCanvas, totalPixelWidth, totalPixelHeight);
  }

  /// 保存图片到相册
  /// 复用 image_viewer_page.dart 的保存逻辑
  static Future<bool> saveToGallery(Uint8List bytes, {String? filename}) async {
    try {
      // 检查权限
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          return false;
        }
      }

      // 生成文件名
      final name = filename ?? 'fluxdo_share_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(bytes, name: '$name.png');
      return true;
    } on GalException catch (e) {
      debugPrint('[ScreenshotUtils] saveToGallery GalException: ${e.type.message}');
      return false;
    } catch (e) {
      debugPrint('[ScreenshotUtils] saveToGallery error: $e');
      return false;
    }
  }

  /// 分享图片
  static Future<void> shareImage(Uint8List bytes, {String? filename}) async {
    try {
      // 创建临时文件
      final tempDir = await getTemporaryDirectory();
      final name = filename ?? 'fluxdo_share_${DateTime.now().millisecondsSinceEpoch}';
      final file = File('${tempDir.path}/$name.png');
      await file.writeAsBytes(bytes);

      // 分享
      final xFile = XFile(file.path, mimeType: 'image/png');
      await ShareUtils.shareOrSaveFile(xFile);
    } catch (e) {
      debugPrint('[ScreenshotUtils] shareImage error: $e');
      rethrow;
    }
  }
}
