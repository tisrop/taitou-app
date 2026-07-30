import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxdo/services/migration_service.dart';

void main() {
  test('runAll 清理已移除的上游代理配置', () async {
    SharedPreferences.setMockInitialValues({
      for (final key in MigrationService.migrationKeys) key: true,
      'http_proxy_enabled': true,
      'upstream_proxy_protocol': 'socks5',
      'http_proxy_host': '127.0.0.1',
      'http_proxy_port': 1080,
      'http_proxy_username': 'user',
      'http_proxy_password': 'secret',
      'vpn_auto_toggle_enabled': true,
      'vpn_suppressed_proxy': true,
      'rhttp_mode': 1,
      'rhttp_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await MigrationService.runAll(prefs);

    for (final key in MigrationService.retiredPreferenceKeys) {
      expect(prefs.containsKey(key), isFalse, reason: '$key 应被清理');
    }
    expect(prefs.getBool('rhttp_enabled'), isTrue);
  });
}
