import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'doh_proxy_service.dart';

/// Per-device CA 证书管理服务
///
/// 每台 Android 设备生成唯一的 CA 证书，避免所有用户共享同一私钥。
class PerDeviceCertService {
  PerDeviceCertService._();
  static final PerDeviceCertService instance = PerDeviceCertService._();

  String? _certPem;
  String? _keyPem;
  bool _loaded = false;

  /// 获取 CA 证书 PEM
  String? get certPem => _certPem;

  /// 获取 CA 私钥 PEM
  String? get keyPem => _keyPem;

  /// 证书是否已加载
  bool get isLoaded => _loaded && _certPem != null && _keyPem != null;

  /// 确保 CA 证书存在（有则读取，无则生成并存储）
  Future<bool> ensureCaCert() async {
    if (isLoaded) return true;

    final dir = await _certsDir();
    final certFile = File('${dir.path}/ca.crt');
    final keyFile = File('${dir.path}/ca.key');

    if (certFile.existsSync() && keyFile.existsSync()) {
      _certPem = await certFile.readAsString();
      _keyPem = await keyFile.readAsString();
      _loaded = true;
      debugPrint('[PerDeviceCert] 已加载本地 CA 证书');
      return true;
    }

    // 通过 FFI 生成新 CA
    final result = await DohProxyService.instance.generateCa();
    if (result == null) {
      debugPrint('[PerDeviceCert] CA 生成失败');
      return false;
    }

    await dir.create(recursive: true);
    await certFile.writeAsString(result.certPem);
    await keyFile.writeAsString(result.keyPem);

    _certPem = result.certPem;
    _keyPem = result.keyPem;
    _loaded = true;
    debugPrint('[PerDeviceCert] 新 CA 证书已生成并保存');
    return true;
  }

  /// 重置内存状态并删除已有证书文件，下次 ensureCaCert 会重新生成
  Future<void> reset() async {
    _certPem = null;
    _keyPem = null;
    _loaded = false;
    try {
      final dir = await _certsDir();
      final certFile = File('${dir.path}/ca.crt');
      final keyFile = File('${dir.path}/ca.key');
      if (certFile.existsSync()) await certFile.delete();
      if (keyFile.existsSync()) await keyFile.delete();
    } catch (_) {}
  }

  Future<Directory> _certsDir() async {
    final appSupport = await getApplicationSupportDirectory();
    return Directory('${appSupport.path}/certs');
  }
}
