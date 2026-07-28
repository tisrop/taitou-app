import 'dart:async';
import 'package:flutter/foundation.dart';

import 'session_cookie_sentinel.dart';

/// 监听 Android WebView cookie 的外部变化并触发 sweep。
///
/// 已知 URL 由 [registerUrl] 维护，页面加载等边界通过
/// [notifyExternalChange] 主动触发，随后 debounce 500ms 执行 sweep。
class CookieStoreObserver {
  CookieStoreObserver._();
  static final CookieStoreObserver instance = CookieStoreObserver._();

  static const Duration _debounceWindow = Duration(milliseconds: 500);

  bool _attached = false;
  Timer? _debounce;
  final Set<String> _knownUrls = {};

  /// 启动监听。幂等，重复调用安全。
  void attach() {
    if (_attached) return;
    _attached = true;
    debugPrint('[CookieObserver] attached on Android');
  }

  /// 由 Dart 端主动触发（例如 WebView onLoadStop）。
  void notifyExternalChange() {
    _onCookiesChanged();
  }

  /// 注册一个 url, 后续 cookie change 事件会对这个 url 跑 sweepAll。
  ///
  /// 通常在 Priming 时调用 (priming 的 url 就是 WV 主域)。
  void registerUrl(String url) {
    if (url.isEmpty) return;
    _knownUrls.add(url);
  }

  /// 仅测试用。
  @visibleForTesting
  void resetForTest() {
    _debounce?.cancel();
    _debounce = null;
    _knownUrls.clear();
    _attached = false;
  }

  void _onCookiesChanged() {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _doSweep);
  }

  Future<void> _doSweep() async {
    final urls = _knownUrls.toList(growable: false);
    if (urls.isEmpty) return;
    debugPrint(
      '[CookieObserver] external cookie change detected, sweepAll for $urls',
    );
    for (final url in urls) {
      try {
        final results = await SessionCookieSentinel.instance.sweepAll(url);
        final mismatch = results
            .where(
              (r) => r.variantsBefore != r.variantsAfter || r.variantsAfter > 1,
            )
            .toList();
        if (mismatch.isNotEmpty) {
          debugPrint(
            '[CookieObserver] sweepAll($url) handled ${mismatch.length} cookies: $mismatch',
          );
        }
      } catch (e) {
        debugPrint('[CookieObserver] sweepAll($url) failed: $e');
      }
    }
  }
}
