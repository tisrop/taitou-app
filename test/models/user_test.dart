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

  group('User assignment capability', () {
    test('parses can_assign from current user JSON', () {
      final user = User.fromJson({
        'id': 1,
        'username': 'assigner',
        'trust_level': 1,
        'can_assign': true,
      });

      expect(user.canAssign, isTrue);
    });

    test('preserves can_assign through cache serialization', () {
      final user = User(
        id: 1,
        username: 'cached-assigner',
        trustLevel: 1,
        canAssign: true,
      );

      final restored = User.fromCacheJson(user.toCacheJson());

      expect(restored.canAssign, isTrue);
    });

    test('copyWith preserves and can override can_assign', () {
      final user = User(
        id: 1,
        username: 'merged-assigner',
        trustLevel: 1,
        canAssign: true,
      );

      expect(user.copyWith().canAssign, isTrue);
      expect(user.copyWith(canAssign: false).canAssign, isFalse);
    });
  });
}
