import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';

/// 聊天消息里的用户（基础用户序列化，含头像模板）
class ChatMessageUser {
  final int id;
  final String username;
  final String name;
  final String avatarTemplate;

  const ChatMessageUser({
    required this.id,
    required this.username,
    this.name = '',
    this.avatarTemplate = '',
  });

  /// 显示名：优先昵称，空则回退 username
  String get displayName => name.isNotEmpty ? name : username;

  factory ChatMessageUser.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const ChatMessageUser(id: 0, username: '');
    }
    return ChatMessageUser(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarTemplate: json['avatar_template'] as String? ?? '',
    );
  }

  String getAvatarUrl({int size = 40}) {
    final template = avatarTemplate.replaceAll('{size}', '$size');
    return UrlHelper.resolveUrlWithCdn(template);
  }
}

/// 被引用的消息摘要（in_reply_to）
class ChatMessageReplyTo {
  final int? id;
  final String? excerpt;
  final ChatMessageUser? user;

  const ChatMessageReplyTo({this.id, this.excerpt, this.user});

  factory ChatMessageReplyTo.fromJson(Map<String, dynamic> json) {
    return ChatMessageReplyTo(
      id: json['id'] as int?,
      excerpt: json['excerpt'] as String?,
      user: ChatMessageUser.fromJson(json['user']),
    );
  }
}

/// 聊天消息里的上传附件（仅保留 id 与原图 URL，首版不渲染上传交互）
class ChatUpload {
  final int id;
  final String? url;
  final String? originalFilename;

  const ChatUpload({required this.id, this.url, this.originalFilename});

  factory ChatUpload.fromJson(Map<String, dynamic> json) {
    return ChatUpload(
      id: json['id'] as int? ?? 0,
      url: json['url'] as String?,
      originalFilename: json['original_filename'] as String?,
    );
  }
}

/// 聊天消息上的单个表情回应分组。
class ChatMessageReaction {
  final String emoji;
  final int count;
  final bool reacted;

  const ChatMessageReaction({
    required this.emoji,
    required this.count,
    this.reacted = false,
  });

  factory ChatMessageReaction.fromJson(Map<String, dynamic> json) {
    return ChatMessageReaction(
      emoji: json['emoji'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      reacted: json['reacted'] as bool? ?? false,
    );
  }

  ChatMessageReaction copyWith({int? count, bool? reacted}) {
    return ChatMessageReaction(
      emoji: emoji,
      count: count ?? this.count,
      reacted: reacted ?? this.reacted,
    );
  }
}

/// 单条聊天消息
class ChatMessage {
  final int id;
  final String message;
  final String? cooked;
  final String? excerpt;
  final DateTime? createdAt;
  final bool edited;
  final DateTime? deletedAt;
  final int? threadId;
  final int chatChannelId;
  final ChatMessageUser user;
  final List<ChatMessageUser> mentionedUsers;
  final List<ChatUpload> uploads;
  final ChatMessageReplyTo? inReplyTo;
  final List<ChatMessageReaction> reactions;
  final int? bookmarkId;
  final List<String> availableFlags;
  final bool pinned;

  /// 是否为客户端乐观暂存消息（尚未被服务端确认）。账号切换后一律视为本地。
  final bool isLocal;

  const ChatMessage({
    required this.id,
    required this.message,
    this.cooked,
    this.excerpt,
    this.createdAt,
    this.edited = false,
    this.deletedAt,
    this.threadId,
    required this.chatChannelId,
    required this.user,
    this.mentionedUsers = const [],
    this.uploads = const [],
    this.inReplyTo,
    this.reactions = const [],
    this.bookmarkId,
    this.availableFlags = const [],
    this.pinned = false,
    this.isLocal = false,
  });

  /// 是否已删除
  bool get isDeleted => deletedAt != null;

  /// 局部覆盖。`processed` 事件只带回 cook 结果，用它把 cooked/uploads 合并进
  /// 已有消息，而不是整条替换（整条替换会丢掉本地已有的其它状态）。
  ChatMessage copyWith({
    int? id,
    String? message,
    String? cooked,
    String? excerpt,
    DateTime? createdAt,
    bool? edited,
    List<ChatUpload>? uploads,
    List<ChatMessageReaction>? reactions,
    int? bookmarkId,
    bool clearBookmark = false,
    List<String>? availableFlags,
    bool? pinned,
    bool? isLocal,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      message: message ?? this.message,
      cooked: cooked ?? this.cooked,
      excerpt: excerpt ?? this.excerpt,
      createdAt: createdAt ?? this.createdAt,
      edited: edited ?? this.edited,
      deletedAt: deletedAt,
      threadId: threadId,
      chatChannelId: chatChannelId,
      user: user,
      mentionedUsers: mentionedUsers,
      uploads: uploads ?? this.uploads,
      inReplyTo: inReplyTo,
      reactions: reactions ?? this.reactions,
      bookmarkId: clearBookmark ? null : (bookmarkId ?? this.bookmarkId),
      availableFlags: availableFlags ?? this.availableFlags,
      pinned: pinned ?? this.pinned,
      isLocal: isLocal ?? this.isLocal,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      message: json['message'] as String? ?? '',
      cooked: json['cooked'] as String?,
      excerpt: json['excerpt'] as String?,
      createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
      edited: json['edited'] as bool? ?? false,
      deletedAt: TimeUtils.parseUtcTime(json['deleted_at'] as String?),
      threadId: json['thread_id'] as int?,
      chatChannelId: json['chat_channel_id'] as int? ?? 0,
      user: ChatMessageUser.fromJson(json['user']),
      mentionedUsers: _parseUsers(json['mentioned_users']),
      uploads: _parseUploads(json['uploads']),
      inReplyTo: json['in_reply_to'] is Map<String, dynamic>
          ? ChatMessageReplyTo.fromJson(
              json['in_reply_to'] as Map<String, dynamic>,
            )
          : null,
      reactions: _parseReactions(json['reactions']),
      bookmarkId: json['bookmark'] is Map<String, dynamic>
          ? (json['bookmark'] as Map<String, dynamic>)['id'] as int?
          : null,
      availableFlags: json['available_flags'] is List
          ? (json['available_flags'] as List).map((value) => '$value').toList()
          : const [],
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  /// MessageBus 事件中的消息以 `chat_message` 为根键（序列化报文）
  static ChatMessage? fromMessageBusData(Map<String, dynamic> json) {
    final raw = json['chat_message'];
    if (raw is! Map<String, dynamic>) return null;
    return ChatMessage.fromJson(raw);
  }

  static List<ChatMessageUser> _parseUsers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatMessageUser.fromJson)
        .toList();
  }

  static List<ChatUpload> _parseUploads(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatUpload.fromJson)
        .toList();
  }

  static List<ChatMessageReaction> _parseReactions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatMessageReaction.fromJson)
        .where((reaction) => reaction.emoji.isNotEmpty && reaction.count > 0)
        .toList();
  }
}

/// `GET /chat/api/channels/{id}/messages` 的分页响应
class ChatMessagesPage {
  final List<ChatMessage> messages;
  final Map<String, dynamic> tracking;
  final int? targetMessageId;
  final bool canLoadMoreFuture;
  final bool canLoadMorePast;

  const ChatMessagesPage({
    required this.messages,
    this.tracking = const {},
    this.targetMessageId,
    this.canLoadMoreFuture = false,
    this.canLoadMorePast = false,
  });

  factory ChatMessagesPage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] is Map<String, dynamic>
        ? json['meta'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rawMessages = json['messages'];
    return ChatMessagesPage(
      messages: rawMessages is List
          ? rawMessages
                .whereType<Map<String, dynamic>>()
                .map(ChatMessage.fromJson)
                .toList()
          : const [],
      tracking: json['tracking'] is Map<String, dynamic>
          ? json['tracking'] as Map<String, dynamic>
          : const {},
      targetMessageId: meta['target_message_id'] as int?,
      canLoadMoreFuture: meta['can_load_more_future'] as bool? ?? false,
      canLoadMorePast: meta['can_load_more_past'] as bool? ?? false,
    );
  }
}
