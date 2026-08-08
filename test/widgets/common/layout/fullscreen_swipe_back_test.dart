import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/layout/fullscreen_swipe_back.dart';
import 'package:fluxdo/widgets/common/layout/predictive_back_cupertino_transitions.dart';

class _PassThroughTransitionsBuilder extends PageTransitionsBuilder {
  const _PassThroughTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

Widget _buildTransition({
  required PageRoute<void> route,
  required Widget child,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Builder(
      builder: (context) {
        return const FullscreenSwipeBackTransitionsBuilder(
          _PassThroughTransitionsBuilder(),
        ).buildTransitions(
          route,
          context,
          kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation,
          child,
        );
      },
    ),
  );
}

void main() {
  testWidgets('普通页面会挂载全屏指针监听器', (tester) async {
    final route = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(
      _buildTransition(
        route: route,
        child: const SizedBox(key: Key('page')),
      ),
    );

    expect(find.byType(Listener), findsOneWidget);
  });

  testWidgets('fullscreenDialog 不挂载水平返回手势', (tester) async {
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(
      _buildTransition(
        route: route,
        child: const SizedBox(key: Key('dialog')),
      ),
    );

    expect(find.byType(Listener), findsNothing);
  });

  testWidgets('页面中部右滑使用 Cupertino 跟手转场并返回上一页', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    const firstPageKey = Key('first-page');
    const secondPageKey = Key('second-page');

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          platform: TargetPlatform.android,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FullscreenSwipeBackTransitionsBuilder(
                PredictiveBackCupertinoPageTransitionsBuilder(),
              ),
            },
          ),
        ),
        home: const SizedBox.expand(key: firstPageKey),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.expand(key: secondPageKey),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(
      find.ancestor(
        of: find.byKey(secondPageKey),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );

    await gesture.moveBy(const Offset(360, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(secondPageKey), findsNothing);
    expect(find.byKey(firstPageKey), findsOneWidget);
  });
}
