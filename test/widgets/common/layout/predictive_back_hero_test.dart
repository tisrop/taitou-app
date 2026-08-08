import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/layout/predictive_back_cupertino_transitions.dart';

/// Hero 路由 × 预测返回：关闭 shared-element 预览时仍应认领手势，
/// 让路由动画驱动带 transitionOnUserGestures 的 Hero 跟手飞行。
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

  Widget buildApp({
    required GlobalKey<NavigatorState> navigatorKey,
    required VoidCallback onFlight,
  }) {
    Widget buildHero(double size) {
      return Hero(
        tag: 'image',
        transitionOnUserGestures: true,
        flightShuttleBuilder: (_, _, _, _, _) {
          onFlight();
          return ColoredBox(
            color: Colors.red,
            child: SizedBox.square(dimension: size),
          );
        },
        child: ColoredBox(
          color: Colors.red,
          child: SizedBox.square(dimension: size),
        ),
      );
    }

    return MaterialApp(
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
          builder: (context) => Column(
            children: [
              buildHero(48),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      opaque: false,
                      pageBuilder: (_, _, _) => Scaffold(
                        backgroundColor: Colors.black,
                        body: Center(child: buildHero(240)),
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return buildPredictiveBackPageTransitions(
                              context,
                              animation,
                              secondaryAnimation,
                              child,
                              useSharedElementPreview: false,
                              fallbackBuilder: (_, animation, _, child) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                            );
                          },
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    '预测返回手势驱动配对 Hero 跟手飞行',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      var heroFlights = 0;

      await tester.pumpWidget(
        buildApp(navigatorKey: navigatorKey, onFlight: () => heroFlights++),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      heroFlights = 0;

      await sendGesture('startBackGesture', {
        'touchOffset': <double>[5, 300],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      await tester.pump();

      expect(navigatorKey.currentState!.userGestureInProgress, isTrue);

      await sendGesture('updateBackGestureProgress', {
        'touchOffset': <double>[80, 300],
        'progress': 0.3,
        'swipeEdge': 0,
      });
      await tester.pump();

      expect(heroFlights, greaterThan(0));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() ==
              '_PredictiveBackSharedElementPageTransition',
        ),
        findsNothing,
      );

      await sendGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(navigatorKey.currentState!.userGestureInProgress, isFalse);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    '取消预测返回后恢复查看器路由',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        buildApp(navigatorKey: navigatorKey, onFlight: () {}),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await sendGesture('startBackGesture', {
        'touchOffset': <double>[5, 300],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      await tester.pump();
      await sendGesture('updateBackGestureProgress', {
        'touchOffset': <double>[80, 300],
        'progress': 0.4,
        'swipeEdge': 0,
      });
      await tester.pump();

      await sendGesture('cancelBackGesture');
      await tester.pumpAndSettle();

      expect(navigatorKey.currentState!.userGestureInProgress, isFalse);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
