import 'package:flutter/material.dart';

/// 为固定种子色复用 [ColorScheme.fromSeed] 的计算结果。
///
/// 外观页会在同一帧为主题模式、配色风格和色卡重复生成二十多套配色；
/// 这些组合稳定且可复用。取色器拖动产生的一次性色值不应走此缓存。
class SeedColorScheme {
  SeedColorScheme._();

  static final Map<(int, int, int), ColorScheme> _cache = {};
  static const int _maxEntries = 64;

  static ColorScheme from({
    required Color seedColor,
    Brightness brightness = Brightness.light,
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) {
    final key = (seedColor.toARGB32(), brightness.index, variant.index);
    final cached = _cache[key];
    if (cached != null) return cached;

    if (_cache.length >= _maxEntries) _cache.clear();

    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: variant,
    );
    _cache[key] = scheme;
    return scheme;
  }

  @visibleForTesting
  static void resetCache() => _cache.clear();

  @visibleForTesting
  static int get cachedCount => _cache.length;

  @visibleForTesting
  static int get maxEntries => _maxEntries;
}
