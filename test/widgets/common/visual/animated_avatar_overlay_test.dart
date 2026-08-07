import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/visual/animated_avatar_overlay.dart';

void main() {
  const baseKey = Key('static-avatar');

  Widget buildStack(String url) {
    return MaterialApp(
      home: Scaffold(
        body: AnimatedAvatarStack(
          animatedUrl: url,
          base: const ColoredBox(key: baseKey, color: Colors.blue),
          size: 32,
        ),
      ),
    );
  }

  testWidgets('动图就绪后收起静态头像，失败时恢复兜底', (tester) async {
    await tester.pumpWidget(buildStack('https://example.invalid/avatar.gif'));

    expect(find.byKey(baseKey), findsOneWidget);
    var overlay = tester.widget<AnimatedAvatarOverlay>(
      find.byType(AnimatedAvatarOverlay),
    );

    overlay.onReadyChanged?.call(true);
    await tester.pump();
    expect(find.byKey(baseKey), findsNothing);

    overlay = tester.widget<AnimatedAvatarOverlay>(
      find.byType(AnimatedAvatarOverlay),
    );
    overlay.onReadyChanged?.call(false);
    await tester.pump();
    expect(find.byKey(baseKey), findsOneWidget);
  });

  testWidgets('切换动图 URL 时立即恢复静态头像等待新首帧', (tester) async {
    await tester.pumpWidget(buildStack('https://example.invalid/old.gif'));

    final overlay = tester.widget<AnimatedAvatarOverlay>(
      find.byType(AnimatedAvatarOverlay),
    );
    overlay.onReadyChanged?.call(true);
    await tester.pump();
    expect(find.byKey(baseKey), findsNothing);

    await tester.pumpWidget(buildStack('https://example.invalid/new.gif'));

    expect(find.byKey(baseKey), findsOneWidget);
    expect(
      tester
          .widget<AnimatedAvatarOverlay>(find.byType(AnimatedAvatarOverlay))
          .url,
      'https://example.invalid/new.gif',
    );
  });
}
