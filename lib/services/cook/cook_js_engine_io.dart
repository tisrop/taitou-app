/// Android flutter_js 引擎封装。
library;

import 'package:flutter_js/flutter_js.dart';

/// Android 支持在本地 JS 引擎中执行 cook。
const bool cookJsSupported = true;

/// 裸 JS 引擎薄封装：eval 代码、取字符串结果。
///
/// Android 使用 flutter_js 提供的 QuickJS 运行时。
class CookJsEngine {
  CookJsEngine()
    : _runtime = getJavascriptRuntime(
        // cook 管线纯字符串运算，不需要 fetch/xhr 注入
        xhr: false,
      );

  final JavascriptRuntime _runtime;

  /// eval 一段 JS，返回其字符串结果；JS 抛错/引擎错误返回 null 并携带错误。
  ///
  /// [onError] 收到错误描述（用于日志），返回 null 表示失败。
  String? evaluate(String code, {void Function(String error)? onError}) {
    try {
      final result = _runtime.evaluate(code);
      if (result.isError) {
        onError?.call(result.stringResult);
        return null;
      }
      return result.stringResult;
    } catch (e) {
      onError?.call(e.toString());
      return null;
    }
  }
}
