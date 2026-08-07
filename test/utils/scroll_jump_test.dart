import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:fluxdo/utils/scroll_jump.dart';

void main() {
  const itemHeight = 50.0;
  const viewportHeight = 600.0;

  Widget buildList(AutoScrollController controller, int itemCount) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: viewportHeight,
            child: ListView.builder(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) => AutoScrollTag(
                key: ValueKey(index),
                controller: controller,
                index: index,
                child: SizedBox(height: itemHeight, child: Text('item $index')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('贴底跳转遇内容收缩时不保留越界位置', (tester) async {
    final controller = AutoScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildList(controller, 20));
    controller.jumpTo(200);
    await tester.pumpAndSettle();

    final position = controller.position;
    expect(position.maxScrollExtent, 400);
    expect(controller.topAlignOffsetForScrollIndex(18), 900);

    await controller.jumpToRenderedScrollIndex(18);
    await tester.pump();
    expect(position.pixels, 400, reason: '应瞬时贴底，不留下动画窗口');

    await tester.pumpWidget(buildList(controller, 17));
    await tester.pump();

    expect(position.maxScrollExtent, 250);
    expect(position.pixels, lessThanOrEqualTo(250));
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.pixels, 250);
  });

  testWidgets('目标下方空间充足时精确顶对齐', (tester) async {
    final controller = AutoScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildList(controller, 20));
    await tester.pumpAndSettle();

    await controller.jumpToRenderedScrollIndex(4);
    await tester.pump();

    expect(controller.position.pixels, 200);
  });

  testWidgets('未渲染目标无法测量顶对齐位置', (tester) async {
    final controller = AutoScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildList(controller, 200));
    await tester.pumpAndSettle();

    expect(controller.topAlignOffsetForScrollIndex(199), isNull);
  });
}
