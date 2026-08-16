import 'chat_channel.dart';
import 'chat_message.dart';

/// 聊天消息搜索排序方式，对应 Discourse chat API 的 `sort` 参数。
enum ChatMessageSearchSort {
  relevance,
  latest;

  String get apiValue => name;
}

/// 一条聊天搜索结果。搜索 API 会在标准消息字段旁附带所属频道。
class ChatMessageSearchHit {
  const ChatMessageSearchHit({required this.message, required this.channel});

  final ChatMessage message;
  final ChatChannel channel;

  /// 兼容不同 Discourse 版本可能只在消息或频道对象中提供频道 ID。
  bool belongsToChannel(int channelId) =>
      channel.id == channelId || message.chatChannelId == channelId;

  factory ChatMessageSearchHit.fromJson(Map<String, dynamic> json) {
    final rawChannel = json['channel'];
    if (rawChannel is! Map) {
      throw const FormatException('Missing channel in chat search result');
    }

    return ChatMessageSearchHit(
      message: ChatMessage.fromJson(json),
      channel: ChatChannel.fromJson(Map<String, dynamic>.from(rawChannel)),
    );
  }
}

/// `GET /chat/api/search` 的分页响应。
class ChatMessageSearchPage {
  const ChatMessageSearchPage({
    required this.hits,
    this.hasMore = false,
    this.limit = 20,
    this.offset = 0,
  });

  final List<ChatMessageSearchHit> hits;
  final bool hasMore;
  final int limit;
  final int offset;

  factory ChatMessageSearchPage.fromJson(Map<String, dynamic> json) {
    final hits = <ChatMessageSearchHit>[];
    final rawMessages = json['messages'];
    if (rawMessages is List) {
      for (final rawMessage in rawMessages) {
        if (rawMessage is! Map) continue;
        try {
          hits.add(
            ChatMessageSearchHit.fromJson(
              Map<String, dynamic>.from(rawMessage),
            ),
          );
        } on FormatException {
          // 单条损坏结果不应让整页搜索失败。
        } on TypeError {
          // 服务端插件版本不一致时可能缺少必填字段，同样跳过该条。
        }
      }
    }

    final rawMeta = json['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : const <String, dynamic>{};

    return ChatMessageSearchPage(
      hits: hits,
      hasMore: meta['has_more'] as bool? ?? false,
      limit: meta['limit'] as int? ?? 20,
      offset: meta['offset'] as int? ?? 0,
    );
  }
}
