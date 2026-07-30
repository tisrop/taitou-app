import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/constants.dart';
import 'package:fluxdo/widgets/auth/webview_login_dialog.dart';

void main() {
  test('站点未配置验证码时不显示人机验证窗口', () {
    expect(
      AppConstants.isLoginCaptchaEnabled(AppConstants.hcaptchaSiteKey),
      isFalse,
    );
  });

  test('配置验证码后才显示人机验证界面', () {
    expect(AppConstants.isLoginCaptchaEnabled('site-key'), isTrue);
  });

  testWidgets('登录流程超时守卫会在期限到达后触发', (tester) async {
    var timedOut = false;
    final guard = WebViewLoginTimeoutGuard(
      timeout: webViewLoginTimeout,
      onTimeout: () => timedOut = true,
    );
    addTearDown(guard.cancel);
    guard.start();

    await tester.pump(webViewLoginTimeout - const Duration(milliseconds: 1));
    expect(timedOut, isFalse);

    await tester.pump(const Duration(milliseconds: 1));
    expect(timedOut, isTrue);
  });

  testWidgets('登录流程完成后超时守卫不会再触发', (tester) async {
    var timedOut = false;
    final guard = WebViewLoginTimeoutGuard(
      timeout: webViewLoginTimeout,
      onTimeout: () => timedOut = true,
    );
    addTearDown(guard.cancel);
    guard.start();

    await tester.pump(const Duration(seconds: 1));
    guard.cancel();
    await tester.pump(webViewLoginTimeout);

    expect(timedOut, isFalse);
  });
}
