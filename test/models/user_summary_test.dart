import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/models/user.dart';

void main() {
  test('parses badges from user_summary and supports top-level fallback', () {
    final inSummary = UserSummary.fromJson({
      'user_summary': {
        'badges': [
          {
            'id': 1,
            'name': 'Anniversary',
            'description': '',
            'badge_type_id': 3,
            'slug': 'anniversary',
          },
        ],
      },
    });
    expect(inSummary.badges.single.slug, 'anniversary');

    final topLevel = UserSummary.fromJson({
      'user_summary': <String, dynamic>{},
      'badges': [
        {
          'id': 2,
          'name': 'First Quote',
          'description': '',
          'badge_type_id': 3,
          'slug': 'first-quote',
        },
      ],
    });
    expect(topLevel.badges.single.slug, 'first-quote');
  });

  test('treats a null badge name as empty', () {
    final summary = UserSummary.fromJson({
      'user_summary': {
        'badges': [
          {
            'id': 3,
            'name': null,
            'description': null,
            'badge_type_id': 3,
            'slug': 'unnamed-badge',
          },
        ],
      },
    });

    expect(summary.badges.single.name, isEmpty);
    expect(summary.badges.single.slug, 'unnamed-badge');
  });

  test('treats a null badge type id as unknown', () {
    final summary = UserSummary.fromJson({
      'user_summary': {
        'badges': [
          {
            'id': 4,
            'name': 'Unknown Type',
            'description': '',
            'badge_type_id': null,
            'slug': 'unknown-type',
          },
        ],
      },
    });

    expect(summary.badges.single.badgeTypeId, 0);
  });
}
