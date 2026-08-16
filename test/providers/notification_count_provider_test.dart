import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/models.dart';
import 'package:fluxdo/providers/message_bus/notification_providers.dart';

class _TestCurrentUserNotifier extends CurrentUserNotifier {
  _TestCurrentUserNotifier(this.initialUser);

  final User? initialUser;

  @override
  FutureOr<User?> build() => initialUser;

  void emit(User? user) {
    state = AsyncValue.data(user);
  }
}

User _user({
  required int id,
  int allUnread = 0,
  int unread = 0,
  int highPriority = 0,
}) {
  return User(
    id: id,
    username: 'user$id',
    trustLevel: 1,
    allUnreadNotificationsCount: allUnread,
    unreadNotifications: unread,
    unreadHighPriorityNotifications: highPriority,
  );
}

void _expectCounts(
  NotificationCountState state, {
  int allUnread = 0,
  int unread = 0,
  int highPriority = 0,
}) {
  expect(state.allUnread, allUnread);
  expect(state.unread, unread);
  expect(state.highPriority, highPriority);
}

void main() {
  ProviderContainer createContainer(User? initialUser) {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(initialUser),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  _TestCurrentUserNotifier currentUserNotifier(ProviderContainer container) {
    return container.read(currentUserProvider.notifier)
        as _TestCurrentUserNotifier;
  }

  test('实时更新到达前会跟随同一用户的服务端通知计数', () async {
    final container = createContainer(_user(id: 1));
    await container.read(currentUserProvider.future);

    _expectCounts(container.read(notificationCountStateProvider));

    currentUserNotifier(
      container,
    ).emit(_user(id: 1, allUnread: 6, unread: 4, highPriority: 2));

    _expectCounts(
      container.read(notificationCountStateProvider),
      allUnread: 6,
      unread: 4,
      highPriority: 2,
    );
  });

  test('实时更新到达后忽略同一用户的过期服务端计数', () async {
    final container = createContainer(
      _user(id: 1, allUnread: 2, unread: 1, highPriority: 1),
    );
    await container.read(currentUserProvider.future);

    container
        .read(notificationCountStateProvider.notifier)
        .update(allUnread: 8, unread: 5, highPriority: 3);
    currentUserNotifier(
      container,
    ).emit(_user(id: 1, allUnread: 2, unread: 1, highPriority: 1));

    _expectCounts(
      container.read(notificationCountStateProvider),
      allUnread: 8,
      unread: 5,
      highPriority: 3,
    );
  });

  test('标记全部已读后不会被同一用户的旧计数恢复', () async {
    final container = createContainer(
      _user(id: 1, allUnread: 5, unread: 3, highPriority: 2),
    );
    await container.read(currentUserProvider.future);

    container.read(notificationCountStateProvider.notifier).markAllRead();
    currentUserNotifier(
      container,
    ).emit(_user(id: 1, allUnread: 5, unread: 3, highPriority: 2));

    _expectCounts(container.read(notificationCountStateProvider));
  });

  test('切换账号后重新采用新用户的服务端计数', () async {
    final container = createContainer(_user(id: 1));
    await container.read(currentUserProvider.future);

    container
        .read(notificationCountStateProvider.notifier)
        .update(allUnread: 9, unread: 7, highPriority: 4);
    currentUserNotifier(
      container,
    ).emit(_user(id: 2, allUnread: 3, unread: 2, highPriority: 1));

    _expectCounts(
      container.read(notificationCountStateProvider),
      allUnread: 3,
      unread: 2,
      highPriority: 1,
    );
  });
}
