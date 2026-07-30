import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rhttp 引擎设置
class RhttpSettings {
  const RhttpSettings({this.enabled = false, this.forceDisabled = false});

  final bool enabled;

  /// 运行时强制禁用标志（不持久化，仅当前进程有效）
  /// 当 rhttp Rust 引擎初始化失败时由 forceDisable() 置为 true，
  /// 下次启动自动恢复为 false 并重新尝试初始化
  final bool forceDisabled;

  RhttpSettings copyWith({bool? enabled, bool? forceDisabled}) {
    return RhttpSettings(
      enabled: enabled ?? this.enabled,
      forceDisabled: forceDisabled ?? this.forceDisabled,
    );
  }
}

/// rhttp 引擎设置管理服务
class RhttpSettingsService {
  RhttpSettingsService._internal();

  static final RhttpSettingsService instance = RhttpSettingsService._internal();

  static const _enabledKey = 'rhttp_enabled';

  final ValueNotifier<RhttpSettings> notifier = ValueNotifier(
    const RhttpSettings(),
  );

  SharedPreferences? _prefs;
  int _version = 0;

  int get version => _version;
  RhttpSettings get current => notifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_prefs != null) return;
    _prefs = prefs;
    final enabled = prefs.getBool(_enabledKey) ?? false;
    notifier.value = RhttpSettings(enabled: enabled);
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;
    notifier.value = notifier.value.copyWith(enabled: enabled);
    await prefs.setBool(_enabledKey, enabled);
    _touch();
  }

  /// 强制禁用（Rhttp.init() 失败时调用）
  ///
  /// 仅修改运行时内存状态，不持久化到 SharedPreferences，
  /// 确保下次启动仍会重新尝试初始化 rhttp 引擎。
  Future<void> forceDisable() async {
    if (_prefs == null) return;
    notifier.value = notifier.value.copyWith(forceDisabled: true);
    _touch();
    debugPrint('[rhttp] 已强制禁用（初始化失败）');
  }

  /// 综合判断当前是否应该使用 rhttp
  bool shouldUseRhttp() {
    if (current.forceDisabled) return false;
    return current.enabled;
  }

  /// 重置单例内部状态，仅用于测试，使 initialize() 可重新执行。
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _version = 0;
  }

  void _touch() {
    _version++;
    notifier.value = notifier.value.copyWith();
  }
}
