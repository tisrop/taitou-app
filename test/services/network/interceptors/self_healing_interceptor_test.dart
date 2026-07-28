import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/self_healing_interceptor.dart';

void main() {
  test('非本站请求 401 不触发主站 session 自愈重试', () async {
    final adapter = _Counting401Adapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://external.example.com',
        validateStatus: (status) => status != null && status < 400,
      ),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(SelfHealingInterceptor(dio: dio));

    await expectLater(
      dio.get('/api/v1/oauth/user-info'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.fetchCount, 1);
  });
}

class _Counting401Adapter implements HttpClientAdapter {
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    return ResponseBody.fromString(
      '{"error":"unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
