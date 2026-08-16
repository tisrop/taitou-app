import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/common/visual/smart_avatar.dart';
import 'package:fluxdo/widgets/notification/notification_item.dart';

void main() {
  Widget buildTestApp(DiscourseNotification notification) {
    return TranslationProvider(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: Scaffold(
          body: NotificationItem(notification: notification, onTap: () {}),
        ),
      ),
    );
  }

  testWidgets('uses the reference notification icons', (tester) async {
    Future<void> pumpNotification(
      NotificationType type,
      FaIconData expectedIcon,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          DiscourseNotification(
            id: 1,
            userId: 1,
            notificationType: type,
            read: true,
            highPriority: false,
            createdAt: DateTime(2026, 8, 4),
            data: NotificationData(
              displayUsername: '阿拉丁',
              badgeName: '编辑者',
              chatChannelTitle: 'General',
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) => widget is FaIcon && widget.icon == expectedIcon.data,
        ),
        findsOneWidget,
      );
    }

    await pumpNotification(
      NotificationType.privateMessage,
      FontAwesomeIcons.solidEnvelope,
    );
    await pumpNotification(NotificationType.replied, FontAwesomeIcons.reply);
    await pumpNotification(
      NotificationType.grantedBadge,
      FontAwesomeIcons.certificate,
    );
    await pumpNotification(
      NotificationType.chatGroupMention,
      FontAwesomeIcons.solidComment,
    );
  });

  testWidgets('uses compact icon, author, topic and absolute date layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final createdAt = DateTime(2026, 7, 31);
    final notification = DiscourseNotification(
      id: 2,
      userId: 1,
      notificationType: NotificationType.replied,
      read: true,
      highPriority: false,
      createdAt: createdAt,
      data: NotificationData(
        displayUsername: '阿拉丁',
        topicTitle: '给咱们论坛捣鼓了一个app',
      ),
    );

    await tester.pumpWidget(buildTestApp(notification));

    expect(find.byType(SmartAvatar), findsNothing);
    expect(find.text('阿拉丁'), findsOneWidget);
    expect(find.text('给咱们论坛捣鼓了一个app'), findsOneWidget);
    expect(find.text(notification.description), findsNothing);
    expect(find.text('7月31日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows concrete channel and group for chat group mentions', (
    tester,
  ) async {
    final notification = DiscourseNotification(
      id: 4,
      userId: 1,
      notificationType: NotificationType.chatGroupMention,
      read: true,
      highPriority: false,
      createdAt: DateTime(2026, 7, 31),
      data: NotificationData(
        displayUsername: '阿拉丁',
        groupName: 'all',
        chatChannelTitle: 'General',
      ),
    );

    await tester.pumpWidget(buildTestApp(notification));

    expect(find.text('阿拉丁'), findsOneWidget);
    expect(find.text('在“General”中提及“@all”'), findsOneWidget);
    expect(find.text('7月31日'), findsOneWidget);
    expect(find.textContaining('天前'), findsNothing);
  });

  testWidgets('uses a full-row tinted background for unread notifications', (
    tester,
  ) async {
    final notification = DiscourseNotification(
      id: 3,
      userId: 1,
      notificationType: NotificationType.grantedBadge,
      read: false,
      highPriority: false,
      createdAt: DateTime.now(),
      data: NotificationData(badgeName: '编辑者'),
    );

    await tester.pumpWidget(buildTestApp(notification));

    final context = tester.element(find.byType(NotificationItem));
    final colorScheme = Theme.of(context).colorScheme;
    final expectedColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.12),
      colorScheme.surface,
    );
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('notification-3')),
    );

    expect(material.color, expectedColor);
    expect(find.text(notification.title), findsOneWidget);
    expect(find.text(notification.description), findsNothing);
  });
}
