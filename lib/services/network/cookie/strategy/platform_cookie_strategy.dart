import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'android_cookie_strategy.dart';

/// 平台 cookie 策略抽象基类。
///
/// 只封装真正有平台差异的操作，不包含业务同步逻辑。
abstract class PlatformCookieStrategy {
  /// Android-only 工厂。
  factory PlatformCookieStrategy.create() => AndroidCookieStrategy();

  /// 从 WebView 读取指定 URL 的 cookie 列表
  Future<List<Cookie>> readCookiesFromWebView(
    CookieManager cookieManager,
    String url,
  );

  /// 清除 WebView cookie store 中所有 cookie
  Future<void> clearWebViewCookies(
    CookieManager cookieManager,
    Set<String> knownHosts,
  );

  /// 将原始 Set-Cookie 头批量写入 WebView
  /// 返回成功写入的条数
  Future<int> writeRawCookiesToWebView(
    List<(String url, String rawHeader)> entries,
  );
}
