import 'package:ai_model_manager/ai_model_manager.dart';

import '../models/chat/chat_message.dart';
import '../utils/time_utils.dart';

/// 聊天记录总结。
///
/// 走用户自配的 AI 模型（和「总结这个话题」同一套），不依赖服务端的
/// discourse-ai 插件 —— 站点不一定装了它。
class ChatSummaryService {
  ChatSummaryService(this._chatService, this._apiKeyLoader);

  final AiChatService _chatService;
  final Future<String?> Function(String providerId) _apiKeyLoader;

  /// 单条消息的最大取用长度。聊天里偶尔有人贴长文，截断避免单条撑爆上下文。
  static const _maxCharsPerMessage = 500;

  /// 把消息列表压成喂给模型的纯文本记录。
  ///
  /// 只保留「时间 + 昵称 + 正文」；正文用 raw markdown（`message`）而不是
  /// cooked HTML —— 标签对总结没有价值，还白白占上下文。
  static String buildTranscript(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      if (msg.isDeleted) continue;
      final text = msg.message.trim();
      if (text.isEmpty) continue;
      final clipped = text.length > _maxCharsPerMessage
          ? '${text.substring(0, _maxCharsPerMessage)}…'
          : text;
      final at = msg.createdAt;
      final stamp = at == null ? '' : '[${TimeUtils.formatCompactTime(at)}] ';
      buffer.writeln('$stamp${msg.user.displayName}: $clipped');
    }
    return buffer.toString().trim();
  }

  static String buildSystemPrompt() {
    return '你是一个聊天记录总结助手。用户会给你一段群聊记录，请你输出简洁的中文总结。\n'
        '要求：\n'
        '1. 先用一两句话概括这段时间聊了什么；\n'
        '2. 再分条列出讨论到的具体话题，每条注明主要参与者；\n'
        '3. 如果有待办、结论或未决问题，单独列出来；\n'
        '4. 不要逐条复述原文，不要编造记录里没有的内容；\n'
        '5. 记录里没有实质内容时，直接说明这段时间没有值得总结的讨论。';
  }

  static String buildUserPrompt({
    required String channelTitle,
    required int hours,
    required String transcript,
  }) {
    return '以下是频道「$channelTitle」过去 $hours 小时的聊天记录，请按要求总结：\n\n$transcript';
  }

  /// 流式总结。逐段 yield 累积文本增量，调用方直接拼接展示。
  Stream<String> summarize({
    required AiProvider provider,
    required AiModel model,
    required String channelTitle,
    required int hours,
    required List<ChatMessage> messages,
  }) async* {
    final transcript = buildTranscript(messages);
    if (transcript.isEmpty) {
      throw const ChatSummaryException(ChatSummaryError.noContent);
    }

    final apiKey = await _apiKeyLoader(provider.id);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const ChatSummaryException(ChatSummaryError.noApiKey);
    }

    final stream = _chatService.sendChatStream(
      provider: provider,
      model: model.id,
      apiKey: apiKey.trim(),
      systemPrompt: buildSystemPrompt(),
      messages: [
        AiChatMessage(
          id: 'chat-summary-request',
          role: ChatRole.user,
          content: buildUserPrompt(
            channelTitle: channelTitle,
            hours: hours,
            transcript: transcript,
          ),
          createdAt: DateTime.now(),
        ),
      ],
    );

    await for (final chunk in stream) {
      // 只要正文；思考块（reasoning）不展示
      if (chunk is TextDelta) yield chunk.text;
    }
  }
}

enum ChatSummaryError {
  /// 时间窗内没有可总结的内容
  noContent,

  /// 选中的 provider 读不出 API Key
  noApiKey,
}

class ChatSummaryException implements Exception {
  const ChatSummaryException(this.error);
  final ChatSummaryError error;

  @override
  String toString() => 'ChatSummaryException($error)';
}
