import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/flatten/inline_flattener.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';
import 'package:fluxdo_render/src/render/hashtag_icons.dart';
import 'package:fluxdo_render/src/selection/projection.dart';

const _hashtag = LinkRun(
  href: '/c/dev/4',
  children: [TextRun('开发调优')],
  hashtagRef: 'dev',
  hashtagIcon: 'folder',
);

void main() {
  const flattener = InlineFlattener();
  const baseStyle = TextStyle(fontSize: 14);

  tearDown(() {
    hashtagIconResolver = null;
    hashtagTapHandler = null;
  });

  testWidgets('药丸尺寸随内容走并使用宿主图标', (tester) async {
    String? resolvedName;
    String? resolvedHref;
    hashtagIconResolver = (_, iconName, href) {
      resolvedName = iconName;
      resolvedHref = href;
      return Icons.star_outline;
    };
    final result = flattener.flatten(const [
      TextRun('看看 '),
      _hashtag,
      TextRun(' 板块'),
    ], baseStyle);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 600, child: Text.rich(result.span)),
        ),
      ),
    );

    final text = find.text('#开发调优');
    final pill = find
        .ancestor(of: text, matching: find.byType(Container))
        .first;
    final size = tester.getSize(pill);
    expect(size.height, lessThan(40));
    expect(size.width, lessThan(200));
    expect(resolvedName, 'folder');
    expect(resolvedHref, '/c/dev/4');
    expect(find.byIcon(Icons.star_outline), findsOneWidget);
  });

  testWidgets('宿主接管点击后不再调用普通链接回调', (tester) async {
    String? tappedRef;
    String? fallbackHref;
    late FlattenResult result;

    hashtagTapHandler = (_, href, ref, label) {
      expect(href, '/c/dev/4');
      expect(label, '开发调优');
      tappedRef = ref;
      return true;
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              result = flattener.flatten(
                const [_hashtag],
                baseStyle,
                context: context,
                linkHandler: (_, href) => fallbackHref = href,
              );
              return Text.rich(result.span);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('#开发调优'));
    expect(tappedRef, 'dev');
    expect(fallbackHref, isNull);
  });

  testWidgets('宿主拒绝接管时退回普通链接回调', (tester) async {
    String? fallbackHref;
    hashtagTapHandler = (_, _, _, _) => false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final result = flattener.flatten(
                const [_hashtag],
                baseStyle,
                context: context,
                linkHandler: (_, href) => fallbackHref = href,
              );
              return Text.rich(result.span);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('#开发调优'));
    expect(fallbackHref, '/c/dev/4');
  });

  test('选区与编辑坐标把药丸视为一个原子', () {
    final result = flattener.flatten(const [_hashtag], baseStyle);
    final entry = result.projection.entries.single;

    expect(entry.kind, ProjectionKind.hashtag);
    expect(entry.renderLen, 1);
    expect(entry.logicalText, '#开发调优');
    expect(result.projection.contentLength, 1);
  });
}
