import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cookie_full_info.dart';

/// 通过原生平台通道写入 / 读取 / 删除 WebView cookie store。
///
/// 保留完整的 cookie 语义（host-only / domain / sameSite 等）。
///
/// v0.4.0 扩展：增加 [nukeAllVariants] / [deleteExactCookie] /
/// [getAllCookieInfos] / [countCookiesByName] 用于 Sentinel 内核（参见
/// `docs/cookie-sync-design-v0.4.0.md` §5.4）。
///
/// 通过 Android native method channel `com.fluxdo/raw_cookie` 实现。
class RawCookieWriter {
  RawCookieWriter._();
  static final instance = RawCookieWriter._();

  static const _channel = MethodChannel('com.fluxdo/raw_cookie');
  static const _sharedStorageIsolatedCookieNames = {
    'cf_clearance',
    '_t',
    '_forum_session',
  };

  bool get isSupported => true;

  /// 通过原始 Set-Cookie 头字符串写入 cookie。
  ///
  /// [url] — cookie 所属的站点 URL
  /// [rawSetCookie] — 原始 Set-Cookie 头（如 `_t=xxx; path=/; secure; httponly`）
  ///
  /// Android 原生实现调用 `CookieManager.setCookie(url, rawSetCookie)`。
  Future<bool> setRawCookie(
    String url,
    String rawSetCookie, {
    bool writeSharedStorage = true,
  }) async {
    final effectiveWriteSharedStorage = _effectiveSharedStorageWrite(
      url,
      rawSetCookie,
      requested: writeSharedStorage,
    );
    try {
      final result = await _channel.invokeMethod<bool>('setRawCookie', {
        'url': url,
        'rawSetCookie': rawSetCookie,
        'writeSharedStorage': effectiveWriteSharedStorage,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] setRawCookie failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return false;
    }
  }

  bool _effectiveSharedStorageWrite(
    String url,
    String rawSetCookie, {
    required bool requested,
  }) {
    if (!requested) return false;

    final name = _cookieNameFromRawHeader(url, rawSetCookie);
    if (name == null) return requested;
    return !_sharedStorageIsolatedCookieNames.contains(name.toLowerCase());
  }

  String? _cookieNameFromRawHeader(String url, String rawSetCookie) {
    try {
      return SetCookieParser.parse(rawSetCookie, uri: Uri.parse(url)).name;
    } catch (_) {
      final separator = rawSetCookie.indexOf('=');
      if (separator <= 0) return null;
      final name = rawSetCookie.substring(0, separator).trim();
      return name.isEmpty ? null : name;
    }
  }

  /// 批量写入多个 raw Set-Cookie 头。
  Future<int> setRawCookies(String url, List<String> rawSetCookies) async {
    var written = 0;
    for (final raw in rawSetCookies) {
      if (await setRawCookie(url, raw)) written++;
    }
    return written;
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 新增：Sentinel 内核所需的原语
  //
  // 原生侧实现详见 §8.4。Phase 1 阶段 Dart 通道已包装，原生侧 Phase 2 实现。
  // 待原生侧实现前，调用返回安全默认值（不抛异常）。
  // ---------------------------------------------------------------------------

  /// 暴力穷举删除指定 name 的所有变体。
  ///
  /// 仅供 Sentinel 在 Android 上"无法精确枚举变体"时使用。
  /// 对每对 `(domain, path)` 组合发出 `Max-Age=0` 删除请求。
  ///
  /// [domainCandidates] — null 表示尝试 host-only（不传 Domain 属性）
  ///
  /// 返回成功删除的变体数（best-effort，原生侧可能无法精确统计）。
  ///
  /// 验证项：V4（Android Max-Age=0 + Domain 精确匹配实测）。
  Future<int> nukeAllVariants({
    required String url,
    required String name,
    required List<String?> domainCandidates,
    required List<String> pathCandidates,
  }) async {
    try {
      final result = await _channel.invokeMethod<int>('nukeAllVariants', {
        'url': url,
        'name': name,
        'domainCandidates': domainCandidates,
        'pathCandidates': pathCandidates,
      });
      return result ?? 0;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] nukeAllVariants failed: $e');
      return 0;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return 0;
    }
  }

  /// 精确删除指定 `(name, domain, path)` 的单条 cookie 变体。
  ///
  /// Android 退化为 `nukeAllVariants` 的单组合调用，domain/path 必须与设置时一致。
  Future<bool> deleteExactCookie({
    required String url,
    required String name,
    required String? domain,
    required String path,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('deleteExactCookie', {
        'url': url,
        'name': name,
        'domain': domain,
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] deleteExactCookie failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return false;
    }
  }

  /// 读取指定 url 下所有 cookie 的完整信息。
  ///
  /// 新版 Android WebView 通过 `WebViewCompat.getCookieInfo` 返回完整字段；
  /// 旧版 WebView 只能返回 name + value。
  ///
  /// 验证项：V12（flutter_inappwebview Android getCookies 实际行为）。
  Future<List<CookieFullInfo>> getAllCookieInfos(String url) async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'getAllCookieInfos',
        {'url': url},
      );
      if (raw == null) return const [];
      return raw
          .map((m) {
            final map = Map<String, dynamic>.from(m);
            return CookieFullInfo(
              name: map['name'] as String? ?? '',
              value: map['value'] as String? ?? '',
              domain: map['domain'] as String?,
              path: map['path'] as String?,
              isSecure: map['isSecure'] as bool?,
              isHttpOnly: map['isHttpOnly'] as bool?,
              expiresMillis: map['expiresMillis'] as int?,
              sameSite: map['sameSite'] as String?,
              isPartitioned: map['partitioned'] as bool?,
            );
          })
          .toList(growable: false);
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] getAllCookieInfos failed: $e');
      return const [];
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return const [];
    }
  }

  /// 统计指定 url 下 cookie name 的变体数量。
  ///
  /// 基于 Android `CookieManager.getCookie(url)` 拼接字符串拆分计数。
  ///
  /// 比 [getAllCookieInfos] 更轻量，仅返回数量不返回内容。
  Future<int> countCookiesByName(String url, String name) async {
    try {
      final result = await _channel.invokeMethod<int>('countCookiesByName', {
        'url': url,
        'name': name,
      });
      return result ?? 0;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] countCookiesByName failed: $e');
      return 0;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return 0;
    }
  }
}
