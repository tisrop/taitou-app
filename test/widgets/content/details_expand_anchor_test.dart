import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

import 'package:fluxdo/widgets/common/layout/anchor_guard_sliver.dart';

final _detailsHtml =
    '<details><summary>标题</summary>'
    '<p>${'长文内容。' * 200}</p>'
    '</details>';

void main() {
  Widget buildList({required bool inBeforeRegion, required Key centerKey}) {
    Widget filler(Color color) => Container(height: 100, color: color);
    final details = FluxdoRender(
      cookedHtml: _detailsHtml,
      selectionEnabled: false,
    );
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          center: centerKey,
          slivers: [
            const AnchorGuardSliver(),
            SliverList.builder(
              itemCount: 10,
              itemBuilder: (context, index) =>
                  index == 2 && inBeforeRegion ? details : filler(Colors.green),
            ),
            SliverList.builder(
              key: centerKey,
              itemCount: 10,
              itemBuilder: (context, index) => index == 2 && !inBeforeRegion
                  ? details
                  : filler(Colors.amber),
            ),
            const AnchorGuardSliver(),
          ],
        ),
      ),
    );
  }

  Future<void> run(WidgetTester tester, {required bool inBeforeRegion}) async {
    FoldShiftHook.onFrame = AnchorGuardSliver.arm;
    addTearDown(() => FoldShiftHook.onFrame = null);

    final centerKey = UniqueKey();
    await tester.pumpWidget(
      buildList(inBeforeRegion: inBeforeRegion, centerKey: centerKey),
    );
    if (inBeforeRegion) {
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(-450);
      await tester.pump();
    }

    final header = find.text('标题');
    expect(header, findsOneWidget);
    final before = tester.getTopLeft(header);

    await tester.tap(header);
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = tester.getTopLeft(header);
      expect(
        (now.dy - before.dy).abs(),
        lessThan(1.0),
        reason:
            'inBeforeRegion=$inBeforeRegion 第 $frame 帧标题漂移 '
            '${(now.dy - before.dy).toStringAsFixed(1)}px',
      );
    }
  }

  testWidgets('details 在 after-center 区展开时标题保持原位', (tester) async {
    await run(tester, inBeforeRegion: false);
  });

  testWidgets('details 在 before-center 区展开时标题保持原位', (tester) async {
    await run(tester, inBeforeRegion: true);
  });
}
