import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/chat/chat_message.dart';
import 'package:fluxdo/widgets/chat/chat_message_action_sheet.dart';

void main() {
  const author = ChatMessageUser(
    id: 2,
    username: 'bob',
    name: 'Bob',
    avatarTemplate: '',
  );

  testWidgets('普通频道消息显示基础操作，并按权限显示举报', (tester) async {
    await tester.pumpWidget(
      _testApp(
        message: const ChatMessage(
          id: 10,
          message: '频道消息',
          chatChannelId: 3,
          user: author,
          availableFlags: ['spam'],
        ),
        canModerate: false,
        canDelete: false,
        canReport: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_rounded), findsNothing);
    expect(find.byIcon(Icons.push_pin_rounded), findsNothing);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);
    expect(find.byIcon(Icons.add_reaction_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
  });

  testWidgets('管理操作和当前收藏、置顶状态正确显示', (tester) async {
    await tester.pumpWidget(
      _testApp(
        message: const ChatMessage(
          id: 11,
          message: '需要管理的消息',
          chatChannelId: 3,
          user: author,
          bookmarkId: 99,
          pinned: true,
          reactions: [
            ChatMessageReaction(emoji: '+1', count: 2, reacted: true),
          ],
        ),
        canModerate: true,
        canDelete: true,
        canReport: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(find.byIcon(Icons.flag_rounded), findsNothing);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });
}

Widget _testApp({
  required ChatMessage message,
  required bool canModerate,
  required bool canDelete,
  required bool canReport,
}) {
  return TranslationProvider(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          height: 800,
          child: ChatMessageActionSheet(
            message: message,
            canModerate: canModerate,
            canDelete: canDelete,
            canReport: canReport,
          ),
        ),
      ),
    ),
  );
}
