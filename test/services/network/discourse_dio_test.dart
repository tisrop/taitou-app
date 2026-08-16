import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/discourse_dio.dart';

void main() {
  DioException responseFailure({
    required String method,
    required int statusCode,
  }) {
    final options = RequestOptions(path: '/test', method: method);
    return DioException.badResponse(
      statusCode: statusCode,
      requestOptions: options,
      response: Response<void>(requestOptions: options, statusCode: statusCode),
    );
  }

  test('GET 收到 429 时不使用固定短延迟自动重试', () {
    final error = responseFailure(method: 'GET', statusCode: 429);

    expect(DiscourseDio.shouldRetryReadRequest(error, 1), isFalse);
  });

  test('幂等读取仍会重试临时服务端错误', () {
    final error = responseFailure(method: 'GET', statusCode: 503);

    expect(DiscourseDio.shouldRetryReadRequest(error, 1), isTrue);
  });

  test('写请求不会因临时服务端错误自动重放', () {
    final error = responseFailure(method: 'POST', statusCode: 503);

    expect(DiscourseDio.shouldRetryReadRequest(error, 1), isFalse);
  });
}
