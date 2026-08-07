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
}
