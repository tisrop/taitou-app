import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_ui/m3e_ui.dart';

void main() {
  testWidgets('顶部拖动不重建列表子树(树形状稳定)', (tester) async {
    final controller = ScrollController();
    final listKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: M3eRefreshIndicator(
            onRefresh: () async {},
            child: ListView.builder(
              key: listKey,
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: 100,
              itemBuilder: (_, i) => SizedBox(height: 40, child: Text('$i')),
            ),
          ),
        ),
      ),
    );
    final elementBefore = listKey.currentContext!;

    // 在顶部轻拖(触发 drag 状态翻转)再松手取消。
    await tester.drag(find.byType(ListView), const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 树形状稳定:同一个 Element,列表未被拆掉重建。
    expect(listKey.currentContext, same(elementBefore));

    // 先滚下去,再在中途来回拖,位置不能被重置。
    controller.jumpTo(400);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.offset, greaterThan(300));
    expect(listKey.currentContext, same(elementBefore));
  });

  testWidgets('完整下拉刷新流程', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: M3eRefreshIndicator(
            onRefresh: () async => refreshed++,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [for (var i = 0; i < 20; i++) SizedBox(height: 40, child: Text('$i'))],
            ),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // snap
    await tester.pump(const Duration(seconds: 1)); // refresh 完成
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新圆片在 SizeTransition 内保留阴影空间', (tester) async {
    final refreshCompleter = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: M3eRefreshIndicator(
            onRefresh: () => refreshCompleter.future,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 1000)],
            ),
          ),
        ),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final badge = find.byWidgetPredicate(
      (widget) =>
          widget is Material &&
          widget.elevation == 3 &&
          widget.shape is CircleBorder,
    );
    expect(badge, findsOneWidget);

    final reveal = find.ancestor(
      of: badge,
      matching: find.byType(SizeTransition),
    );
    expect(reveal, findsOneWidget);

    final badgeRect = tester.getRect(badge);
    final revealRect = tester.getRect(reveal);
    expect(badgeRect.top, 40, reason: '增加阴影留白后应保持原 displacement');
    expect(
      revealRect.bottom - badgeRect.bottom,
      greaterThanOrEqualTo(6),
      reason: '裁剪边界应在圆片下方保留阴影空间',
    );

    refreshCompleter.complete();
    await tester.pumpAndSettle();
  });
}
