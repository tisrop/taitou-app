import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledCurrentUserNotifier extends CurrentUserNotifier {
  final session = Completer<bool>();
  final preloaded = Completer<User?>();
  final current = Completer<User?>();

  @override
  Future<bool> checkLoggedIn(DiscourseService service) => session.future;

  @override
  Future<User?> fetchPreloadedCurrentUser(DiscourseService service) =>
      preloaded.future;

  @override
  Future<User?> fetchCurrentUser(DiscourseService service) => current.future;
}

User _user({required int allUnread}) => User(
  id: 1,
  username: 'tester',
  trustLevel: 1,
  allUnreadNotificationsCount: allUnread,
  unreadNotifications: allUnread,
);

void main() {
  test('缓存、预加载与接口结果按就绪顺序渐进发布', () async {
    final cached = _user(allUnread: 9);
    SharedPreferences.setMockInitialValues({
      'current_user_cache': jsonEncode(cached.toCacheJson()),
      'current_user_cache_username': cached.username,
    });
    PreloadedDataService().reset();

    late _ControlledCurrentUserNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          () => notifier = _ControlledCurrentUserNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final cachedPublished = Completer<void>();
    final preloadedPublished = Completer<void>();
    final subscription = container.listen(currentUserProvider, (_, next) {
      final count = next.value?.allUnreadNotificationsCount;
      if (count == 0 && !cachedPublished.isCompleted) {
        cachedPublished.complete();
      }
      if (count == 7 && !preloadedPublished.isCompleted) {
        preloadedPublished.complete();
      }
    });
    addTearDown(subscription.close);

    await cachedPublished.future;
    expect(container.read(currentUserProvider).value?.username, 'tester');
    // 通知计数不写入会话缓存，首拍应为默认值，随后由 preloaded 补齐。
    expect(
      container.read(currentUserProvider).value?.allUnreadNotificationsCount,
      0,
    );

    notifier.session.complete(true);
    notifier.preloaded.complete(_user(allUnread: 7));
    await preloadedPublished.future;
    expect(
      container.read(currentUserProvider).value?.allUnreadNotificationsCount,
      7,
    );

    notifier.current.complete(_user(allUnread: 0));
    await container.read(currentUserProvider.future);
    expect(
      container.read(currentUserProvider).value?.allUnreadNotificationsCount,
      7,
    );
  });
}
