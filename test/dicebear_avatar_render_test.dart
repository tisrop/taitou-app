import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jovial_svg/jovial_svg.dart';

import 'package:fluxdo/utils/svg_utils.dart';

/// openxinsheng 的默认头像来自 api.dicebear.com，是 **SVG**（站内 51 个活跃
/// 用户里 42 个如此）。旧实现按全 PNG 头像设计，自绘话题卡的解码
/// 路径没有 SVG 分支，SVG 抛异常后被空 catch 吞掉 → 列表头像永久空白。
///
/// 这里锁住 SvgUtils 这一侧的契约：能识别、sanitize 不破坏内容、jovial_svg
/// 能解析出有效 viewport，并且最终能光栅化成自绘话题卡可用的位图。
void main() {
  final bytes = File('test/dicebear_sample.svg').readAsBytesSync();

  test('dicebear 头像能被识别为 SVG', () {
    expect(SvgUtils.isSvgBytes(bytes), isTrue);
  });

  test('PNG 字节不会被误判成 SVG', () {
    expect(SvgUtils.isSvgBytes([0x89, 0x50, 0x4E, 0x47]), isFalse);
  });

  test('sanitize 后 jovial_svg 能解析出有效 viewport', () {
    final sanitized = SvgUtils.sanitize(SvgUtils.decodeSvgBytes(bytes));
    final si = ScalableImage.fromSvgString(sanitized, warnF: (_) {});

    // viewport 为零就意味着 rasterize 只能画出一张空图
    expect(si.viewport.width, greaterThan(0));
    expect(si.viewport.height, greaterThan(0));
  });

  test('sanitize 没有把内容清空', () {
    final raw = SvgUtils.decodeSvgBytes(bytes);
    final sanitized = SvgUtils.sanitize(raw);
    expect(sanitized.contains('<svg'), isTrue);
    expect(utf8.encode(sanitized).length, greaterThan(raw.length ~/ 2));
  });

  testWidgets('能光栅化成自绘话题卡使用的位图', (tester) async {
    final image = await SvgUtils.rasterize(bytes, 96);

    expect(image, isNotNull);
    expect(image!.width, 96);
    expect(image.height, 96);
    image.dispose();
  });
}
