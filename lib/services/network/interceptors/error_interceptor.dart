import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../constants.dart';
import '../../../l10n/s.dart';
import '../../../services/cf/cf_challenge_service.dart';
import '../../toast_service.dart';
import '../exceptions/api_exception.dart';
import '../vpn_connectivity_state.dart';

/// 错误拦截器
/// 处理 429/502/503/504 错误，转换为自定义异常
/// 操作性请求（POST/PUT/DELETE/PATCH）默认显示错误提示
/// 可通过 extra['showErrorToast'] 或 extra['isSilent'] 手动控制
class ErrorInterceptor extends Interceptor {
  /// 操作性请求方法，默认显示错误提示
  static const _mutationMethods = {'POST', 'PUT', 'DELETE', 'PATCH'};
  static const _vpnHintCooldown = Duration(minutes: 5);
  static DateTime? _lastVpnHintAt;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final method = err.requestOptions.method.toUpperCase();
    final extra = err.requestOptions.extra;
    final vpnFailureHandled = await _handleVpnConnectionFailure(err);

    // CF 盾 403/429 由 CfChallengeInterceptor 统一决定展示形态:
    // 页面数据走错误态按钮,操作请求走明确提示,静默请求不打扰。
    // CF 速率限制规则配 managed_challenge 时返回 429 + 挑战页,不是真正的速率限制,
    // 不能落入下方 429 分支弹"请等待 N 秒"toast、抛 RateLimitException。
    if ((statusCode == 403 || statusCode == 429) &&
        CfChallengeService.isCfChallengeResponse(err.response)) {
      handler.next(err);
      return;
    }

    // CF 恢复协调产生的本地取消应保持原始语义，不显示通用请求失败提示。
    if (err.error is CfChallengeException) {
      handler.next(err);
      return;
    }

    // 静默模式：不显示任何错误提示
    if (extra['isSilent'] == true) {
      handler.next(err);
      return;
    }

    // 判断是否显示错误提示：
    // 1. 如果 extra 中明确指定了 showErrorToast，使用指定的值
    // 2. 否则，操作性请求默认显示
    final showErrorToast = extra.containsKey('showErrorToast')
        ? extra['showErrorToast'] == true
        : _mutationMethods.contains(method);

    // 提取错误信息
    String? errorMessage;
    final data = err.response?.data;
    if (data is Map<String, dynamic>) {
      // Discourse API 错误格式
      errorMessage =
          data['error'] as String? ??
          (data['errors'] as List?)?.firstOrNull?.toString();
    }

    // 重试耗尽后抛出自定义异常供 UI 层处理
    if (statusCode == 429) {
      final retryAfter = _extractRetryAfterSeconds(err.response);
      if (showErrorToast) {
        final toastMessage = retryAfter != null && retryAfter > 0
            ? S.current.network_rateLimitedWait(_formatWaitDuration(retryAfter))
            : (errorMessage ?? S.current.network_rateLimited);
        ToastService.showError(toastMessage);
      }
      throw RateLimitException(retryAfter, errorMessage);
    }
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      if (showErrorToast) {
        ToastService.showError(
          errorMessage ?? S.current.network_serverUnavailableRetry,
        );
      }
      throw ServerException(statusCode!);
    }

    // 其他错误
    if (showErrorToast && !vpnFailureHandled) {
      if (errorMessage != null) {
        ToastService.showError(errorMessage);
      } else {
        // 通用错误提示
        final message = switch (statusCode) {
          400 => S.current.network_badRequest,
          401 => S.current.network_unauthorized,
          403 => S.current.network_forbidden,
          404 => S.current.network_notFound,
          422 => S.current.network_unprocessable,
          500 => S.current.network_internalError,
          _ => S.current.error_requestFailed,
        };
        ToastService.showError(message);
      }
    }

    handler.next(err);
  }

  Future<bool> _handleVpnConnectionFailure(DioException err) async {
    if (!_isVpnDirectHintCandidate(err)) {
      return false;
    }

    final vpnActive = await VpnConnectivityState.instance.resolveIsActive();
    if (!vpnActive) return false;

    final now = DateTime.now();
    final lastShownAt = _lastVpnHintAt;
    if (lastShownAt == null ||
        now.difference(lastShownAt) >= _vpnHintCooldown) {
      _lastVpnHintAt = now;
      ToastService.show(
        S.current.network_vpnDirectHint,
        type: ToastType.error,
        duration: const Duration(seconds: 8),
        maxLines: null,
      );
      return true;
    }
    return false;
  }

  @visibleForTesting
  static bool shouldShowVpnDirectHint(
    DioException err, {
    required bool vpnActive,
  }) {
    return vpnActive && _isVpnDirectHintCandidate(err);
  }

  static bool _isVpnDirectHintCandidate(DioException err) {
    if (err.response != null) return false;
    if (err.requestOptions.extra['isSilent'] == true) return false;
    if (!AppConstants.isSiteHost(err.requestOptions.uri.host)) return false;

    return switch (err.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => true,
      DioExceptionType.unknown =>
        err.error is SocketException || _isCronetConnectionFailure(err.error),
      DioExceptionType.badCertificate ||
      DioExceptionType.badResponse ||
      DioExceptionType.cancel => false,
    };
  }

  @visibleForTesting
  static void resetVpnHintCooldown() {
    _lastVpnHintAt = null;
  }

  static bool _isCronetConnectionFailure(Object? error) {
    if (error is! http.ClientException) return false;

    final message = error.message.toUpperCase();
    if (!message.contains('CRONET')) return false;

    const connectionErrors = <String>{
      'ERR_CONNECTION_CLOSED',
      'ERR_CONNECTION_RESET',
      'ERR_CONNECTION_ABORTED',
      'ERR_CONNECTION_REFUSED',
      'ERR_CONNECTION_TIMED_OUT',
      'ERR_TIMED_OUT',
      'ERR_INTERNET_DISCONNECTED',
      'ERR_NETWORK_CHANGED',
      'ERR_ADDRESS_UNREACHABLE',
      'ERR_NAME_NOT_RESOLVED',
    };
    return connectionErrors.any(message.contains);
  }

  int? _extractRetryAfterSeconds(Response? response) {
    if (response == null) return null;
    final headerSeconds = _extractRetryAfterFromHeaders(response.headers);
    if (headerSeconds != null) return headerSeconds;
    return _extractRetryAfterFromData(response.data);
  }

  int? _extractRetryAfterFromHeaders(Headers headers) {
    final retryAfter =
        headers.value('retry-after') ?? headers.value('Retry-After');
    if (retryAfter != null) {
      final retrySeconds = int.tryParse(retryAfter);
      if (retrySeconds != null && retrySeconds > 0) {
        return retrySeconds;
      }
      try {
        final retryDate = HttpDate.parse(retryAfter);
        final delta = retryDate.difference(DateTime.now()).inSeconds;
        if (delta > 0) return delta;
      } catch (_) {}
    }

    final resetValue =
        headers.value('x-ratelimit-reset') ??
        headers.value('ratelimit-reset') ??
        headers.value('x-rate-limit-reset') ??
        headers.value('X-RateLimit-Reset');
    final resetSeconds = int.tryParse(resetValue ?? '');
    if (resetSeconds != null && resetSeconds > 0) {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final delta = resetSeconds > 1000000000
          ? (resetSeconds - nowSeconds)
          : resetSeconds;
      if (delta > 0) return delta;
    }
    return null;
  }

  int? _extractRetryAfterFromData(dynamic data) {
    if (data is Map) {
      final extras = data['extras'];
      if (extras is Map) {
        final waitSecondsRaw = extras['wait_seconds'] ?? extras['time_left'];
        final waitSeconds = int.tryParse(waitSecondsRaw?.toString() ?? '');
        if (waitSeconds != null && waitSeconds > 0) {
          return waitSeconds;
        }
      }

      final error = data['error'];
      if (error is String) {
        final parsed = _parseWaitSecondsFromText(error);
        if (parsed != null) return parsed;
      }

      final errors = data['errors'];
      if (errors is List) {
        for (final item in errors) {
          final parsed = _parseWaitSecondsFromText(item.toString());
          if (parsed != null) return parsed;
        }
      } else if (errors is String) {
        final parsed = _parseWaitSecondsFromText(errors);
        if (parsed != null) return parsed;
      }
    }

    if (data is String) {
      return _parseWaitSecondsFromText(data);
    }

    return null;
  }

  int? _parseWaitSecondsFromText(String message) {
    final chineseMatch = RegExp(
      r'请等待\s*([0-9]+)\s*(天|小时|分钟|秒)',
    ).firstMatch(message);
    if (chineseMatch != null) {
      final value = int.tryParse(chineseMatch.group(1) ?? '');
      final unit = chineseMatch.group(2);
      if (value == null || unit == null) return null;
      return _secondsFromUnit(value, unit);
    }

    final englishMatch = RegExp(
      r'Please wait\s+(\d+)\s+(second|seconds|minute|minutes|hour|hours|day|days)',
      caseSensitive: false,
    ).firstMatch(message);
    if (englishMatch != null) {
      final value = int.tryParse(englishMatch.group(1) ?? '');
      final unit = englishMatch.group(2)?.toLowerCase();
      if (value == null || unit == null) return null;
      return _secondsFromUnit(value, unit);
    }

    return null;
  }

  int _secondsFromUnit(int value, String unit) {
    if (unit.contains('天') || unit.startsWith('day')) {
      return value * 86400;
    }
    if (unit.contains('小时') || unit.startsWith('hour')) {
      return value * 3600;
    }
    if (unit.contains('分钟') || unit.startsWith('minute')) {
      return value * 60;
    }
    return value;
  }

  String _formatWaitDuration(int seconds) {
    if (seconds >= 86400) {
      return S.current.time_days((seconds / 86400).ceil());
    }
    if (seconds >= 3600) {
      return S.current.time_hours((seconds / 3600).ceil());
    }
    if (seconds >= 60) {
      return S.current.time_minutes((seconds / 60).ceil());
    }
    return S.current.time_seconds(seconds);
  }
}
