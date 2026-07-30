import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/gamification.dart';

void main() {
  group('GamificationLeaderboardResponse', () {
    test('parses leaderboard users and personal rank', () {
      final response = GamificationLeaderboardResponse.fromJson({
        'leaderboard': {
          'id': 4,
          'name': 'Community',
          'default_period': 'all_time',
          'from_date': '2026-01-01',
          'to_date': '2026-12-31',
          'period_filter_disabled': false,
        },
        'users': [
          {
            'id': 10,
            'username': 'alice',
            'name': 'Alice',
            'avatar_template':
                '/user_avatar/openxinsheng.com/alice/{size}/1.png',
            'total_score': 128,
            'position': 1,
          },
        ],
        'personal': {
          'user': {
            'id': 20,
            'username': 'bob',
            'avatar_template': '/letter_avatar_proxy/v4/letter/b/{size}.png',
            'total_score': 42,
          },
          'position': 8,
        },
      });

      expect(response.leaderboard.id, 4);
      expect(response.leaderboard.defaultPeriod, 'all_time');
      expect(response.leaderboard.fromDate, DateTime(2026));
      expect(response.leaderboard.toDate, DateTime(2026, 12, 31));
      expect(response.users.single.displayName, 'Alice');
      expect(response.users.single.totalScore, 128);
      expect(response.personal?.position, 8);
      expect(response.personal?.user.position, 8);
      expect(response.personal?.user.totalScore, 42);
      expect(response.isPreparing, isFalse);
    });

    test('parses the flat 202 response while scores are being generated', () {
      final response = GamificationLeaderboardResponse.fromJson({
        'id': 7,
        'name': 'Community',
        'default_period': 'monthly',
        'users': <dynamic>[],
        'reason': 'Leaderboard cache is not ready',
      });

      expect(response.leaderboard.id, 7);
      expect(response.users, isEmpty);
      expect(response.isPreparing, isTrue);
    });

    test('accepts numeric default period from older plugin responses', () {
      final response = GamificationLeaderboardResponse.fromJson({
        'leaderboard': {'id': 1, 'name': 'Global', 'default_period': 4},
        'users': <dynamic>[],
        'personal': <String, dynamic>{},
      });

      expect(response.leaderboard.defaultPeriod, '4');
      expect(response.personal, isNull);
    });
  });
}
