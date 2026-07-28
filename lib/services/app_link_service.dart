import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用链接解析结果
class AppLinkInfo {
  /// 是否能解析到目标应用
  final bool canResolve;

  /// 应用名称（仅 Android 可获取）
  final String? appName;

  /// 包名（仅 Android）
  final String? packageName;

  /// 应用图标 PNG 字节（仅 Android 可获取）
  final Uint8List? appIcon;

  const AppLinkInfo({
    required this.canResolve,
    this.appName,
    this.packageName,
    this.appIcon,
  });

  @override
  String toString() =>
      'AppLinkInfo(canResolve=$canResolve, appName=$appName, '
      'packageName=$packageName, iconBytes=${appIcon?.length ?? 0})';
}

/// 应用链接服务
///
/// 通过 Android MethodChannel 解析和启动应用链接。
/// 使用 PackageManager 获取目标应用名称、包名和图标。
class AppLinkService {
  static const _channel = MethodChannel('com.github.lingyan000.fluxdo/browser');

  /// 解析应用链接，获取目标应用信息
  static Future<AppLinkInfo> resolveAppLink(String url) async {
    debugPrint('[AppLink] resolveAppLink: $url');
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'resolveAppLink',
        {'url': url},
      );
      debugPrint('[AppLink] native result: $result');
      if (result != null) {
        final info = AppLinkInfo(
          canResolve: result['canResolve'] as bool? ?? false,
          appName: result['appName'] as String?,
          packageName: result['packageName'] as String?,
          appIcon: result['appIcon'] as Uint8List?,
        );
        debugPrint('[AppLink] parsed: $info');
        return info;
      }
    } catch (e) {
      debugPrint('[AppLink] resolveAppLink error: $e');
    }
    return const AppLinkInfo(canResolve: false);
  }

  /// 启动应用链接
  ///
  /// 优先通过 Android MethodChannel 启动，失败时回退到 url_launcher。
  static Future<bool> launchAppLink(String url) async {
    // 1. 尝试原生 MethodChannel
    try {
      final result = await _channel.invokeMethod<bool>('launchAppLink', {
        'url': url,
      });
      if (result == true) return true;
    } catch (_) {
      // 原生 channel 调用失败，继续使用 Android 外部应用启动兜底。
    }

    // 2. 回退到 url_launcher
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
