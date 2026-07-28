import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/window_state_service.dart';

void main() {
  group('WindowStateService.isBoundsRestorable', () {
    test('拒绝 Windows 最小化占位坐标', () {
      final bounds = Rect.fromLTWH(-32000, -32000, 160, 39);
      final visibleAreas = [Rect.fromLTWH(0, 0, 1920, 1040)];

      expect(
        WindowStateService.isBoundsRestorable(bounds, visibleAreas),
        isFalse,
      );
      expect(WindowStateService.isBoundsRestorable(bounds, const []), isFalse);
    });

    test('接受可视区域内的窗口坐标', () {
      final bounds = Rect.fromLTWH(120, 80, 1280, 720);
      final visibleAreas = [Rect.fromLTWH(0, 0, 1920, 1040)];

      expect(
        WindowStateService.isBoundsRestorable(bounds, visibleAreas),
        isTrue,
      );
    });

    test('接受负坐标显示器上的窗口坐标', () {
      final bounds = Rect.fromLTWH(-1200, 80, 900, 700);
      final visibleAreas = [
        Rect.fromLTWH(-1280, 0, 1280, 1024),
        Rect.fromLTWH(0, 0, 1920, 1040),
      ];

      expect(
        WindowStateService.isBoundsRestorable(bounds, visibleAreas),
        isTrue,
      );
    });

    test('拒绝无效尺寸', () {
      final visibleAreas = [Rect.fromLTWH(0, 0, 1920, 1040)];

      expect(
        WindowStateService.isBoundsRestorable(Rect.zero, visibleAreas),
        isFalse,
      );
    });

    test('没有显示器信息时保留有限且正尺寸的坐标', () {
      final bounds = Rect.fromLTWH(120, 80, 1280, 720);

      expect(WindowStateService.isBoundsRestorable(bounds, const []), isTrue);
    });
  });
}
