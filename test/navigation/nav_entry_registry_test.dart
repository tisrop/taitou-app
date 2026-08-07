import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart';
import 'package:fluxdo/navigation/nav_entry_registry.dart';

void main() {
  group('chat navigation availability', () {
    final chatEntry = NavEntryRegistry.buildAll().singleWhere(
      (entry) => entry.id == NavEntryIds.chat,
    );

    test('requires login and chat access', () {
      expect(chatEntry.requiresLogin, isTrue);
      expect(chatEntry.requiresChatAccess, isTrue);
      expect(NavEntryRegistry.isAvailable(chatEntry, null), isFalse);
      expect(
        NavEntryRegistry.isAvailable(
          chatEntry,
          User(id: 1, username: 'denied', trustLevel: 0, canChat: false),
        ),
        isFalse,
      );
      expect(
        NavEntryRegistry.isAvailable(
          chatEntry,
          User(id: 2, username: 'allowed', trustLevel: 1, canChat: true),
        ),
        isTrue,
      );
    });

    test('keeps legacy unknown capability available', () {
      final legacyUser = User(id: 3, username: 'legacy', trustLevel: 1);

      expect(NavEntryRegistry.isAvailable(chatEntry, legacyUser), isTrue);
    });
  });
}
