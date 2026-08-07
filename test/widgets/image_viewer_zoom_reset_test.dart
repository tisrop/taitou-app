import 'package:extended_image_lite/extended_image_lite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/image_viewer_page.dart';

void main() {
  Future<ImageGestureController> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Hero(
                  tag: 'test-image',
                  transitionOnUserGestures: true,
                  child: SizedBox(width: 40, height: 40),
                ),
                TextButton(
                  onPressed: () => ImageViewerPage.open(
                    context,
                    'https://example.com/image.png',
                    heroTag: 'test-image',
                  ),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    return tester
        .widget<GestureImageView>(find.byType(GestureImageView))
        .controller;
  }

  void zoomTo(ImageGestureController controller, double scale) {
    controller.details = GestureDetails(
      totalScale: scale,
      offset: Offset.zero,
      gestureDetails: controller.details,
    );
  }

  testWidgets('程序化返回在退场首帧归位图片缩放', (tester) async {
    final controller = await openViewer(tester);
    zoomTo(controller, 3);
    expect(controller.details?.totalScale, 3);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();

    expect(controller.details?.totalScale, 1);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
