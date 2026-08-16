import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  group('PreloadedDataService.parsePositiveIntSetting', () {
    test('解析站点返回的整数和字符串配置', () {
      expect(PreloadedDataService.parsePositiveIntSetting(5), 5);
      expect(PreloadedDataService.parsePositiveIntSetting('12'), 12);
    });

    test('无效或非正数配置返回 null，以便请求省略 limit', () {
      expect(PreloadedDataService.parsePositiveIntSetting(null), isNull);
      expect(PreloadedDataService.parsePositiveIntSetting(0), isNull);
      expect(PreloadedDataService.parsePositiveIntSetting(-1), isNull);
      expect(PreloadedDataService.parsePositiveIntSetting('invalid'), isNull);
    });
  });

  test('首页缺少预加载数据时保持未加载并抛出解析错误', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: '<html><body>missing preload</body></html>',
            ),
          ),
        ),
      );
    final service = PreloadedDataService.forTesting(dio);

    await expectLater(service.ensureLoaded(), throwsA(isA<FormatException>()));
    expect(service.isLoaded, isFalse);
  });
}
