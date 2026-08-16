import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../providers/theme_provider.dart';
import 'seed_color_scheme.dart';

/// 在进入外观页前，利用空闲时段摊平字体与种子配色的首次计算开销。
class AppearanceWarmup {
  AppearanceWarmup._();

  static (int, int, int, int)? _lastSignature;

  static void schedule({
    required ThemeState themeState,
    required Brightness brightness,
  }) {
    final effectiveSeed = themeState.useDynamicColor
        ? (themeState.dynamicPrimary ?? themeState.seedColor)
        : themeState.seedColor;
    final variant = themeState.schemeVariant;
    final customColorsHash = Object.hashAll(
      themeState.customColors.map((color) => color.toARGB32()),
    );
    final signature = (
      effectiveSeed.toARGB32(),
      variant.index,
      brightness.index,
      customColorsHash,
    );
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    final scheduler = SchedulerBinding.instance;
    void queue(void Function() task) =>
        scheduler.scheduleTask(task, Priority.idle);

    queue(_warmUpMiSansTypeface);

    for (final seed in <Color>[
      effectiveSeed,
      ...ThemeNotifier.presetColors,
      ...themeState.customColors,
    ]) {
      queue(
        () => SeedColorScheme.from(
          seedColor: seed,
          brightness: brightness,
          variant: variant,
        ),
      );
    }

    for (final previewBrightness in Brightness.values) {
      queue(
        () => SeedColorScheme.from(
          seedColor: effectiveSeed,
          brightness: previewBrightness,
          variant: variant,
        ),
      );
    }

    for (final previewVariant in DynamicSchemeVariant.values) {
      queue(
        () => SeedColorScheme.from(
          seedColor: effectiveSeed,
          brightness: brightness,
          variant: previewVariant,
        ),
      );
    }
  }

  static void _warmUpMiSansTypeface() {
    TextPainter(
        text: const TextSpan(
          text: 'MiSans',
          style: TextStyle(fontFamily: 'MiSans'),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..dispose();
  }
}
