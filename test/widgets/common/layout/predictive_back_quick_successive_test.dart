import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/layout/predictive_back_cupertino_transitions.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> sendGesture(String method, [Map<String, Object?>? arguments]) {
    return binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  Future<bool> startGestureAndReadClaim() async {
    var claimed = false;
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('startBackGesture', {
          'touchOffset': <double>[0, 300],
          'progress': 0.0,
          'swipeEdge': 0,
        }),
      ),
      (ByteData? reply) {
        if (reply != null) {
          claimed = const StandardMethodCodec().decodeEnvelope(reply) == true;
        }
      },
    );
    return claimed;
  }

  Future<void> pumpNavigatorDuringPushTransition(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
                  builder: (_) => const Scaffold(body: Text('page B')),
                ),
              ),
              child: const Text('page A'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('page A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('page B'), findsOneWidget);
  }

  testWidgets(
    '路由转场中提交预测返回手势会返回上一层',
    (tester) async {
      await pumpNavigatorDuringPushTransition(tester);

      final claimed = await startGestureAndReadClaim();
      await tester.pump();
      expect(claimed, isTrue, reason: '转场期手势必须被认领，避免系统露底');

      await sendGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('page B'), findsNothing);
      expect(find.text('page A'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '路由转场中取消预测返回手势会保留当前页',
    (tester) async {
      await pumpNavigatorDuringPushTransition(tester);

      expect(await startGestureAndReadClaim(), isTrue);
      await tester.pump();
      await sendGesture('cancelBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('page B'), findsOneWidget);

      expect(await startGestureAndReadClaim(), isTrue);
      await tester.pump();
      await sendGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('page B'), findsNothing);
      expect(find.text('page A'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
