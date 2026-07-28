import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/s.dart';
import '../../../services/toast_service.dart';

/// AI 聊天首次引导
class AiChatGuide {
  static const String _key = 'ai_chat_guide_shown';

  /// 检查并显示引导提示
  static Future<void> checkAndShow(SharedPreferences prefs) async {
    final shown = prefs.getBool(_key) ?? false;
    if (shown) return;

    await prefs.setBool(_key, true);
    ToastService.showInfo(S.current.ai_swipeHint);
  }
}
