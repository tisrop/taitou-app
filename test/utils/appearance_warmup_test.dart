import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/utils/appearance_warmup.dart';
import 'package:fluxdo/utils/seed_color_scheme.dart';

void main() {
  testWidgets('预热覆盖外观页首帧使用的固定配色组合', (tester) async {
    SeedColorScheme.resetCache();

    const customColor = Color(0xFF123456);
    const themeState = ThemeState(
      mode: ThemeMode.system,
      seedColor: Colors.blue,
      schemeVariant: DynamicSchemeVariant.tonalSpot,
      customColors: [customColor],
    );

    AppearanceWarmup.schedule(
      themeState: themeState,
      brightness: Brightness.light,
    );

    await tester.idle();
    await tester.pump();

    final countAfterWarmup = SeedColorScheme.cachedCount;
    expect(countAfterWarmup, greaterThan(0));

    for (final seed in <Color>[
      Colors.blue,
      ...ThemeNotifier.presetColors,
      customColor,
    ]) {
      SeedColorScheme.from(seedColor: seed, brightness: Brightness.light);
    }
    SeedColorScheme.from(seedColor: Colors.blue, brightness: Brightness.dark);
    for (final variant in DynamicSchemeVariant.values) {
      SeedColorScheme.from(
        seedColor: Colors.blue,
        brightness: Brightness.light,
        variant: variant,
      );
    }

    expect(
      SeedColorScheme.cachedCount,
      countAfterWarmup,
      reason: '外观页首帧不应再产生未命中的配色计算',
    );
  });
}
