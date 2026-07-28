import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// 应用图标风格（用户只选择风格，深浅色由系统自适应处理）
enum AppIconStyle {
  /// 经典 FluxDO 图标
  classic,

  /// 现代图标
  modern,
}

/// 应用图标状态
class AppIconState {
  final AppIconStyle currentStyle;
  final bool isChanging;

  const AppIconState({
    this.currentStyle = AppIconStyle.classic,
    this.isChanging = false,
  });

  AppIconState copyWith({AppIconStyle? currentStyle, bool? isChanging}) {
    return AppIconState(
      currentStyle: currentStyle ?? this.currentStyle,
      isChanging: isChanging ?? this.isChanging,
    );
  }
}

/// 应用图标管理
class AppIconNotifier extends StateNotifier<AppIconState> {
  static const String _prefKey = 'pref_app_icon';
  static const _platformChannel = MethodChannel(
    'com.github.lingyan000.fluxdo/app_icon',
  );
  final SharedPreferences _prefs;

  AppIconNotifier(this._prefs) : super(const AppIconState()) {
    _init();
  }

  AppIconStyle _styleFromSavedValue(String? saved) {
    switch (saved) {
      case 'modern':
      case 'modern_light':
      case 'ModernIcon':
        return AppIconStyle.modern;
      default:
        return AppIconStyle.classic;
    }
  }

  String _styleToPrefValue(AppIconStyle style) {
    return style == AppIconStyle.modern ? 'modern' : 'classic';
  }

  Future<void> _init() async {
    final style = _styleFromSavedValue(_prefs.getString(_prefKey));
    state = state.copyWith(currentStyle: style);
  }

  /// 根据风格获取平台图标名（深浅色由系统自适应处理）
  String? _getIconName(AppIconStyle style) {
    switch (style) {
      case AppIconStyle.classic:
        return null;
      case AppIconStyle.modern:
        return 'ModernIcon';
    }
  }

  /// 调用平台 API 切换图标
  Future<String?> _setPlatformIcon(String? iconName) async {
    await _platformChannel.invokeMethod('setAlternateIcon', {
      'iconName': iconName,
    });
    return iconName;
  }

  Future<bool> _isPlatformIconApplied(AppIconStyle style) async =>
      style == state.currentStyle;

  void _logPlatformIconException(PlatformException error) {
    debugPrint(
      '切换应用图标失败: '
      'code=${error.code}, '
      'message=${error.message}, '
      'details=${error.details}',
    );
  }

  /// 切换应用图标风格
  Future<bool> setIconStyle(AppIconStyle style) async {
    if (state.isChanging) return true;
    if (style == state.currentStyle && await _isPlatformIconApplied(style)) {
      return true;
    }

    state = state.copyWith(isChanging: true);

    try {
      final iconName = _getIconName(style);
      await _setPlatformIcon(iconName);

      await _prefs.setString(_prefKey, _styleToPrefValue(style));

      state = state.copyWith(currentStyle: style, isChanging: false);
      return true;
    } on PlatformException catch (e) {
      _logPlatformIconException(e);

      state = state.copyWith(isChanging: false);
      return false;
    } catch (e) {
      debugPrint('切换应用图标失败: $e');
      state = state.copyWith(isChanging: false);
      return false;
    }
  }
}

/// 应用图标 Provider
final appIconProvider = StateNotifierProvider<AppIconNotifier, AppIconState>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppIconNotifier(prefs);
});
