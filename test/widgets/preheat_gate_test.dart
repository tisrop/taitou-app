import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/common/misc/error_view.dart';
import 'package:fluxdo/widgets/preheat_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    PackageInfo.setMockInitialValues(
      appName: 'Taitou',
      packageName: 'com.openxinsheng.taitou',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('预加载超过阻塞上限后先展示主页', (tester) async {
    final preload = Completer<void>();

    await tester.pumpWidget(
      _TestApp(
        child: PreheatGate(
          maxBlockingDuration: const Duration(milliseconds: 100),
          preloadOverride: () => preload.future,
          warmupOverride: () {},
          child: const Text('主页内容'),
        ),
      ),
    );

    expect(find.text('主页内容'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('主页内容'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);

    preload.complete();
    await tester.pump();
  });

  testWidgets('阻塞窗口内预加载失败时仍显示错误页', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: PreheatGate(
          maxBlockingDuration: const Duration(seconds: 1),
          preloadOverride: () =>
              Future<void>.error(StateError('preload failed')),
          warmupOverride: () {},
          child: const Text('主页内容'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('主页内容'), findsNothing);
  });

  testWidgets('超时后的迟到错误不会把主页切回错误页', (tester) async {
    final preload = Completer<void>();

    await tester.pumpWidget(
      _TestApp(
        child: PreheatGate(
          maxBlockingDuration: Duration.zero,
          preloadOverride: () => preload.future,
          warmupOverride: () {},
          child: const Text('主页内容'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('主页内容'), findsOneWidget);

    preload.completeError(StateError('late failure'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('主页内容'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        navigatorKey: navigatorKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: child,
      ),
    );
  }
}
