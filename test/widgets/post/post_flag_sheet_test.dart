import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_flag_sheet.dart';

Widget _buildTestApp({required Widget child}) {
  return TranslationProvider(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('举报项同时显示标题和描述并替换用户名占位符', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        child: PostFlagSheet(
          postId: 42,
          postUsername: 'bob',
          service: DiscourseService(),
          loadFlagTypes: () async => const [
            FlagType(
              id: 2,
              nameKey: 'notify_user',
              name: '通知 @%{username}',
              description: '这是一段说明',
              isFlag: true,
              position: 1,
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('通知 @bob'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('post-flag-description-notify_user')),
      findsOneWidget,
    );
  });
}
