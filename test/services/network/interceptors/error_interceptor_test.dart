import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fluxdo/constants.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/services/network/interceptors/error_interceptor.dart';
import 'package:fluxdo/services/network/vpn_connectivity_state.dart';

void main() {
  setUp(() {
    VpnConnectivityState.instance.reset();
    ErrorInterceptor.resetVpnHintCooldown();
  });

  tearDown(() {
    VpnConnectivityState.instance.reset();
    ErrorInterceptor.resetVpnHintCooldown();
  });

  RequestOptions options({
    String baseUrl = AppConstants.baseUrl,
    String path = '/latest.json',
    String method = 'GET',
    Map<String, dynamic>? extra,
  }) {
    return RequestOptions(
      path: path,
      baseUrl: baseUrl,
      method: method,
      extra: extra ?? <String, dynamic>{},
    );
  }

  DioException failure({
    DioExceptionType type = DioExceptionType.connectionError,
    RequestOptions? requestOptions,
    Object? error,
    Response<dynamic>? response,
  }) {
    return DioException(
      requestOptions: requestOptions ?? options(),
      type: type,
      error: error,
      response: response,
    );
  }

  group('VPN DIRECT 提示判定', () {
    test('VPN 下主站及子域连接失败时提示', () {
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(failure(), vpnActive: true),
        isTrue,
      );
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(
            requestOptions: options(
              baseUrl: 'https://cdn.${AppConstants.baseHost}',
            ),
          ),
          vpnActive: true,
        ),
        isTrue,
      );
    });

    test('非 VPN、外站、静默请求和取消请求不提示', () {
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(failure(), vpnActive: false),
        isFalse,
      );
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(requestOptions: options(baseUrl: 'https://example.com')),
          vpnActive: true,
        ),
        isFalse,
      );
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(requestOptions: options(extra: {'isSilent': true})),
          vpnActive: true,
        ),
        isFalse,
      );
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(type: DioExceptionType.cancel),
          vpnActive: true,
        ),
        isFalse,
      );
    });

    test('HTTP 响应错误不提示，底层 SocketException 可以提示', () {
      final requestOptions = options();
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(
            requestOptions: requestOptions,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: requestOptions,
              statusCode: 403,
            ),
          ),
          vpnActive: true,
        ),
        isFalse,
      );
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(
            type: DioExceptionType.unknown,
            error: const SocketException('connection failed'),
          ),
          vpnActive: true,
        ),
        isTrue,
      );
    });

    test('unknown 包装 Cronet 连接关闭错误时提示', () {
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(
            type: DioExceptionType.unknown,
            requestOptions: options(path: '/'),
            error: http.ClientException(
              'Cronet exception: Exception in CronetUrlRequest: '
              'net::ERR_CONNECTION_CLOSED, ErrorCode=5, '
              'InternalErrorCode=-100, Retryable=true',
              Uri.parse(AppConstants.baseUrl),
            ),
          ),
          vpnActive: true,
        ),
        isTrue,
      );
    });

    test('unknown 包装普通 ClientException 时不提示', () {
      expect(
        ErrorInterceptor.shouldShowVpnDirectHint(
          failure(
            type: DioExceptionType.unknown,
            error: http.ClientException('unexpected client failure'),
          ),
          vpnActive: true,
        ),
        isFalse,
      );
    });
  });

  test('VpnConnectivityState 跟踪最近一次 VPN 状态', () {
    final state = VpnConnectivityState.instance;
    state.update(const [ConnectivityResult.wifi, ConnectivityResult.vpn]);
    expect(state.isActive, isTrue);

    state.update(const [ConnectivityResult.wifi]);
    expect(state.isActive, isFalse);
  });

  test('首次网络事件未到达时主动查询 VPN 状态', () async {
    final state = VpnConnectivityState.instance;

    final active = await state.resolveIsActive(
      checkConnectivity: () async => const [
        ConnectivityResult.wifi,
        ConnectivityResult.vpn,
      ],
    );

    expect(active, isTrue);
    expect(state.isActive, isTrue);
  });

  testWidgets('VPN 提示冷却期内的操作失败仍显示通用错误', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          navigatorKey: navigatorKey,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    final state = VpnConnectivityState.instance;
    state.update(const [ConnectivityResult.vpn]);

    final interceptor = ErrorInterceptor();
    Future<void> handleMutationFailure() async {
      final handler = _TestErrorInterceptorHandler();
      final completed = handler.completed;
      interceptor.onError(
        failure(
          requestOptions: options(path: '/posts.json', method: 'POST'),
        ),
        handler,
      );
      await tester.pump();
      expect(handler.isCompleted, isTrue);
      await completed;
    }

    await handleMutationFailure();
    expect(find.text(S.current.network_vpnDirectHint), findsOneWidget);

    await handleMutationFailure();
    expect(find.text(S.current.network_vpnDirectHint), findsNothing);
    expect(find.text(S.current.error_requestFailed), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
  });
}

class _TestErrorInterceptorHandler extends ErrorInterceptorHandler {
  Future<void> get completed async {
    try {
      await future;
    } catch (_) {
      // ErrorInterceptor 通过 handler.next 保留原始 DioException。
    }
  }
}
