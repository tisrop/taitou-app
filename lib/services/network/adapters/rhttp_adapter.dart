import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

import '../rhttp/rhttp_settings_service.dart';

/// 基于 rhttp (Rust reqwest) 的 Dio 适配器
///
/// 支持 HTTP/2 多路复用和系统 DNS。
class RhttpAdapter implements HttpClientAdapter {
  _RhttpDelegate? _delegate;
  Future<_RhttpDelegate>? _delegateBuild;
  int _rhttpVersion = -1;
  int _clientGeneration = 0;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError(
        "Can't establish connection after the adapter was closed.",
      );
    }
    final delegate = await _ensureDelegate();
    final response = await delegate.fetch(options, requestStream, cancelFuture);
    return response.responseBody;
  }

  Future<_RhttpDelegate> _ensureDelegate() async {
    final rhttpVersion = RhttpSettingsService.instance.version;

    final configChanged = _rhttpVersion != rhttpVersion;
    if (configChanged) {
      _disposeAllClients();
      _rhttpVersion = rhttpVersion;
    }

    final delegate = _delegate;
    if (delegate != null) {
      return delegate;
    }
    final building = _delegateBuild;
    if (building != null) {
      try {
        return await building;
      } on _StaleRhttpBuild {
        if (identical(_delegateBuild, building)) {
          _delegateBuild = null;
        }
        return _ensureDelegate();
      }
    }
    final buildGeneration = _clientGeneration;
    final future = _buildDelegate(buildGeneration);
    _delegateBuild = future;
    try {
      return await future;
    } on _StaleRhttpBuild {
      if (identical(_delegateBuild, future)) {
        _delegateBuild = null;
      }
      return _ensureDelegate();
    } finally {
      if (identical(_delegateBuild, future)) {
        _delegateBuild = null;
      }
    }
  }

  Future<_RhttpDelegate> _buildDelegate(int buildGeneration) async {
    final created = _RhttpDelegate(await _createClient());
    if (_closed || buildGeneration != _clientGeneration) {
      created.client.dispose(cancelRunningRequests: true);
      if (_closed) {
        throw StateError(
          "Can't establish connection after the adapter was closed.",
        );
      }
      throw const _StaleRhttpBuild();
    }
    _delegate = created;
    debugPrint('[DIO] RhttpAdapter 重建完成 (DNS: system)');
    return created;
  }

  Future<rhttp.RhttpClient> _createClient() async {
    return rhttp.RhttpClient.create(
      settings: rhttp.ClientSettings(
        // 用 ALPN 协商 HTTP/2，避免 https 场景误用 prior knowledge 造成超时。
        httpVersionPref: rhttp.HttpVersionPref.all,

        // Dio 自己根据状态码处理，不让 rhttp 提前抛状态码异常。
        throwOnStatusCode: false,

        // 不读取环境变量或应用内配置，始终直连。
        proxySettings: const rhttp.ProxySettings.noProxy(),

        // Cookie/重定向交给 Dio 拦截器
        cookieSettings: const rhttp.CookieSettings(storeCookies: false),
        redirectSettings: const rhttp.RedirectSettings.none(),

        timeoutSettings: const rhttp.TimeoutSettings(
          connectTimeout: Duration(seconds: 30),
          // client 级 timeout 仅作进程兜底,真正的 per-request 超时由 Dio 的
          // RequestOptions.receiveTimeout / connectTimeout 在上层控制。
          // 这里若写死成 30s,会硬截断所有需要 >30s 的请求(如 MessageBus 长轮询
          // 服务端 hold 25s),导致请求被 rhttp 提前 abort 抛 RhttpTimeoutException。
          timeout: Duration(minutes: 10),
          keepAliveTimeout: Duration(seconds: 60),
        ),
      ),
    );
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    _disposeAllClients(force: force);
  }

  void _disposeAllClients({bool force = false}) {
    _clientGeneration++;
    _delegateBuild = null;
    _delegate?.client.dispose(cancelRunningRequests: force);
    _delegate = null;
  }
}

class _StaleRhttpBuild implements Exception {
  const _StaleRhttpBuild();
}

class _RhttpFetchResult {
  const _RhttpFetchResult({required this.responseBody, required this.remoteIp});

  final ResponseBody responseBody;
  final String? remoteIp;
}

class _RhttpDelegate {
  const _RhttpDelegate(this.client);

  final rhttp.RhttpClient client;

  Future<_RhttpFetchResult> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final cancelToken = rhttp.CancelToken();
    cancelFuture?.whenComplete(cancelToken.cancel);

    try {
      final response = await client.requestStream(
        method: rhttp.HttpMethod(options.method.toUpperCase()),
        url: options.uri.toString(),
        headers: _buildHeaders(options),
        body: _buildBody(options, requestStream),
        cancelToken: cancelToken,
      );

      return _RhttpFetchResult(
        responseBody: ResponseBody(
          response.body.cast<Uint8List>().handleError(
            // flutter_rust_bridge STREAM_CANCEL_ERROR：
            // Dart 端取消了流（页面销毁/请求取消），Rust 端写入已关闭的 StreamSink。
            // 等价于流正常结束，静默吞掉避免 SIGABRT 崩溃。
            (error) {},
            test: (error) => error.toString().contains('STREAM_CANCEL_ERROR'),
          ),
          response.statusCode,
          headers: response.headerMapList,
          isRedirect: false,
        )..extra['remote_ip'] = response.remoteIp,
        remoteIp: response.remoteIp,
      );
    } on rhttp.RhttpException catch (error) {
      throw _mapRhttpException(options, error);
    }
  }

  rhttp.HttpHeaders? _buildHeaders(RequestOptions options) {
    if (options.headers.isEmpty) {
      return null;
    }

    final headers = <String, String>{};
    options.headers.forEach((key, value) {
      if (value == null) {
        return;
      }
      final headerValue = switch (value) {
        Iterable<Object?> values =>
          values
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .join(', '),
        _ => value.toString().trim(),
      };
      if (headerValue.isNotEmpty) {
        headers[key] = headerValue;
      }
    });
    if (headers.isEmpty) {
      return null;
    }
    return rhttp.HttpHeaders.rawMap(headers);
  }

  rhttp.HttpBody? _buildBody(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) {
    if (requestStream != null) {
      final contentLength = int.tryParse(
        options.headers['content-length']?.toString() ?? '',
      );
      return rhttp.HttpBody.stream(
        requestStream,
        length: contentLength != null && contentLength >= 0
            ? contentLength
            : null,
      );
    }

    final data = options.data;
    if (data == null) {
      return null;
    }
    if (data is Uint8List) {
      return rhttp.HttpBody.bytes(data);
    }
    if (data is List<int>) {
      return rhttp.HttpBody.bytes(Uint8List.fromList(data));
    }
    if (data is String) {
      return rhttp.HttpBody.text(data);
    }
    if (data is Map<String, String>) {
      return rhttp.HttpBody.form(data);
    }
    return rhttp.HttpBody.json(data);
  }

  DioException _mapRhttpException(
    RequestOptions options,
    rhttp.RhttpException error,
  ) {
    if (error is rhttp.RhttpCancelException) {
      return DioException(
        requestOptions: options,
        error: error,
        type: DioExceptionType.cancel,
        message: error.toString(),
      );
    }
    if (error is rhttp.RhttpTimeoutException) {
      return DioException.connectionTimeout(
        requestOptions: options,
        timeout:
            options.connectTimeout ?? options.receiveTimeout ?? Duration.zero,
        error: error,
      );
    }
    if (error is rhttp.RhttpInvalidCertificateException) {
      return DioException.badCertificate(requestOptions: options, error: error);
    }
    if (error is rhttp.RhttpConnectionException) {
      return DioException.connectionError(
        requestOptions: options,
        reason: error.message,
        error: error,
      );
    }
    if (error is rhttp.RhttpStatusCodeException) {
      return DioException.badResponse(
        statusCode: error.statusCode,
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: error.statusCode,
          headers: Headers.fromMap(error.headerMapList),
          data: error.body,
        ),
      );
    }
    return DioException(
      requestOptions: options,
      error: error,
      type: DioExceptionType.unknown,
    );
  }
}
