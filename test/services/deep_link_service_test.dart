import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/constants.dart';
import 'package:fluxdo/services/deep_link_service.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  final pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DeepLinkService.instance.dispose();
  });

  test('canHandleUri 只接受受支持的 scheme 和 host', () {
    final service = DeepLinkService.instance;

    expect(
      service.canHandleUri(Uri.parse('${AppConstants.baseUrl}/t/123')),
      isTrue,
    );
    expect(
      service.canHandleUri(
        Uri.parse('https://www.${AppConstants.baseHost}/t/123'),
      ),
      isTrue,
    );
    expect(
      service.canHandleUri(
        Uri.parse('https://meta.${AppConstants.baseHost}/latest'),
      ),
      isTrue,
    );
    expect(
      service.canHandleUri(Uri.parse('${AppConstants.appScheme}://topic/123')),
      isTrue,
    );
    expect(
      service.canHandleUri(Uri.parse('https://example.com/t/123')),
      isFalse,
    );
    expect(
      service.canHandleUri(Uri.parse('ftp://${AppConstants.baseHost}/t/123')),
      isFalse,
    );
  });

  testWidgets('handleUri 不接管非本站的话题路径', (tester) async {
    BuildContext? capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final context = capturedContext!;
    DeepLinkService.instance.updateContext(context);
    DeepLinkService.instance.handleUri(Uri.parse('https://example.com/t/123'));
    await tester.pump();

    expect(Navigator.of(context).canPop(), isFalse);
  });

  testWidgets('handleUri 支持 taitou 话题链接', (tester) async {
    BuildContext? capturedContext;
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final context = capturedContext!;
    observer.pushedRoutes.clear();
    DeepLinkService.instance.updateContext(context);
    DeepLinkService.instance.handleUri(
      Uri.parse('${AppConstants.appScheme}://topic/123/5'),
    );

    expect(observer.pushedRoutes, hasLength(1));
    expect(Navigator.of(context).canPop(), isTrue);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('handleUri 支持 taitou 用户链接', (tester) async {
    BuildContext? capturedContext;
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final context = capturedContext!;
    observer.pushedRoutes.clear();
    DeepLinkService.instance.updateContext(context);
    DeepLinkService.instance.handleUri(
      Uri.parse('${AppConstants.appScheme}://user/alice'),
    );

    expect(observer.pushedRoutes, hasLength(1));
    expect(Navigator.of(context).canPop(), isTrue);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('handleUri 对 taitou 路由大小写不敏感', (tester) async {
    BuildContext? capturedContext;
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final context = capturedContext!;
    observer.pushedRoutes.clear();
    DeepLinkService.instance.updateContext(context);
    DeepLinkService.instance.handleUri(
      Uri.parse('${AppConstants.appScheme}://Topic/123'),
    );

    expect(observer.pushedRoutes, hasLength(1));
    expect(Navigator.of(context).canPop(), isTrue);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  });
}
