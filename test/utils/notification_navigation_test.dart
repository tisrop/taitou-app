import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/chat_channel_page.dart';
import 'package:fluxdo/providers/chat/chat_list_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/utils/notification_navigation.dart';

class _TestChatListNotifier extends ChatListNotifier {
  _TestChatListNotifier(super.channelId);

  @override
  ChatListState build() => const ChatListState(isLoading: false);

  @override
  Future<bool> loadAround(int messageId) async => false;
}

class _TestCurrentUserNotifier extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

void main() {
  testWidgets('点击聊天室 @ 通知会打开频道并定位到目标消息', (tester) async {
    final notification = DiscourseNotification(
      id: 101,
      userId: 7,
      notificationType: NotificationType.chatMention,
      read: true,
      highPriority: true,
      createdAt: DateTime.utc(2026, 8, 4),
      data: NotificationData(
        chatChannelId: 12,
        chatMessageId: 456,
        chatChannelTitle: '站务讨论',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatListProvider(12).overrideWith(() => _TestChatListNotifier(12)),
          currentUserProvider.overrideWith(_TestCurrentUserNotifier.new),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    handleNotificationTap(context, ref, notification),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final page = tester.widget<ChatChannelPage>(find.byType(ChatChannelPage));
    expect(page.channelId, 12);
    expect(page.initialMessageId, 456);
    expect(page.title, '站务讨论');
  });
}
