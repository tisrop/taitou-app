import '../chat/chat_message.dart';

/// 当前用户接收频道推送通知的级别。
enum ChatChannelNotificationLevel {
  never('never'),
  mention('mention'),
  always('always');

  const ChatChannelNotificationLevel(this.value);

  final String value;

  static ChatChannelNotificationLevel fromJson(dynamic value) {
    return ChatChannelNotificationLevel.values.firstWhere(
      (level) => level.value == value,
      orElse: () => ChatChannelNotificationLevel.mention,
    );
  }
}

/// 聊天频道成员的成员关系（当前用户）
class ChatChannelMembership {
  final bool following;
  final bool muted;
  final bool starred;
  final ChatChannelNotificationLevel notificationLevel;
  final int? lastReadMessageId;

  const ChatChannelMembership({
    required this.following,
    required this.muted,
    this.starred = false,
    this.notificationLevel = ChatChannelNotificationLevel.mention,
    this.lastReadMessageId,
  });

  factory ChatChannelMembership.fromJson(Map<String, dynamic> json) {
    return ChatChannelMembership(
      following: json['following'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      starred: json['starred'] as bool? ?? false,
      notificationLevel: ChatChannelNotificationLevel.fromJson(
        json['notification_level'],
      ),
      lastReadMessageId: json['last_read_message_id'] as int?,
    );
  }
}

/// MessageBus 断点续传所需的各种 last_id
class ChatMessageBusLastIds {
  final int? channelMessageBusLastId;
  final int? newMessages;
  final int? newMentions;
  final int? kick;

  const ChatMessageBusLastIds({
    this.channelMessageBusLastId,
    this.newMessages,
    this.newMentions,
    this.kick,
  });

  const ChatMessageBusLastIds.empty() : this();

  factory ChatMessageBusLastIds.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const ChatMessageBusLastIds.empty();
    }
    return ChatMessageBusLastIds(
      channelMessageBusLastId: json['channel_message_bus_last_id'] as int?,
      newMessages: json['new_messages'] as int?,
      newMentions: json['new_mentions'] as int?,
      kick: json['kick'] as int?,
    );
  }
}

/// 单个聊天频道
class ChatChannel {
  final int id;
  final String title;
  final String? description;
  final String? slug;
  final String? emoji;
  final String status;
  final String chatableType;
  final int? chatableId;

  /// 分类频道的十六进制颜色（如 `0088CC`，无 `#` 前缀），来自 chatable.color。
  final String? chatableColor;

  /// 分类频道所属分类是否为「仅限特定群组可见」，来自 chatable.read_restricted。
  /// 网页版据此在频道图标右上角叠加一个小锁。
  final bool chatableReadRestricted;
  final bool autoJoinUsers;
  final bool threadingEnabled;
  final int membershipsCount;
  final ChatChannelMembership? currentUserMembership;
  final ChatMessage? lastMessage;
  final ChatMessageBusLastIds messageBusLastIds;

  /// 直接消息频道的成员（头像），供频道图标展示；公开频道为空列表。
  final List<ChatMessageUser> directMessageUsers;

  const ChatChannel({
    required this.id,
    required this.title,
    this.description,
    this.slug,
    this.emoji,
    this.status = 'open',
    this.chatableType = '',
    this.chatableId,
    this.chatableColor,
    this.chatableReadRestricted = false,
    this.autoJoinUsers = false,
    this.threadingEnabled = false,
    this.membershipsCount = 0,
    this.currentUserMembership,
    this.lastMessage,
    this.messageBusLastIds = const ChatMessageBusLastIds.empty(),
    this.directMessageUsers = const [],
  });

  /// 频道是否是「直接消息」频道(1:1 / 群聊)
  bool get isDirectMessage => chatableType == 'DirectMessage';

  /// 频道是否是「分类（公开）」频道
  bool get isCategoryChannel => chatableType == 'Category';

  /// 是否已关注(底栏候选、未读展示用)
  bool get isFollowing => currentUserMembership?.following ?? false;

  /// 当前用户是否已收藏该频道。
  bool get isStarred => currentUserMembership?.starred ?? false;

  /// 只有开放频道可以由尚未加入的用户加入。
  bool get isJoinable => status == 'open' && !isFollowing;

  factory ChatChannel.fromJson(Map<String, dynamic> json) {
    final chatable = json['chatable'] is Map<String, dynamic>
        ? json['chatable'] as Map<String, dynamic>
        : null;
    return ChatChannel(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      slug: json['slug'] as String?,
      emoji: json['emoji'] as String?,
      status: json['status'] as String? ?? 'open',
      chatableType: json['chatable_type'] as String? ?? '',
      chatableId: json['chatable_id'] as int?,
      chatableColor: chatable?['color'] as String?,
      chatableReadRestricted: chatable?['read_restricted'] as bool? ?? false,
      autoJoinUsers: json['auto_join_users'] as bool? ?? false,
      threadingEnabled: json['threading_enabled'] as bool? ?? false,
      membershipsCount: json['memberships_count'] as int? ?? 0,
      currentUserMembership:
          json['current_user_membership'] is Map<String, dynamic>
          ? ChatChannelMembership.fromJson(
              json['current_user_membership'] as Map<String, dynamic>,
            )
          : null,
      lastMessage: _parseLastMessage(json['last_message']),
      messageBusLastIds: ChatMessageBusLastIds.fromJson(
        json['meta']?['message_bus_last_ids'] is Map<String, dynamic>
            ? (json['meta']!['message_bus_last_ids'] as Map<String, dynamic>)
            : null,
      ),
      directMessageUsers: _parseDirectMessageUsers(chatable),
    );
  }

  /// 直接消息频道在 `chatable.users` 里给出成员（含头像模板）。
  /// 公开频道的 chatable 是 Category，无 users。
  static List<ChatMessageUser> _parseDirectMessageUsers(
    Map<String, dynamic>? chatable,
  ) {
    final users = chatable?['users'];
    if (users is! List) return const [];
    return users
        .whereType<Map<String, dynamic>>()
        .map(ChatMessageUser.fromJson)
        .toList();
  }

  /// 频道索引里的 last_message 是可选摘要；少数响应会保留对象但将 id 设为 null。
  /// 消息 id 是未读判断和消息操作的必要字段，缺失时忽略该摘要，避免构造无效消息。
  static ChatMessage? _parseLastMessage(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    if (json['id'] is! int) return null;
    return ChatMessage.fromJson(json);
  }

  ChatChannel copyWith({
    ChatMessage? lastMessage,
    ChatChannelMembership? currentUserMembership,
    bool? threadingEnabled,
  }) {
    return ChatChannel(
      id: id,
      title: title,
      description: description,
      slug: slug,
      emoji: emoji,
      status: status,
      chatableType: chatableType,
      chatableId: chatableId,
      chatableColor: chatableColor,
      chatableReadRestricted: chatableReadRestricted,
      autoJoinUsers: autoJoinUsers,
      threadingEnabled: threadingEnabled ?? this.threadingEnabled,
      membershipsCount: membershipsCount,
      currentUserMembership:
          currentUserMembership ?? this.currentUserMembership,
      lastMessage: lastMessage ?? this.lastMessage,
      messageBusLastIds: messageBusLastIds,
      directMessageUsers: directMessageUsers,
    );
  }
}

/// `GET /chat/api/me/channels` 的索引响应
class ChatChannelIndex {
  final List<ChatChannel> publicChannels;
  final List<ChatChannel> directMessageChannels;
  final Map<String, dynamic> tracking;
  final Map<String, dynamic>? globalPresenceChannelState;

  const ChatChannelIndex({
    required this.publicChannels,
    required this.directMessageChannels,
    this.tracking = const {},
    this.globalPresenceChannelState,
  });

  /// 全部频道（公开 + 直接消息）
  List<ChatChannel> get allChannels => [
    ...publicChannels,
    ...directMessageChannels,
  ];

  factory ChatChannelIndex.fromJson(Map<String, dynamic> json) {
    final public = _parseChannels(json['public_channels']);
    final direct = _parseChannels(json['direct_message_channels']);
    return ChatChannelIndex(
      publicChannels: public,
      directMessageChannels: direct,
      tracking: json['tracking'] is Map<String, dynamic>
          ? json['tracking'] as Map<String, dynamic>
          : const {},
      globalPresenceChannelState:
          json['global_presence_channel_state'] is Map<String, dynamic>
          ? json['global_presence_channel_state'] as Map<String, dynamic>
          : null,
    );
  }

  static List<ChatChannel> _parseChannels(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatChannel.fromJson)
        .toList();
  }
}

/// `GET /chat/api/channels` 的频道目录响应。
class ChatChannelDirectoryPage {
  final List<ChatChannel> channels;
  final String? loadMoreUrl;

  const ChatChannelDirectoryPage({required this.channels, this.loadMoreUrl});

  bool get hasMore => loadMoreUrl != null && loadMoreUrl!.isNotEmpty;

  factory ChatChannelDirectoryPage.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final meta = json['meta'];
    return ChatChannelDirectoryPage(
      channels: rawChannels is List
          ? rawChannels
                .whereType<Map<String, dynamic>>()
                .map(ChatChannel.fromJson)
                .toList()
          : const [],
      loadMoreUrl: meta is Map ? meta['load_more_url'] as String? : null,
    );
  }
}
