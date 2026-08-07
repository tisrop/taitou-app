import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/layout/anchor_guard_sliver.dart';

class _AnchorHarness extends StatefulWidget {
  const _AnchorHarness({super.key});

  @override
  State<_AnchorHarness> createState() => _AnchorHarnessState();
}

class _AnchorHarnessState extends State<_AnchorHarness> {
  final controller = ScrollController();
  double leadingHeight = 500;
  int structureSignature = 1;

  void insertContentAboveAnchor(double height) {
    AnchorGuardSliver.arm();
    setState(() {
      leadingHeight += height;
      structureSignature++;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          scrollCacheExtent: ScrollCacheExtent.pixels(2000),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: leadingHeight)),
            const SliverToBoxAdapter(
              child: SizedBox(
                key: ValueKey('single-box-anchor'),
                height: 1000,
                child: Text('推荐话题'),
              ),
            ),
            AnchorGuardSliver(structureSignature: structureSignature),
          ],
        ),
      ),
    );
  }
}

class _ReverseAnchorHarness extends StatefulWidget {
  const _ReverseAnchorHarness({super.key});

  @override
  State<_ReverseAnchorHarness> createState() => _ReverseAnchorHarnessState();
}

class _ReverseAnchorHarnessState extends State<_ReverseAnchorHarness> {
  final controller = ScrollController();
  final centerKey = GlobalKey();
  double bodyHeight = 40;

  void growBody(double delta) {
    AnchorGuardSliver.arm();
    setState(() => bodyHeight += delta);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget filler(Color color) =>
        SizedBox(height: 100, child: ColoredBox(color: color));

    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          center: centerKey,
          scrollCacheExtent: ScrollCacheExtent.pixels(2000),
          slivers: [
            const AnchorGuardSliver(),
            SliverList.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                if (index != 2) return filler(Colors.green);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      key: ValueKey('reverse-anchor'),
                      height: 40,
                      child: Text('折叠标题'),
                    ),
                    SizedBox(height: bodyHeight),
                  ],
                );
              },
            ),
            SliverList.builder(
              key: centerKey,
              itemCount: 10,
              itemBuilder: (context, index) => filler(Colors.amber),
            ),
            const AnchorGuardSliver(),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('单盒 sliver 上方插入内容时保持锚点位置', (tester) async {
    final harnessKey = GlobalKey<_AnchorHarnessState>();
    await tester.pumpWidget(_AnchorHarness(key: harnessKey));

    harnessKey.currentState!.controller.jumpTo(550);
    await tester.pump();
    await tester.pump();

    final anchor = find.byKey(const ValueKey('single-box-anchor'));
    final topBefore = tester.getTopLeft(anchor).dy;
    final offsetBefore = harnessKey.currentState!.controller.offset;
    expect(topBefore, lessThan(0));

    harnessKey.currentState!.insertContentAboveAnchor(120);
    await tester.pump();

    expect(tester.getTopLeft(anchor).dy, closeTo(topBefore, 0.01));
    expect(
      harnessKey.currentState!.controller.offset,
      closeTo(offsetBefore + 120, 0.01),
    );
  });

  testWidgets('反向半场连续多帧增长时每帧只消费一次修正', (tester) async {
    final harnessKey = GlobalKey<_ReverseAnchorHarnessState>();
    await tester.pumpWidget(_ReverseAnchorHarness(key: harnessKey));

    harnessKey.currentState!.controller.jumpTo(-450);
    await tester.pump();
    await tester.pump();

    final anchor = find.byKey(const ValueKey('reverse-anchor'));
    expect(anchor, findsOneWidget);
    final topBefore = tester.getTopLeft(anchor).dy;

    for (var frame = 0; frame < 6; frame++) {
      harnessKey.currentState!.growBody(16);
      await tester.pump(const Duration(milliseconds: 16));
      final topNow = tester.getTopLeft(anchor).dy;
      expect(
        topNow,
        closeTo(topBefore, 0.5),
        reason: '第 ${frame + 1} 帧不应漏修或重复消费修正',
      );
    }
  });
}
