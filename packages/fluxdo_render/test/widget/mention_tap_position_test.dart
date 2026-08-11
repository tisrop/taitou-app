/// mention 点击的全局坐标记录回归测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';
import 'package:fluxdo_render/src/render/mention_handler.dart';

void main() {
  setUp(() => lastInlineTapGlobalPosition = null);

  Future<void> pumpMentions(
    WidgetTester tester,
    List<InlineNode> inlines,
  ) async {
    const flattener = InlineFlattener();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final result = flattener.flatten(
                inlines,
                const TextStyle(fontSize: 14),
                emojiImageBuilder: (context, emoji, size) =>
                    SizedBox(width: size, height: size),
                context: context,
                mentionTapHandler: (_, _, _) {},
              );
              return Text.rich(
                result.span,
                textDirection: TextDirection.ltr,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('TextSpan mention 点击记录全局坐标', (tester) async {
    await pumpMentions(tester, const [
      MentionRun(username: 'bob', href: '/u/bob'),
    ]);
    expect(lastInlineTapGlobalPosition, isNull);
    await tester.tapAt(tester.getCenter(find.byType(RichText)));
    await tester.pump();
    expect(lastInlineTapGlobalPosition, isNotNull);
  });

  testWidgets('WidgetSpan mention 点击同样记录全局坐标', (tester) async {
    await pumpMentions(tester, const [
      MentionRun(
        username: 'bob',
        href: '/u/bob',
        statusEmoji: EmojiRun(name: 'coffee', url: 'x'),
      ),
    ]);
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(lastInlineTapGlobalPosition, isNotNull);
  });
}
