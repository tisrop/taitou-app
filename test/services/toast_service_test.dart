import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/services/toast_service.dart';

void main() {
  testWidgets('多行 Toast 在窄屏和放大字体下完整显示', (tester) async {
    const message =
        '检测到 VPN，主站连接失败。请在代理工具中将 openxinsheng.com 和 '
        '*.openxinsheng.com 设置为 DIRECT。';

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    ToastService.show(
      message,
      type: ToastType.error,
      duration: const Duration(seconds: 1),
      maxLines: null,
    );
    await tester.pump(const Duration(milliseconds: 400));

    final textFinder = find.text(message);
    expect(textFinder, findsOneWidget);
    final text = tester.widget<Text>(textFinder);
    expect(text.maxLines, isNull);
    expect(text.overflow, TextOverflow.visible);
    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
