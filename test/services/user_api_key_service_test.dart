import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/storage/resilient_secure_storage.dart';
import 'package:fluxdo/services/user_api_key_service.dart';

void main() {
  test('one_time_password key 登录后会自我撤销并清除本地副本', () async {
    final storage = _MemorySecureStorage('temporary-user-api-key');
    final adapter = _RecordingAdapter(statusCode: 200);
    final dio = Dio(BaseOptions(baseUrl: 'https://openxinsheng.com'))
      ..httpClientAdapter = adapter;
    final service = UserApiKeyService.forTesting(storage: storage);

    await service.burnAfterLoginIfUseless(dio);

    expect(UserApiKeyService.keyWorthKeeping, isFalse);
    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/user-api-key/revoke');
    expect(adapter.request?.headers['User-Api-Key'], 'temporary-user-api-key');
    expect(adapter.request?.extra['skipAuthCheck'], isTrue);
    expect(adapter.request?.extra['skipCsrf'], isTrue);
    expect(await service.readApiKey(), isNull);
  });

  test('服务端撤销失败时仍清除无用途的本地 key', () async {
    final storage = _MemorySecureStorage('temporary-user-api-key');
    final dio = Dio(BaseOptions(baseUrl: 'https://openxinsheng.com'))
      ..httpClientAdapter = _RecordingAdapter(statusCode: 500);
    final service = UserApiKeyService.forTesting(storage: storage);

    await service.burnAfterLoginIfUseless(dio);

    expect(await service.readApiKey(), isNull);
  });
}

class _MemorySecureStorage implements ResilientSecureStorage {
  _MemorySecureStorage(this.value);

  String? value;

  @override
  Future<String?> read({required String key}) async => value;

  @override
  Future<void> write({required String key, required String value}) async {
    this.value = value;
  }

  @override
  Future<void> delete({required String key}) async {
    value = null;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.statusCode});

  final int statusCode;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
