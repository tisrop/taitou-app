import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_toolbar.dart';
import 'package:fluxdo/widgets/post/reply_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _wrap(Widget child) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        navigatorKey: navigatorKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('回复弹层避开顶部系统状态栏', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    late BuildContext launcherContext;
    await tester.pumpWidget(
      await _wrap(
        Builder(
          builder: (context) {
            launcherContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final replyFuture = showReplySheet(
      context: launcherContext,
      topicTitle: '测试主题',
    );
    await tester.pumpAndSettle();

    final targetTop = tester
        .getTopLeft(find.byKey(const ValueKey('replyComposerTarget')))
        .dy;
    expect(targetTop, greaterThanOrEqualTo(32));

    await tester.tap(find.byKey(const ValueKey('replyComposerClose')));
    await tester.pumpAndSettle();
    await replyFuture;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('回复编辑器按参考布局展示顶部目标、顶部工具栏和底部操作栏', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _wrap(const ReplySheet(topicTitle: '测试主题')));
    await tester.pump();

    expect(find.byKey(const ValueKey('replyComposerTarget')), findsOneWidget);
    expect(find.text('话题'), findsOneWidget);
    expect(find.text('测试主题'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('replyComposerTopicContext')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('replyComposerMenu')), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerClose')), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerFooter')), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerSend')), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerDiscard')), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerUpload')), findsOneWidget);

    final toolbarTop = tester.getTopLeft(find.byType(MarkdownToolbar)).dy;
    final editorTop = tester.getTopLeft(find.byType(TextField).last).dy;
    expect(toolbarTop, lessThan(editorTop), reason: '回复场景的格式工具栏应位于正文上方');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
