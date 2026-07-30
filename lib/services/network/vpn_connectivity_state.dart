import 'package:connectivity_plus/connectivity_plus.dart';

/// 缓存 connectivity_plus 最近一次上报的 VPN 状态。
class VpnConnectivityState {
  VpnConnectivityState._();

  static final VpnConnectivityState instance = VpnConnectivityState._();

  bool _isActive = false;
  bool _hasSnapshot = false;
  Future<bool>? _refreshFuture;

  bool get isActive => _isActive;

  void update(List<ConnectivityResult> results) {
    _isActive = results.contains(ConnectivityResult.vpn);
    _hasSnapshot = true;
  }

  /// 首次网络事件尚未到达时主动查询，避免冷启动请求先失败而漏掉 VPN 提示。
  Future<bool> resolveIsActive({
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
  }) {
    if (_hasSnapshot) return Future.value(_isActive);
    return _refreshFuture ??= _refresh(checkConnectivity).whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<bool> _refresh(
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
  ) async {
    try {
      final results =
          await (checkConnectivity ?? Connectivity().checkConnectivity)();
      update(results);
    } catch (_) {
      // 查询失败时保持未知；后续错误仍可再次尝试，不把失败误判为 VPN。
    }
    return _isActive;
  }

  void reset() {
    _isActive = false;
    _hasSnapshot = false;
    _refreshFuture = null;
  }
}
