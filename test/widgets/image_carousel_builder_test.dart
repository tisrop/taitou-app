import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/builders/image_carousel_builder.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/image_utils.dart';

void main() {
  testWidgets('正文轮播图支持多种指针设备拖拽翻页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: buildImageCarousel(
              context: context,
              theme: Theme.of(context),
              images: const [],
              galleryInfo: GalleryInfo.fromImages(const []),
            ),
          ),
        ),
      ),
    );

    final pageViewContext = tester.element(find.byType(PageView));
    final behavior = ScrollConfiguration.of(pageViewContext);

    expect(
      behavior.dragDevices,
      containsAll(<PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }),
    );
  });
}
