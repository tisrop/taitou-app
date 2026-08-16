import '../../utils/time_utils.dart';
import 'chat_message.dart';

/// Maximum accepted by `GET /chat/api/channels/{id}/threads`.
const chatThreadsMaxPageSize = 10;

/// 消息串列表中的最近回复摘要。
class ChatThreadPreview {
  final DateTime? lastReplyCreatedAt;
  final String? lastReplyExcerpt;
  final int? lastReplyId;
  final int participantCount;
  final int replyCount;
  final List<ChatMessageUser> participantUsers;
  final ChatMessageUser? lastReplyUser;

  const ChatThreadPreview({
    this.lastReplyCreatedAt,
    this.lastReplyExcerpt,
    this.lastReplyId,
    this.participantCount = 0,
    this.replyCount = 0,
    this.participantUsers = const [],
    this.lastReplyUser,
  });

  factory ChatThreadPreview.fromJson(Map<String, dynamic> json) {
    return ChatThreadPreview(
      lastReplyCreatedAt: TimeUtils.parseUtcTime(
        json['last_reply_created_at'] as String?,
      ),
      lastReplyExcerpt: json['last_reply_excerpt'] as String?,
      lastReplyId: json['last_reply_id'] as int?,
      participantCount: json['participant_count'] as int? ?? 0,
      replyCount: json['reply_count'] as int? ?? 0,
      participantUsers: _parseUsers(json['participant_users']),
      lastReplyUser: json['last_reply_user'] is Map
          ? ChatMessageUser.fromJson(
              Map<String, dynamic>.from(json['last_reply_user'] as Map),
            )
          : null,
    );
  }

  static List<ChatMessageUser> _parseUsers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (user) => ChatMessageUser.fromJson(Map<String, dynamic>.from(user)),
        )
        .toList();
  }
}

/// 频道内的一条消息串。
class ChatThread {
  final int id;
  final String? title;
  final String status;
  final int channelId;
  final int replyCount;
  final int? lastMessageId;
  final ChatMessage? originalMessage;
  final ChatThreadPreview? preview;

  const ChatThread({
    required this.id,
    this.title,
    this.status = 'open',
    required this.channelId,
    this.replyCount = 0,
    this.lastMessageId,
    this.originalMessage,
    this.preview,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: json['id'] as int,
      title: json['title'] as String?,
      status: json['status'] as String? ?? 'open',
      channelId: json['channel_id'] as int? ?? 0,
      replyCount: json['reply_count'] as int? ?? 0,
      lastMessageId: json['last_message_id'] as int?,
      originalMessage: json['original_message'] is Map
          ? ChatMessage.fromJson(
              Map<String, dynamic>.from(json['original_message'] as Map),
            )
          : null,
      preview: json['preview'] is Map
          ? ChatThreadPreview.fromJson(
              Map<String, dynamic>.from(json['preview'] as Map),
            )
          : null,
    );
  }
}

/// `GET /chat/api/channels/{id}/threads` 的分页响应。
class ChatThreadsPage {
  final List<ChatThread> threads;
  final Map<String, dynamic> tracking;
  final bool hasMore;

  const ChatThreadsPage({
    required this.threads,
    this.tracking = const {},
    this.hasMore = false,
  });

  factory ChatThreadsPage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : const <String, dynamic>{};
    final loadMoreUrl = meta['load_more_url'] as String?;
    final rawThreads = json['threads'];
    return ChatThreadsPage(
      threads: rawThreads is List
          ? rawThreads
                .whereType<Map>()
                .map(
                  (thread) =>
                      ChatThread.fromJson(Map<String, dynamic>.from(thread)),
                )
                .toList()
          : const [],
      tracking: json['tracking'] is Map
          ? Map<String, dynamic>.from(json['tracking'] as Map)
          : const {},
      hasMore: loadMoreUrl?.isNotEmpty == true,
    );
  }
}
