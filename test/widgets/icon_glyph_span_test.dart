import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/common/text/icon_glyph_span.dart';

void main() {
  test('placeholder middle 使用当前 span 字体度量', () {
    ui.Paragraph build(double spanFontSize) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
        ..pushStyle(ui.TextStyle(fontSize: spanFontSize))
        ..addPlaceholder(12, 12, ui.PlaceholderAlignment.middle)
        ..addText('123');
      return builder.build()..layout(const ui.ParagraphConstraints(width: 300));
    }

    final small = build(11);
    final large = build(22);
    final smallRect = small.getBoxesForPlaceholders().first.toRect();
    final largeRect = large.getBoxesForPlaceholders().first.toRect();
    final smallCenter = smallRect.center.dy - small.alphabeticBaseline;
    final largeCenter = largeRect.center.dy - large.alphabeticBaseline;

    expect(
      (largeCenter - smallCenter).abs(),
      greaterThan(1),
      reason: 'middle 对齐应使用占位符所在 span 的样式度量',
    );
  });

  testWidgets('图标字形使用 WidgetSpan 并透传同行样式', (tester) async {
    const textStyle = TextStyle(fontSize: 11);
    late InlineSpan span;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = iconGlyphSpan(
              context,
              Icons.info_outline,
              size: 12,
              color: Colors.black,
              textStyle: textStyle,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(span, isA<WidgetSpan>());
    final widgetSpan = span as WidgetSpan;
    expect(widgetSpan.alignment, PlaceholderAlignment.middle);
    expect(widgetSpan.style, textStyle);
  });
}
