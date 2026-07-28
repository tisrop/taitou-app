import 'package:shared_preferences/shared_preferences.dart';

/// 证书偏好服务
///
/// 管理 Android 是否使用 per-device CA 证书的偏好设置。
class CertPreferenceService {
  CertPreferenceService._();

  static const _usePerDeviceKey = 'cert_use_per_device';

  /// Android 不强制使用 per-device CA。
  static bool get isPerDeviceRequired => false;

  /// Android 可选使用 per-device CA。
  static bool get isPerDeviceOptional => true;

  /// 是否使用 per-device CA
  ///
  /// 从本地偏好读取 Android 的 per-device CA 开关。
  static Future<bool> usePerDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_usePerDeviceKey) ?? false;
  }

  /// 设置 Android 是否使用 per-device CA。
  static Future<void> setUsePerDevice(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_usePerDeviceKey, value);
  }
}
