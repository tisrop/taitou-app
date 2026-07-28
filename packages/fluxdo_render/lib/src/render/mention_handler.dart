/// 点击 mention 时主项目要执行的回调签名。
///
/// 子包不实现用户卡路由(主项目有 UserProfilePage + DiscourseUrlParser
/// 解析 username),通过这个 typedef 注入。
///
/// 调用方:
/// ```dart
/// FluxdoRender(
///   cookedHtml: ...,
///   mentionTapHandler: (ctx, username, href) {
///     Navigator.of(ctx).push(MaterialPageRoute(
///       builder: (_) => UserProfilePage(username: username),
///     ));
///   },
/// );
/// ```

library;

import 'package:flutter/widgets.dart';

typedef MentionTapHandler = void Function(
  BuildContext context,
  String username,
  String href,
);

/// 默认 mention handler —— 仅打印 debug 信息,不跳转。
///
/// 主项目调用方必须自行注入实际 handler;留这个 default 是为了
/// 让子包单测 + example gallery 不至于因为忘注入而崩。
void defaultMentionTapHandler(
  BuildContext context,
  String username,
  String href,
) {
  debugPrint('[fluxdo_render] mention tapped without handler: @$username ($href)');
}
