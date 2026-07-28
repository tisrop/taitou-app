import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/app_icon_provider.dart';

/// 启动页"绘制 logo"动画组件
///
/// 入场时用主题色细线沿轮廓逐段描出 logo,随后各色块依次淡入、
/// 描边线淡出,终态与 assets 中的 SVG 完全一致(直接用 CustomPainter
/// 复刻几何,无需切换回 SVG)。绘制完成后用一次克制的光晕脉冲收尾。
class PreheatLogo extends StatefulWidget {
  final AppIconStyle style;
  final double size;

  const PreheatLogo({super.key, required this.style, this.size = 108});

  @override
  State<PreheatLogo> createState() => _PreheatLogoState();
}

class _PreheatLogoState extends State<PreheatLogo>
    with TickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    duration: const Duration(milliseconds: 1300),
    vsync: this,
  );
  late final AnimationController _glow = AnimationController(
    duration: const Duration(milliseconds: 1600),
    vsync: this,
  );

  List<_LogoShape> _shapes = const [];
  Brightness? _brightness;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _entry
      ..addStatusListener((status) {
        // 绘制完成后只做一次光晕脉冲，避免长时间等待时持续抢占注意力。
        if (status == AnimationStatus.completed && !_disableAnimations) {
          _glow.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) {
      _brightness = brightness;
      _rebuildShapes();
    }

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations != disableAnimations) {
      _disableAnimations = disableAnimations;
      if (disableAnimations) {
        _entry.stop();
        _glow.stop();
        _entry.value = 1;
        _glow.value = 1;
      } else if (_entry.value == 1) {
        _glow.value = 0;
        _entry.forward(from: 0);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PreheatLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _rebuildShapes();
    }
  }

  void _rebuildShapes() {
    final dark = (_brightness ?? Brightness.light) == Brightness.dark;
    _shapes = widget.style == AppIconStyle.modern
        ? _buildTaitouShapes(
            background: dark ? _kModernDarkGradient : _kModernLightGradient,
            glyph: dark ? _kModernDarkGlyph : _kBrand,
          )
        : _buildTaitouShapes(background: _kClassicGradient, glyph: _kOnBrand);
  }

  @override
  void dispose() {
    _entry.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const viewSize = 1024.0; // 两种样式同用「抬」字标画布

    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _glow]),
      builder: (context, _) {
        // 光晕随填充出现，并在绘制完成后做一次轻微脉冲。
        final glowIn = _segment(_entry.value, 0.45, 1.0, Curves.easeIn);
        final pulse = math.sin(math.pi * _glow.value);
        final glowAlpha = glowIn * (0.06 + 0.04 * pulse);
        final glowBlur = 26.0 + 8.0 * pulse;
        final settle = _segment(_entry.value, 0, 1, Curves.easeOutBack);
        final scale = 0.96 + 0.04 * settle;

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: glowAlpha),
                  blurRadius: glowBlur,
                ),
              ],
            ),
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _LogoPainter(
                  shapes: _shapes,
                  t: _entry.value,
                  strokeColor: colorScheme.primary,
                  viewSize: viewSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 将整体进度 [t] 映射到 [start, end] 区间内的局部进度并应用曲线
double _segment(
  double t,
  double start,
  double end, [
  Curve curve = Curves.easeInOutCubic,
]) {
  return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
}

/// logo 的一个组成形状:填充路径 + 可选的描边路径与裁剪
class _LogoShape {
  final Path fillPath;
  final Color? fill;
  final Gradient? fillGradient;
  final double fillStrokeWidth;

  /// 描边动画走的路径,可与填充轮廓不同(如经典 logo 用分界弦线)
  final Path? strokePath;

  final double strokeStart;
  final double strokeEnd;
  final double fillStart;
  final double fillEnd;

  const _LogoShape({
    required this.fillPath,
    this.fill,
    this.fillGradient,
    this.fillStrokeWidth = 0,
    this.strokePath,
    this.strokeStart = 0,
    this.strokeEnd = 1,
    required this.fillStart,
    required this.fillEnd,
  }) : assert(fill != null || fillGradient != null);
}

class _LogoPainter extends CustomPainter {
  final List<_LogoShape> shapes;
  final double t;
  final Color strokeColor;

  /// viewBox 边长,绘制时统一缩放到组件尺寸
  final double viewSize;

  /// 描边线在该进度后整体淡出
  static const double _strokeFadeStart = 0.84;

  const _LogoPainter({
    required this.shapes,
    required this.t,
    required this.strokeColor,
    required this.viewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / viewSize;
    canvas.save();
    canvas.scale(scale);

    for (final shape in shapes) {
      final fillT = _segment(
        t,
        shape.fillStart,
        shape.fillEnd,
        Curves.easeInOut,
      );
      if (fillT <= 0) continue;
      canvas.save();
      final fillPaint = Paint();
      final fillGradient = shape.fillGradient;
      if (fillGradient != null) {
        fillPaint
          ..shader = fillGradient.createShader(shape.fillPath.getBounds())
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: fillT),
            BlendMode.modulate,
          );
      } else {
        fillPaint.color = shape.fill!.withValues(alpha: fillT);
      }
      canvas.drawPath(shape.fillPath, fillPaint);

      if (shape.fillStrokeWidth > 0) {
        canvas.drawPath(
          shape.fillPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = shape.fillStrokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = shape.fill!.withValues(alpha: fillT),
        );
      }
      canvas.restore();
    }

    final strokeAlpha =
        1.0 - _segment(t, _strokeFadeStart, 1.0, Curves.easeOut);
    if (strokeAlpha > 0) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor.withValues(alpha: strokeAlpha);
      for (final shape in shapes) {
        final strokePath = shape.strokePath;
        if (strokePath == null) continue;
        final strokeT = _segment(
          t,
          shape.strokeStart,
          shape.strokeEnd,
          Curves.easeInOutCubic,
        );
        if (strokeT <= 0) continue;
        for (final metric in strokePath.computeMetrics()) {
          canvas.drawPath(
            metric.extractPath(0, metric.length * strokeT),
            strokePaint,
          );
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.shapes != shapes ||
        oldDelegate.strokeColor != strokeColor;
  }
}

/// 品牌色与渐变，与 launcher 图标、assets/logo*.svg 保持一致。
const Color _kBrand = Color(0xFF1769DE);
const Color _kOnBrand = Color(0xFFFFFFFF);
const Color _kModernDarkGlyph = Color(0xFFF7F9FC);
const LinearGradient _kClassicGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3486F5), Color(0xFF1558C7)],
);
const LinearGradient _kModernDarkGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF282C34), Color(0xFF15171B)],
);
const LinearGradient _kModernLightGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFCFDFE), Color(0xFFE7ECF4)],
);

/// 「抬」字形轮廓(Heiti SC Medium，1024 画布内 520 见方居中)。
///
/// 开屏 logo 是**代码画的**，不读 assets/logo.svg —— 换品牌时这里、
/// assets/logo*.svg、android res 下的 launcher 图标三处要一起改，
/// 漏掉任何一处都会出现「图标换了但开屏还是旧的」。
const String _taitouGlyph =
    'M515.4 772.0H465.4Q468.2 750.4 469.7 728.2Q471.1 706.1 471.1 683.9V579.3Q471.1 562.9 470.5 5'
    '51.8Q469.9 540.7 468.2 529.9Q477.3 531.0 486.7 531.9Q496.1 532.7 510.3 533.3Q524.5 533.9 545'
    '.0 534.2Q565.4 534.4 596.7 534.4Q627.9 534.4 649.0 534.2Q670.0 533.9 684.2 533.3Q698.4 532.7'
    ' 707.8 531.9Q717.2 531.0 725.1 529.9Q724.0 534.4 723.7 538.4Q723.4 542.4 722.8 547.8Q722.3 5'
    '53.2 722.3 560.6Q722.3 568.0 722.3 579.3V668.6Q722.3 691.3 723.7 716.0Q725.1 740.7 728.0 761'
    '.2H676.2V715.2H515.4ZM676.2 573.1H515.4V674.8H676.2ZM331.3 416.2Q288.1 416.8 262.5 421.4V371'
    '.9Q275.6 374.2 292.6 375.0Q309.7 375.9 331.3 376.5Q331.3 348.6 330.7 329.3Q330.1 310.0 329.3'
    ' 296.9Q328.4 283.8 327.3 275.0Q326.2 266.2 325.0 260.0Q340.4 262.8 352.6 263.9Q364.8 265.1 3'
    '76.7 263.9Q389.2 262.8 391.5 267.1Q393.8 271.3 385.3 278.1Q379.0 282.7 376.5 287.0Q373.9 291'
    '.2 373.9 298.6V376.5Q394.4 375.9 410.8 375.0Q427.3 374.2 439.8 371.9V421.4Q413.7 416.8 373.9'
    ' 416.8V506.6Q387.5 500.3 400.9 493.8Q414.3 487.3 427.9 480.5Q426.8 495.2 428.5 505.5Q430.2 5'
    '15.7 434.7 524.8Q416.5 533.9 401.5 541.0Q386.4 548.1 373.9 554.3V713.5Q373.9 730.5 371.6 740'
    '.5Q369.4 750.4 361.1 756.1Q352.9 761.8 337.0 764.9Q321.0 768.0 294.3 771.4Q292.6 756.7 288.1'
    ' 744.4Q283.5 732.2 272.2 715.7Q291.5 717.4 303.4 717.4Q315.4 717.4 321.3 714.6Q327.3 711.8 3'
    '29.3 706.6Q331.3 701.5 331.3 693.0V575.9Q313.7 585.6 302.6 592.4Q291.5 599.2 278.4 608.9Q277'
    '.3 603.2 275.0 595.0Q272.7 586.7 269.9 578.2Q267.1 569.7 263.9 561.4Q260.8 553.2 257.4 547.0'
    'Q277.9 541.3 296.0 535.6Q314.2 529.9 331.3 523.7ZM706.9 458.3Q642.7 462.8 600.4 466.5Q558.0 4'
    '70.2 530.8 473.9Q503.5 477.6 487.8 481.6Q472.2 485.6 461.4 489.6Q459.7 477.0 455.5 464.3Q451'
    '.2 451.5 444.9 440.1Q455.7 435.6 467.1 424.8Q478.5 414.0 486.4 402.6Q514.3 365.1 531.6 329.0'
    'Q548.9 292.9 561.4 252.0Q597.8 268.5 619.4 273.6Q630.8 276.4 630.5 280.7Q630.2 285.0 618.8 2'
    '88.4Q614.3 289.5 607.5 298.0Q600.7 306.6 588.7 327.0Q582.5 337.2 573.4 351.2Q564.3 365.1 553'
    '.5 379.9Q542.7 394.6 531.6 408.6Q520.5 422.5 510.9 433.3L688.2 425.9Q676.8 407.7 664.0 391.0'
    'Q651.2 374.2 638.7 361.1L672.8 335.5Q686.5 350.3 699.8 366.8Q713.2 383.3 725.4 400.0Q737.6 4'
    '16.8 748.1 433.0Q758.6 449.2 766.6 462.8L721.7 489.0Q718.9 482.2 715.2 474.2Q711.5 466.3 706'
    '.9 458.3Z';

/// 「抬」字标:圆角方底 + 字形。描边先勾轮廓，随后依次填充底与字。
List<_LogoShape> _buildTaitouShapes({
  required Gradient background,
  required Color glyph,
}) {
  final plate = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 1024, 1024),
        const Radius.circular(225),
      ),
    );
  final glyphTransform = Matrix4.identity()
    ..translateByDouble(508.0, 504.0, 0, 1)
    ..scaleByDouble(1.08, 1.08, 1, 1)
    ..translateByDouble(-512.0, -512.0, 0, 1);
  final glyphPath = _parseSvgPath(
    _taitouGlyph,
  ).transform(glyphTransform.storage);

  return [
    _LogoShape(
      fillPath: plate,
      fillGradient: background,
      strokePath: plate,
      strokeStart: 0.0,
      strokeEnd: 0.45,
      fillStart: 0.42,
      fillEnd: 0.66,
    ),
    _LogoShape(
      fillPath: glyphPath,
      fill: glyph,
      fillStrokeWidth: 8,
      strokePath: glyphPath,
      strokeStart: 0.28,
      strokeEnd: 0.62,
      fillStart: 0.60,
      fillEnd: 0.86,
    ),
  ];
}

/// 迷你 SVG path 解析器。
///
/// 只需覆盖字形导出用到的绝对命令 M/L/H/V/Q/Z —— 字形由 fontTools 的
/// SVGPathPen 生成，不会出现相对命令、弧线或科学计数法。
Path _parseSvgPath(String d) {
  final path = Path();
  final number = RegExp(r'-?\d*\.?\d+');
  var cx = 0.0;
  var cy = 0.0;

  for (final segment in RegExp(r'([A-Z])([^A-Z]*)').allMatches(d)) {
    final cmd = segment.group(1)!;
    final args = number
        .allMatches(segment.group(2)!)
        .map((m) => double.parse(m.group(0)!))
        .toList();

    switch (cmd) {
      case 'M':
        for (var i = 0; i + 1 < args.length; i += 2) {
          cx = args[i];
          cy = args[i + 1];
          // 一条 M 后跟多组坐标时，后续按 lineTo 处理(SVG 规范)
          if (i == 0) {
            path.moveTo(cx, cy);
          } else {
            path.lineTo(cx, cy);
          }
        }
      case 'L':
        for (var i = 0; i + 1 < args.length; i += 2) {
          cx = args[i];
          cy = args[i + 1];
          path.lineTo(cx, cy);
        }
      case 'H':
        for (final v in args) {
          cx = v;
          path.lineTo(cx, cy);
        }
      case 'V':
        for (final v in args) {
          cy = v;
          path.lineTo(cx, cy);
        }
      case 'Q':
        for (var i = 0; i + 3 < args.length; i += 4) {
          path.quadraticBezierTo(
            args[i],
            args[i + 1],
            args[i + 2],
            args[i + 3],
          );
          cx = args[i + 2];
          cy = args[i + 3];
        }
      case 'Z':
        path.close();
    }
  }
  return path;
}
