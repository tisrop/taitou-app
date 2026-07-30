import 'package:flutter/foundation.dart';

import 'log/log_writer.dart';

/// 网络诊断日志门面。
///
/// 输出到统一 JSONL（type: network），在应用日志页按「网络」筛选查看。
/// 历史版本写独立的 network_debug.log 且开关从未被打开，导致网络日志
/// 一直是空的；合并进统一日志后默认生效。
class NetworkLogger {
  NetworkLogger._();

  /// 写入一条网络诊断日志
  static void log(String message, {String level = 'info'}) {
    debugPrint('[Network] $message');
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'network',
      'message': message,
    });
  }
}
