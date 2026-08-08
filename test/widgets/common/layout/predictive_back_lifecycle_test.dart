import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/layout/predictive_back_cupertino_transitions.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> sendBackGesture(
    String method, [
    Map<String, Object?>? arguments,
  ]) {
    return binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  Future<GlobalKey<NavigatorState>> pumpNavigator(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          platform: TargetPlatform.android,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android:
                  PredictiveBackCupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('next page')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    return navigatorKey;
  }

  Future<void> startGesture(WidgetTester tester) async {
    await sendBackGesture('startBackGesture', {
      'touchOffset': <double>[0, 300],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await tester.pump();
    await sendBackGesture('updateBackGestureProgress', {
      'touchOffset': <double>[100, 300],
      'progress': 0.4,
      'swipeEdge': 0,
    });
    await tester.pump();
  }

  testWidgets(
    '后台打断预测返回后会取消手势并保持后续手势可用',
    (tester) async {
      final navigatorKey = await pumpNavigator(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await startGesture(tester);
      expect(navigatorKey.currentState!.userGestureInProgress, isTrue);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(navigatorKey.currentState!.userGestureInProgress, isFalse);
      expect(find.text('next page'), findsOneWidget);

      await startGesture(tester);
      expect(navigatorKey.currentState!.userGestureInProgress, isTrue);
      await sendBackGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('next page'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'commit 收尾期间锁屏不会破坏后续预测返回',
    (tester) async {
      final navigatorKey = await pumpNavigator(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await startGesture(tester);
      await sendBackGesture('commitBackGesture');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await startGesture(tester);
      expect(
        navigatorKey.currentState!.userGestureInProgress,
        isTrue,
        reason: 'commit 收尾期间的生命周期事件不能让手势计数下溢',
      );
      await sendBackGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('next page'), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
