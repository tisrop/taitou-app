import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:ua_client_hints/ua_client_hints.dart';

import 'config/site_customization.dart';
import 'config/sites/openxinsheng.dart';

/// 应用常量（仅支持 Android）。
class AppConstants {
  /// 当前站点自定义配置
  static final SiteCustomization siteCustomization = openxinshengCustomization;

  /// 是否启用 WebView Cookie 同步（启动时预热 WebView）
  /// 设为 false 时，不使用 WebView 同步，Cookie 由 Dio Set-Cookie 与本地存储维护
  static const bool enableWebViewCookieSync = false;

  static String? _cachedUserAgent;
  static final Completer<String> _uaCompleter = Completer<String>();
  static bool _uaInitialized = false;
  static Map<String, String>? _cachedClientHints;

  static final RegExp _nonAsciiRun = RegExp(r'[^\x00-\x7F]+');
  static const String asciiAppName = 'Taitou';

  static String sanitizeHeaderValue(String value) =>
      value.replaceAll(_nonAsciiRun, asciiAppName);

  /// 获取 Android WebView 的真实 UA，并移除暴露 WebView 身份的标识。
  static Future<void> initUserAgent() async {
    if (_uaInitialized) return;
    _uaInitialized = true;

    try {
      final webViewUA = await InAppWebViewController.getDefaultUserAgent();
      _cachedUserAgent = _sanitizeUserAgent(webViewUA);
      debugPrint('[AppConstants] WebView UA: $webViewUA');
      debugPrint('[AppConstants] Sanitized UA: $_cachedUserAgent');
    } catch (e) {
      debugPrint('[AppConstants] 获取 WebView UA 失败: $e');
      _cachedUserAgent = _buildDefaultUserAgent();
    }
    _uaCompleter.complete(_cachedUserAgent!);
    await _initClientHints();
  }

  static Future<void> _initClientHints() async {
    try {
      final hints = await userAgentClientHintsHeader();
      hints.remove('User-Agent');
      _cachedClientHints = {
        for (final entry in hints.entries)
          entry.key: sanitizeHeaderValue(entry.value),
      };
      debugPrint('[AppConstants] Client Hints: $_cachedClientHints');
    } catch (e) {
      debugPrint('[AppConstants] 获取 Client Hints 失败: $e');
    }
  }

  static Map<String, String>? get clientHints => _cachedClientHints;

  static String _sanitizeUserAgent(String ua) {
    var sanitized = ua.replaceAll(RegExp(r'[;\s]*\bwv\b[;\s]*(?=\))'), '');
    sanitized = sanitized.replaceAll(RegExp(r'Version/[^ ]+ *'), '');
    return sanitized;
  }

  static Future<String> getUserAgent() async {
    if (_cachedUserAgent != null) return _cachedUserAgent!;
    if (!_uaInitialized) await initUserAgent();
    return _uaCompleter.future;
  }

  static String get userAgent => _cachedUserAgent ?? _buildDefaultUserAgent();

  static String get webViewUserAgentOverride => userAgent;

  static String _buildDefaultUserAgent() =>
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  /// 站点主域名
  static const String baseUrl = 'https://openxinsheng.com';

  /// [baseUrl] 的 host（如 `openxinsheng.com`）。主域判定、deep link 匹配、
  /// cookie 归属都从这里取，避免各处再硬编码域名字面量。
  static final String baseHost = Uri.parse(baseUrl).host;

  /// host 是否属于本站：主域、`www.` 前缀或任意子域。
  static bool isSiteHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == baseHost ||
        normalized == 'www.$baseHost' ||
        normalized.endsWith('.$baseHost');
  }

  /// 是否显示「用户名 / 密码」应用内登录表单。
  ///
  /// openxinsheng.com 实测（2026-07-26，取自站点预载设置）：
  /// - `enable_local_logins: true`、`enable_local_logins_via_email: true`
  ///   → 本地密码登录可用
  /// - `hcaptcha_site_key: ""`、`recaptcha_site_key: ""` → 没装任何验证码插件
  /// - `enable_discourse_connect: false`、`login_required: false`
  static const bool enableNativePasswordLogin = true;

  /// 站点 hcaptcha 的 sitekey。
  ///
  /// **空字符串表示站点没有验证码**：登录流程跳过 hcaptcha 组件与
  /// `/hcaptcha/create.json`，直接 `GET /session/csrf` → `POST /session.json`。
  /// 上游为特定站点写死了 hcaptcha key；本站当前没有验证码插件。
  ///
  /// 站点若以后启用 hcaptcha，把 key 填进来即可恢复完整流程，无需改其他代码。
  static const String hcaptchaSiteKey = '';

  /// 指定 site key 是否启用了登录验证码。
  static bool isLoginCaptchaEnabled(String siteKey) =>
      siteKey.trim().isNotEmpty;

  /// 登录前是否强制取到 Cloudflare `cf_clearance` 才允许提交。
  ///
  /// 有验证码的站点可能需要先取得 Cloudflare clearance；本站登录流程不要求。
  /// 本站登录三个请求全部由 WebView 内核发出，TLS 指纹天然一致，不需要这道
  /// 前置；真被 CF 拦了也会在 csrf 阶段暴露，由 `_handleCsrfFailure` 弹人机
  /// 验证重试。有验证码的站点才需要打开。
  static bool get requireCfClearanceBeforeLogin =>
      isLoginCaptchaEnabled(hcaptchaSiteKey);

  /// 是否启用 Firebase Crashlytics 崩溃上报。
  ///
  /// 仓库里的 `android/app/google-services.json` 是上游留的占位配置
  /// （`project_id: dummy-project-id`），本项目没有自己的 Firebase 项目，
  /// 崩溃数据实际不会上报到任何地方。开着会向用户弹「本应用使用 Firebase
  /// Crashlytics 收集崩溃信息」的告知框——一个不属实的隐私声明，所以关掉。
  ///
  /// 要真正启用：建自己的 Firebase 项目、用真实 google-services.json 覆盖占位
  /// 文件（applicationId 需为 com.openxinsheng.taitou），再把这里改成 true。
  static const bool enableCrashReporting = false;

  /// 应用自定义 URL scheme（`taitou://topic/123` 等深链）。
  /// 需与 AndroidManifest 的 `android:scheme` 保持一致。
  static const String appScheme = 'taitou';

  /// 请求首页时是否跳过 X-CSRF-Token（用于预热）
  static const bool skipCsrfForHomeRequest = true;
}
