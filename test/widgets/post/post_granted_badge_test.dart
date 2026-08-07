import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_granted_badge.dart';

void main() {
  Widget host(GrantedBadge badge) {
    return MaterialApp(
      home: Scaffold(body: PostGrantedBadgeIcon(badge: badge)),
    );
  }

  test('GrantedBadge.fromJson 解析嵌套徽章说明', () {
    final badge = GrantedBadge.fromJson({
      'badge': {
        'id': 1,
        'name': 'Devotee',
        'description': '连续访问 365 天',
        'slug': 'devotee',
      },
    });

    expect(badge.description, '连续访问 365 天');
  });

  testWidgets('Tooltip 优先显示去除 HTML 的徽章说明', (tester) async {
    const badge = GrantedBadge(
      id: 1,
      name: 'Devotee',
      description: '连续 <a href="/badges">365</a> 天 &amp; 保持活跃',
      icon: 'certificate',
      slug: 'devotee',
    );

    await tester.pumpWidget(host(badge));

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '连续 365 天 & 保持活跃');
  });

  testWidgets('说明为空时 Tooltip 回退到徽章名称', (tester) async {
    const badge = GrantedBadge(
      id: 1,
      name: 'Devotee',
      description: '   ',
      icon: 'certificate',
      slug: 'devotee',
    );

    await tester.pumpWidget(host(badge));

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Devotee');
  });
}
