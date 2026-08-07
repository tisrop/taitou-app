import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

import '../../constants.dart';
import 'adapters/platform_adapter.dart';
import 'cookie/app_cookie_manager.dart';
import 'cookie/cookie_jar_service.dart';
import 'cookie/csrf_token_service.dart';
import 'interceptors/cf_challenge_interceptor.dart';
import 'interceptors/request_scheduler_interceptor.dart';
import 'interceptors/session_guard_interceptor.dart';
import 'interceptors/cronet_fallback_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/network_log_interceptor.dart';
import 'interceptors/redirect_interceptor.dart';
import 'interceptors/request_header_interceptor.dart';
import 'interceptors/self_healing_interceptor.dart';

/// 统一封装的 Dio 工厂
class DiscourseDio {
  static const _retryableReadMethods = {'GET', 'HEAD', 'OPTIONS'};

  /// 只对幂等读请求做短暂网络故障重试。
  ///
  /// 业务层的“加载失败，点重试又好了”通常是首个请求撞上连接抖动、
  /// 网关 5xx 或服务端 429。写请求不能在这里自动重放，避免重复发帖、
  /// 重复投票等副作用；CF challenge / 鉴权错误也交给对应拦截器处理。
  static bool _shouldRetryReadRequest(DioException error, int attempt) {
    final method = error.requestOptions.method.toUpperCase();
    if (!_retryableReadMethods.contains(method)) return false;

    if (error.type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      return status != null && defaultRetryableStatuses.contains(status);
    }

    // 不重试 cancel、CF challenge 等业务错误；只覆盖真实的传输层抖动。
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.badCertificate => true,
      _ => false,
    };
  }

  static Dio create({
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    Map<String, dynamic>? defaultHeaders,
    String? baseUrl,

    /// null 表示不限制（用于下载、MessageBus 等），非 null 启用调度器。
    /// 实际并发数和速率从 [RequestSchedulerConfig] 动态读取。
    int? maxConcurrent = 3,
    bool enableRetry = true,
    bool enableCfChallenge = true,
    bool enableCookies = true,
    bool enableNetworkLog = true,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: defaultHeaders,
        // 禁用自动重定向，手动处理以确保重定向时使用正确的 cookie
        followRedirects: false,
        // 包含重定向状态码，让我们手动处理
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );

    // 大响应(>50KB)的 JSON 解码移入 isolate:话题列表/详情等大 JSON
    // 在主线程解码实测把 DartIsolate::HandleMessage 顶到 50~100ms,
    // 滚动/返回列表时直接掉帧。小响应仍同步解码(isolate 往返不划算)。
    dio.transformer = BackgroundTransformer();

    // 1. 配置平台适配器
    configurePlatformAdapter(dio);

    // 2. 会话代守卫（最先执行，确保过期请求不进入后续拦截器）
    dio.interceptors.add(SessionGuardInterceptor());

    // 3. 并发限制 + 滑动窗口速率限制（null 表示不限制）
    // 实际参数从 RequestSchedulerConfig 动态读取
    if (maxConcurrent != null) {
      dio.interceptors.add(RequestSchedulerInterceptor());
    }

    // 4. Cookie 管理
    final cookieJarService = CookieJarService();
    if (enableCookies && cookieJarService.isInitialized) {
      dio.interceptors.add(AppCookieManager(cookieJarService.cookieJar));
      // 4.1 v0.4.0: 401 / discourse-logged-out 透明自愈
      //
      // 注册顺序: AppCookieManager 在前, SelfHealing 在后。
      // Dio 规则: onResponse 按 LIFO 调用 → SelfHealing 先于 AppCookieManager。
      //
      // 这是必要的: 服务器拒绝时常带 Set-Cookie 清 _t。如果 AppCookieManager
      // 先 onResponse, jar 中 _t 被清空, SelfHealing 检查时认为"真登出"跳过自愈。
      // 反之让 SelfHealing 先 onResponse, 看到的是 jar 上一个稳定状态,
      // 能正确判定"jar 仍有效, WV 多变体导致服务器拒绝", 触发自愈。
      dio.interceptors.add(SelfHealingInterceptor(dio: dio));
    }

    // 5. Cronet 降级拦截器（在重试拦截器之前）
    dio.interceptors.add(CronetFallbackInterceptor(dio));

    // 6. 重试拦截器 (dio_smart_retry)
    if (enableRetry) {
      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          logPrint: (msg) => debugPrint('[Dio Retry] $msg'),
          // 首次请求失败时自动补两次，页面不再直接落入“加载失败”；
          // 仅幂等读请求会通过上面的 retryEvaluator。
          retries: 2,
          retryDelays: const [
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 4),
          ],
          retryEvaluator: _shouldRetryReadRequest,
        ),
      );
    }

    // 7. 请求头拦截器
    dio.interceptors.add(RequestHeaderInterceptor(CsrfTokenService()));

    // 8. 重定向拦截器
    dio.interceptors.add(RedirectInterceptor(dio));

    // 9. 错误拦截器
    dio.interceptors.add(ErrorInterceptor());

    // 10. CF 验证拦截器
    if (enableCfChallenge) {
      dio.interceptors.add(
        CfChallengeInterceptor(dio: dio, cookieJarService: cookieJarService),
      );
    }

    // 11. 网络日志拦截器（最后一个，记录最终结果）
    // WebView 兼容分流位于 HttpClientAdapter 层，业务拦截器始终看到原始 URL。
    if (enableNetworkLog) {
      dio.interceptors.add(NetworkLogInterceptor());
    }

    return dio;
  }
}
