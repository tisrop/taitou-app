import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'cert_preference_service.dart';
import 'per_device_cert_service.dart';

/// Android proxy CA certificate management.
class ProxyCertificate {
  ProxyCertificate._();

  static bool _initialized = false;

  /// Initialize the security context to trust the proxy CA
  ///
  /// Call this early in app startup (e.g., in main.dart)
  static Future<void> initialize() async {
    if (_initialized) return;

    final usePerDevice = await CertPreferenceService.usePerDevice();

    if (usePerDevice) {
      await _initializePerDevice();
    }
    // 固定 CA 由 Android network_security_config.xml 信任。

    _initialized = true;
  }

  /// 重新初始化（切换 per-device 开关后调用）
  static Future<void> reinitialize() async {
    _initialized = false;
    await initialize();
  }

  /// 初始化 Android per-device CA 证书
  static Future<void> _initializePerDevice() async {
    final certService = PerDeviceCertService.instance;
    final ok = await certService.ensureCaCert();
    if (ok && certService.certPem != null) {
      try {
        final certBytes = Uint8List.fromList(certService.certPem!.codeUnits);
        final context = SecurityContext.defaultContext;
        context.setTrustedCertificatesBytes(certBytes);
        debugPrint('ProxyCertificate: per-device CA loaded');
      } catch (e) {
        debugPrint('ProxyCertificate: Could not load per-device CA: $e');
      }
    } else {
      debugPrint('ProxyCertificate: per-device CA not ready');
    }
  }

  /// Get the CA certificate PEM content for display or export
  static Future<String?> getCertificatePem() async {
    final usePerDevice = await CertPreferenceService.usePerDevice();
    if (usePerDevice) {
      final certService = PerDeviceCertService.instance;
      if (certService.isLoaded) return certService.certPem;
      await certService.ensureCaCert();
      return certService.certPem;
    }
    try {
      return await rootBundle.loadString('assets/certs/proxy_ca.pem');
    } catch (e) {
      return null;
    }
  }
}
