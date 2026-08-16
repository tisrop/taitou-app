import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/services/navigation/back_exit_guard.dart';

void main() {
  test('超时前第二次返回允许退出，成功后重新开始计数', () {
    var now = DateTime(2026, 8, 7, 12);
    final guard = BackExitGuard(now: () => now);

    expect(guard.shouldExit(), isFalse);

    now = now.add(const Duration(seconds: 1));
    expect(guard.shouldExit(), isTrue);

    now = now.add(const Duration(milliseconds: 100));
    expect(guard.shouldExit(), isFalse);
  });

  test('达到或超过超时时间后需要重新按两次', () {
    var now = DateTime(2026, 8, 7, 12);
    final guard = BackExitGuard(now: () => now);

    expect(guard.shouldExit(), isFalse);

    now = now.add(const Duration(seconds: 2));
    expect(guard.shouldExit(), isFalse);

    now = now.add(const Duration(milliseconds: 500));
    expect(guard.shouldExit(), isTrue);
  });

  test('支持自定义双击退出时间窗口', () {
    var now = DateTime(2026, 8, 7, 12);
    final guard = BackExitGuard(
      timeout: const Duration(milliseconds: 500),
      now: () => now,
    );

    expect(guard.shouldExit(), isFalse);

    now = now.add(const Duration(milliseconds: 499));
    expect(guard.shouldExit(), isTrue);
  });
}
