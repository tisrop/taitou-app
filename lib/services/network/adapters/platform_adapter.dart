import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../rhttp/rhttp_settings_service.dart';
import '../webview/webview_adapter_settings_service.dart';
import 'adapter_log_metadata.dart';
import 'cronet_fallback_service.dart';
import 'network_http_adapter.dart';
import '../../../l10n/s.dart';
import 'rhttp_adapter.dart';
import 'webview_http_adapter.dart';

/// 当前使用的适配器类型
enum AdapterType {
  webview, // Android WebView 网络栈兼容适配器
  native, // Android NativeAdapter
  network, // Dart IO 备用适配器
  rhttp, // rhttp 引擎（Rust reqwest）
}

/// 当前适配器生效的原因（用于 UI 解释"为什么是这个引擎"）
enum AdapterReason {
  rhttp, // rhttp 已启用且满足使用条件
  fallback, // Cronet 已降级，走备用适配器
  native, // 默认直连
}

/// 当前生效的适配器及其原因
class EffectiveAdapter {
  const EffectiveAdapter(this.type, this.reason);

  final AdapterType type;
  final AdapterReason reason;
}

/// 全局变量：记录当前使用的适配器类型
AdapterType? _currentAdapterType;

/// 获取当前使用的适配器类型
AdapterType? getCurrentAdapterType() => _currentAdapterType;

AdapterType? tryParseAdapterType(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final type in AdapterType.values) {
    if (type.name == value) {
      return type;
    }
  }
  return null;
}

/// 获取适配器类型的显示名称
String getAdapterDisplayName(AdapterType type) {
  switch (type) {
    case AdapterType.webview:
      return S.current.network_adapterWebView;
    case AdapterType.native:
      return S.current.network_adapterNativeAndroid;
    case AdapterType.network:
      return S.current.network_adapterNetwork;
    case AdapterType.rhttp:
      return S.current.network_adapterRhttp;
  }
}

/// 创建一个 HttpClientAdapter，用于外部服务（如 AI 请求）复用应用网络配置
HttpClientAdapter createExternalHttpAdapter() {
  final fallbackService = CronetFallbackService.instance;
  final rhttpSettings = RhttpSettingsService.instance;

  final adapter = _DynamicAdapter(fallbackService, rhttpSettings);
  return _WebViewAdapterWrapper(adapter);
}

/// 配置平台适配器
void configurePlatformAdapter(Dio dio) {
  final fallbackService = CronetFallbackService.instance;
  final rhttpSettings = RhttpSettingsService.instance;

  // Android 默认使用主链路动态适配。
  dio.httpClientAdapter = _DynamicAdapter(fallbackService, rhttpSettings);
  _currentAdapterType = _resolveAdapterType(fallbackService, rhttpSettings);

  dio.httpClientAdapter = _WebViewAdapterWrapper(dio.httpClientAdapter);
}

AdapterType _resolveAdapterType(
  CronetFallbackService fallbackService,
  RhttpSettingsService rhttpSettings,
) {
  return _resolveEffective(fallbackService, rhttpSettings).type;
}

AdapterType _resolveAdapterTypeForRequest(
  RequestOptions options,
  CronetFallbackService fallbackService,
  RhttpSettingsService rhttpSettings,
) {
  return _resolveEffective(
    fallbackService,
    rhttpSettings,
    requestOptions: options,
  ).type;
}

/// 实时解析当前生效的适配器及原因（UI 单一数据源）。
///
/// 不依赖请求触发，读取各 service 当前状态即时推算，
/// 与 [_DynamicAdapter] 每次请求时的判断完全同源。
EffectiveAdapter resolveEffectiveAdapter() {
  return _resolveEffective(
    CronetFallbackService.instance,
    RhttpSettingsService.instance,
  );
}

EffectiveAdapter _resolveEffective(
  CronetFallbackService fallbackService,
  RhttpSettingsService rhttpSettings, {
  RequestOptions? requestOptions,
}) {
  // rhttp 优先（满足条件时）
  if (rhttpSettings.shouldUseRhttp() &&
      (requestOptions == null || requestAllowsRhttpAdapter(requestOptions))) {
    return const EffectiveAdapter(AdapterType.rhttp, AdapterReason.rhttp);
  }
  if (fallbackService.hasFallenBack) {
    return const EffectiveAdapter(AdapterType.network, AdapterReason.fallback);
  }
  return const EffectiveAdapter(AdapterType.native, AdapterReason.native);
}

@visibleForTesting
bool requestAllowsRhttpAdapter(RequestOptions options) {
  return options.extra['skipRhttpAdapter'] != true;
}

/// 创建 Android NativeAdapter。
HttpClientAdapter _createNativeAdapter() => NativeAdapter();

/// 在主网络适配器之外按请求分流到 WebView 兼容适配器。
class _WebViewAdapterWrapper implements HttpClientAdapter {
  _WebViewAdapterWrapper(this._inner) {
    WebViewAdapterSettingsService.instance.effectiveNotifier.addListener(
      _handleWebViewSettingChanged,
    );
  }

  final HttpClientAdapter _inner;
  WebViewHttpAdapter? _webViewAdapter;

  WebViewHttpAdapter _getWebViewAdapter() {
    return _webViewAdapter ??= WebViewHttpAdapter();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // WebView 适配器：主域名 API 请求走 WebView 内核（真正的浏览器 TLS 指纹）
    if (_shouldUseWebView(options)) {
      return _getWebViewAdapter().fetch(options, requestStream, cancelFuture);
    }

    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    WebViewAdapterSettingsService.instance.effectiveNotifier.removeListener(
      _handleWebViewSettingChanged,
    );
    _webViewAdapter?.close(force: force);
    _webViewAdapter = null;
    _inner.close(force: force);
  }

  void _handleWebViewSettingChanged() {
    if (WebViewAdapterSettingsService.instance.effectiveEnabled) {
      return;
    }
    _webViewAdapter?.disposeWhenIdle();
  }

  bool _shouldUseWebView(RequestOptions options) {
    if (!WebViewAdapterSettingsService.instance.effectiveEnabled) {
      return false;
    }
    return requestCanUseWebViewAdapter(options);
  }
}

/// 判断请求本身是否能由 WebView 适配器承载，不考虑当前兼容模式开关。
/// 用于 CF 恢复在弹出兼容提示前确认该请求确实可以被浏览器网络栈接管。
bool requestCanUseWebViewAdapter(RequestOptions options) {
  final uri = options.uri;
  if (options.extra['skipWebViewAdapter'] == true) {
    return false;
  }
  if (options.extra['isCfChallengePlatform'] == true ||
      uri.path.startsWith('/cdn-cgi/')) {
    return false;
  }

  final resourceKind = options.extra[WebViewHttpAdapter.resourceKindExtraKey]
      ?.toString();
  final method = options.method.toUpperCase();
  final isBinaryResponse =
      options.responseType == ResponseType.stream ||
      options.responseType == ResponseType.bytes;

  // 当前 WebView fetch 运行在站点 origin；跨域图片即使浏览器能显示，
  // JS 也不能读取响应字节。图片流仅允许同源请求，其它 stream 请求
  //（MessageBus、下载等）仍不走 WebView。
  if (resourceKind == WebViewHttpAdapter.resourceKindImage) {
    return (method == 'GET' || method == 'HEAD') &&
        isBinaryResponse &&
        WebViewAdapterSettingsService.instance.canUseWebView(uri);
  }

  if (!WebViewAdapterSettingsService.instance.canUseWebView(uri)) {
    return false;
  }
  if (isBinaryResponse) {
    return false;
  }

  final accept = _requestHeaderValue(options.headers, 'Accept').toLowerCase();
  final requestedWith = _requestHeaderValue(
    options.headers,
    'X-Requested-With',
  );
  final explicitlyHtml =
      accept.contains('text/html') || accept.contains('application/xhtml+xml');
  if (explicitlyHtml) {
    return false;
  }
  final apiLikeGet =
      requestedWith == 'XMLHttpRequest' ||
      uri.path.endsWith('.json') ||
      accept.contains('application/json') ||
      accept.contains('text/javascript');
  if ((method == 'GET' || method == 'HEAD') && !apiLikeGet) {
    return false;
  }

  return method == 'GET' ||
      method == 'HEAD' ||
      method == 'POST' ||
      method == 'PUT' ||
      method == 'PATCH' ||
      method == 'DELETE';
}

String _requestHeaderValue(Map<String, dynamic> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toString().toLowerCase() == name.toLowerCase()) {
      return _requestHeaderValueToString(entry.value);
    }
  }
  return '';
}

String _requestHeaderValueToString(Object? value) {
  if (value == null) return '';
  if (value is Iterable) {
    return value
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
  }
  return value.toString().trim();
}

/// Android 动态适配器：每次请求时根据设置在 rhttp、network 和 native
/// 网络栈之间切换。WebView 分流由外层包装器负责。
class _DynamicAdapter implements HttpClientAdapter {
  _DynamicAdapter(this._fallbackService, this._rhttpSettings);

  final CronetFallbackService _fallbackService;
  final RhttpSettingsService _rhttpSettings;

  final Map<AdapterType, HttpClientAdapter> _delegates = {};
  int _rhttpVersion = -1;
  bool _hasFallenBack = false;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (_closed) {
      throw StateError(
        "Can't establish connection after the adapter was closed.",
      );
    }
    final desiredType = _resolveAdapterTypeForRequest(
      options,
      _fallbackService,
      _rhttpSettings,
    );
    final delegate = _ensureDelegate(desiredType);
    setRequestAdapterLogName(options, desiredType.name);
    _currentAdapterType = desiredType;
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  HttpClientAdapter _ensureDelegate(AdapterType desiredType) {
    final rhttpVersion = _rhttpSettings.version;
    final hasFallenBack = _fallbackService.hasFallenBack;

    final configChanged =
        _rhttpVersion != rhttpVersion || _hasFallenBack != hasFallenBack;

    if (configChanged) {
      // 不要强杀旧 delegate，避免进行中的 Cronet/rhttp 请求触发 native 崩溃。
      for (final delegate in _delegates.values) {
        delegate.close(force: false);
      }
      _delegates.clear();
    }

    final existing = _delegates[desiredType];
    if (existing != null) {
      return existing;
    }

    final delegate = switch (desiredType) {
      AdapterType.webview => WebViewHttpAdapter(),
      AdapterType.rhttp => RhttpAdapter(),
      AdapterType.network => NetworkHttpAdapter(),
      AdapterType.native => _createNativeAdapter(),
    };

    switch (desiredType) {
      case AdapterType.webview:
        debugPrint('[DIO] Dynamic adapter -> WebViewHttpAdapter');
      case AdapterType.rhttp:
        debugPrint('[DIO] Dynamic adapter -> RhttpAdapter');
      case AdapterType.network:
        debugPrint('[DIO] Dynamic adapter -> NetworkHttpAdapter');
      case AdapterType.native:
        break;
    }

    _rhttpVersion = rhttpVersion;
    _hasFallenBack = hasFallenBack;
    _delegates[desiredType] = delegate;
    return delegate;
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    for (final delegate in _delegates.values) {
      delegate.close(force: force);
    }
    _delegates.clear();
  }
}
