import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/models/user.dart';

void main() {
  group('User chat capability', () {
    test('parses true and false values from current user JSON', () {
      final allowed = User.fromJson({
        'id': 1,
        'username': 'allowed',
        'trust_level': 1,
        'can_chat': true,
      });
      final denied = User.fromJson({
        'id': 2,
        'username': 'denied',
        'trust_level': 0,
        'can_chat': false,
      });

      expect(allowed.canChat, isTrue);
      expect(denied.canChat, isFalse);
    });

    test('keeps a missing capability unknown', () {
      final user = User.fromJson({
        'id': 1,
        'username': 'legacy',
        'trust_level': 1,
      });

      expect(user.canChat, isNull);
    });

    test('preserves the capability through cache serialization', () {
      final user = User(
        id: 1,
        username: 'cached',
        trustLevel: 1,
        canChat: false,
      );

      final restored = User.fromCacheJson(user.toCacheJson());

      expect(restored.canChat, isFalse);
    });

    test('copyWith can merge a current-user capability', () {
      final profile = User(id: 1, username: 'merged', trustLevel: 0);

      expect(profile.copyWith(canChat: false).canChat, isFalse);
      expect(profile.copyWith().canChat, isNull);
    });
  });
}
