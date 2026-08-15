import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_toolbar.dart';
import 'package:fluxdo/widgets/post/reply_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _wrap(
  Widget child, {
  Map<String, Object> initialPreferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
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

    Navigator.of(launcherContext).pop();
    await tester.pumpAndSettle();
    await replyFuture;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('回复编辑器按参考布局展示顶部操作、底部工具栏和工具网格', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await _wrap(
        const ReplySheet(topicTitle: '测试主题'),
        initialPreferences: const {'pref_use_rich_composer': true},
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('replyComposerTarget')), findsOneWidget);
    expect(find.text('回复话题'), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerMenu')), findsNothing);
    expect(find.byKey(const ValueKey('replyComposerDiscard')), findsOneWidget);
    expect(find.text('舍弃'), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerSend')), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('replyComposerDragHandle'))),
      const Size(36, 5),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('replyComposerSend'))),
      const Size(84, 44),
    );
    expect(find.byKey(const ValueKey('replyComposerFooter')), findsNothing);
    expect(find.byKey(const ValueKey('replyComposerUpload')), findsNothing);
    expect(find.byKey(const ValueKey('replyComposerClose')), findsNothing);
    expect(
      find.byKey(const ValueKey('markdownToolbarPreview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('markdownToolbarSwitchMode')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('markdownToolbarEmojiPill'))),
      const Size(48, 48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('markdownToolbarActionsPill'))),
      const Size(92, 48),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('markdownToolbarPreview'))).dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('markdownToolbarMoreTools')))
            .dx,
      ),
      reason: '加号旁边只能保留一个位于其左侧的预览按钮',
    );

    final toolbarTop = tester.getTopLeft(find.byType(MarkdownToolbar)).dy;
    final editorTop = tester.getTopLeft(find.byType(TextField).last).dy;
    expect(toolbarTop, greaterThan(editorTop), reason: '格式工具栏应贴在正文底部');

    await tester.tap(find.byKey(const ValueKey('markdownToolbarMoreTools')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('markdownToolPanel')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('markdownToolPanel'))).height,
      336,
    );
    expect(find.text('更多工具'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('附件'), findsOneWidget);
    expect(find.text('音视频'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('粗体'), findsOneWidget);
    expect(find.text('斜体'), findsOneWidget);
    expect(find.text('删除线'), findsOneWidget);
    expect(find.text('无序列表'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('编辑和私信模式不渲染空的更多菜单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await _wrap(const ReplySheet(composePrivateMessage: true)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('replyComposerTarget')), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerMenu')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('replyComposerTarget')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<int>), findsNothing);

    final now = DateTime(2026, 8, 15);
    final post = Post(
      id: 1,
      username: 'tester',
      avatarTemplate: '',
      cooked: '<p>原文</p>',
      postNumber: 2,
      postType: 1,
      updatedAt: now,
      createdAt: now,
      likeCount: 0,
      replyCount: 0,
    );

    await tester.pumpWidget(
      await _wrap(ReplySheet(topicId: 1, editPost: post)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('replyComposerTarget')), findsOneWidget);
    expect(find.byKey(const ValueKey('replyComposerMenu')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('replyComposerTarget')));
    await tester.pump();
    expect(find.byType(PopupMenuItem<int>), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 61));
  });
}
