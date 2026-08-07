import 'package:flutter/material.dart';

/// 图标内联进段落：使用 WidgetSpan 按行中线对齐单字形 Text。
///
/// Material Symbols 的字形下降部接近零，直接放进 TextSpan 与正文共用
/// 基线时会产生视觉上飘。placeholder 的 middle 对齐可按同行正文样式
/// 计算行中线；根 TextSpan 没有样式时应显式传入 [textStyle]。
InlineSpan iconGlyphSpan(
  BuildContext context,
  IconData icon, {
  required double size,
  required Color color,
  double gap = 0,
  TextStyle? textStyle,
}) {
  final iconTheme = IconTheme.of(context);
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    style: textStyle,
    child: Text(
      String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: color,
        letterSpacing: gap,
        height: 1.0,
        fontVariations: <FontVariation>[
          if (iconTheme.fill != null) FontVariation('FILL', iconTheme.fill!),
          if (iconTheme.weight != null)
            FontVariation('wght', iconTheme.weight!),
          if (iconTheme.grade != null) FontVariation('GRAD', iconTheme.grade!),
          if (iconTheme.opticalSize != null)
            FontVariation('opsz', iconTheme.opticalSize!),
        ],
      ),
    ),
  );
}
