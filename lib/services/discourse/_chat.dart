part of 'discourse_service.dart';

/// 聊天（discourse-chat）相关
///
/// 对齐官方 Discourse chat 插件的 `/chat/api/*` 端点。聊天仅限已登录用户，
/// 匿名访问返回 403；各方法在未登录时抛出异常交由上层引导登录。
mixin _ChatMixin on _DiscourseServiceBase {
  /// 当前用户可见的频道列表（公开频道 + 直接消息频道）。
  ///
  /// 对应 `GET /chat/api/me/channels`，响应含 `public_channels` /
  /// `direct_message_channels` / `meta.message_bus_last_ids` 等。
  Future<ChatChannelIndex> getChatChannels() async {
    await requireAuthenticated();
    try {
      final response = await _dio.get('/chat/api/me/channels');
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat channels response');
      }
      return ChatChannelIndex.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 浏览当前用户可访问的公开聊天频道。
  ///
  /// 对应 `GET /chat/api/channels`。`status` 支持 open / closed；不传时
  /// 返回全部状态。响应根键为 `channels`，并可能通过 meta.load_more_url
  /// 提供下一页地址。
  Future<ChatChannelDirectoryPage> getChatChannelDirectory({
    String? filter,
    String? status,
    int offset = 0,
    int limit = 50,
  }) async {
    await requireAuthenticated();
    try {
      final normalizedFilter = filter?.trim();
      final response = await _dio.get(
        '/chat/api/channels',
        queryParameters: {
          if (normalizedFilter?.isNotEmpty == true) 'filter': normalizedFilter,
          if (status == 'open' || status == 'closed') 'status': status,
          'offset': offset,
          'limit': limit,
        },
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat channel directory response');
      }
      return ChatChannelDirectoryPage.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 加入一个公开聊天频道，成功响应根键为 `membership`。
  Future<ChatChannelMembership> joinChatChannel(int channelId) async {
    await requireAuthenticated();
    try {
      final response = await _dio.post(
        '/chat/api/channels/$channelId/memberships/me',
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat membership response');
      }
      final membership = Map<String, dynamic>.from(raw)['membership'];
      if (membership is! Map) {
        throw const FormatException('Invalid chat membership response');
      }
      return ChatChannelMembership.fromJson(
        Map<String, dynamic>.from(membership),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 离开频道并移除当前用户的频道成员关系。
  ///
  /// 对应 `DELETE /chat/api/channels/{channelId}/memberships/me`。
  Future<void> leaveChatChannel(int channelId) async {
    await requireAuthenticated();
    try {
      await _dio.delete(
        '/chat/api/channels/$channelId/memberships/me',
        options: Options(extra: {'showErrorToast': false}),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建分类聊天频道。
  ///
  /// 对应 `POST /chat/api/channels`，官方控制器要求所有字段位于
  /// `channel` 根键下。
  Future<ChatChannel> createCategoryChatChannel({
    required int categoryId,
    required String name,
    String? slug,
    String? description,
    String? emoji,
    bool autoJoinUsers = false,
    bool threadingEnabled = false,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Channel name is required');
    }

    await requireAuthenticated();
    try {
      final normalizedSlug = slug?.trim();
      final normalizedDescription = description?.trim();
      final normalizedEmoji = emoji?.trim();
      final response = await _dio.post(
        '/chat/api/channels',
        data: {
          'channel': {
            'chatable_id': categoryId,
            'name': normalizedName,
            if (normalizedSlug?.isNotEmpty == true) 'slug': normalizedSlug,
            if (normalizedDescription?.isNotEmpty == true)
              'description': normalizedDescription,
            if (normalizedEmoji?.isNotEmpty == true) 'emoji': normalizedEmoji,
            'auto_join_users': autoJoinUsers,
            'threading_enabled': threadingEnabled,
          },
        },
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid create chat channel response');
      }
      final channel = Map<String, dynamic>.from(raw)['channel'];
      if (channel is! Map) {
        throw const FormatException('Invalid create chat channel response');
      }
      return ChatChannel.fromJson(Map<String, dynamic>.from(channel));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建或获取一个直接消息草稿频道。
  ///
  /// 对应 `POST /chat/api/direct-message-channels`。官方接口按用户名接收
  /// `target_usernames[]`；`upsert: true` 会在一对一私聊已存在时直接返回
  /// 原频道。新频道要等首条消息发送成功后才会由服务端发布并加入直接消息目录，
  /// 因此调用方不能仅凭此响应把空频道持久化到本地目录。
  Future<ChatChannel> createDirectMessageChannel(
    List<String> targetUsernames, {
    bool upsert = true,
    String? name,
  }) async {
    final usernames = targetUsernames
        .map((username) => username.trim())
        .where((username) => username.isNotEmpty)
        .toSet()
        .toList();
    if (usernames.isEmpty) {
      throw ArgumentError.value(
        targetUsernames,
        'targetUsernames',
        'At least one target username is required',
      );
    }

    await requireAuthenticated();
    try {
      final channelName = name?.trim();
      final response = await _dio.post(
        '/chat/api/direct-message-channels',
        data: {
          'target_usernames': usernames,
          'upsert': upsert,
          if (channelName?.isNotEmpty == true) 'name': channelName,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          listFormat: ListFormat.multiCompatible,
        ),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid direct message response');
      }
      final channel = Map<String, dynamic>.from(raw)['channel'];
      if (channel is! Map) {
        throw const FormatException('Invalid direct message response');
      }
      return ChatChannel.fromJson(Map<String, dynamic>.from(channel));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 单个聊天频道详情。
  ///
  /// 对应 `GET /chat/api/channels/{channelId}`，响应根键为 `channel`。
  Future<ChatChannel> getChatChannel(int channelId) async {
    await requireAuthenticated();
    try {
      final response = await _dio.get('/chat/api/channels/$channelId');
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat channel response');
      }
      final channel = Map<String, dynamic>.from(raw)['channel'];
      if (channel is! Map<String, dynamic>) {
        throw const FormatException('Invalid chat channel response');
      }
      return ChatChannel.fromJson(channel);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 收藏或取消收藏当前频道。
  ///
  /// 对应 `PUT /chat/api/channels/{channelId}/memberships/me`。
  Future<ChatChannelMembership> setChatChannelStarred(
    int channelId, {
    required bool starred,
  }) async {
    await requireAuthenticated();
    try {
      final response = await _dio.put(
        '/chat/api/channels/$channelId/memberships/me',
        data: {'starred': starred},
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat membership response');
      }
      final membership = Map<String, dynamic>.from(raw)['membership'];
      if (membership is! Map) {
        throw const FormatException('Invalid chat membership response');
      }
      return ChatChannelMembership.fromJson(
        Map<String, dynamic>.from(membership),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 更新当前用户在频道内的免打扰或推送通知设置。
  ///
  /// 对应 `PUT /chat/api/channels/{channelId}/notifications-settings/me`。
  Future<ChatChannelMembership> updateChatChannelNotificationSettings(
    int channelId, {
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) async {
    if (muted == null && notificationLevel == null) {
      throw ArgumentError('At least one notification setting is required');
    }

    final settings = <String, dynamic>{};
    if (muted != null) settings['muted'] = muted;
    if (notificationLevel != null) {
      settings['notification_level'] = notificationLevel.value;
    }

    await requireAuthenticated();
    try {
      final response = await _dio.put(
        '/chat/api/channels/$channelId/notifications-settings/me',
        data: {'notifications_settings': settings},
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat membership response');
      }
      final membership = Map<String, dynamic>.from(raw)['membership'];
      if (membership is! Map) {
        throw const FormatException('Invalid chat membership response');
      }
      return ChatChannelMembership.fromJson(
        Map<String, dynamic>.from(membership),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 开启或关闭频道消息串。
  ///
  /// 对应 `PUT /chat/api/channels/{channelId}`。
  Future<ChatChannel> setChatChannelThreadingEnabled(
    int channelId, {
    required bool enabled,
  }) async {
    await requireAuthenticated();
    try {
      final response = await _dio.put(
        '/chat/api/channels/$channelId',
        data: {
          'channel': {'threading_enabled': enabled},
        },
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat channel response');
      }
      final channel = Map<String, dynamic>.from(raw)['channel'];
      if (channel is! Map) {
        throw const FormatException('Invalid chat channel response');
      }
      return ChatChannel.fromJson(Map<String, dynamic>.from(channel));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取频道内当前用户可见的消息串。
  Future<ChatThreadsPage> getChatThreads(
    int channelId, {
    int offset = 0,
    int limit = chatThreadsMaxPageSize,
  }) async {
    await requireAuthenticated();
    try {
      // The server validates this parameter against a maximum of 10.
      final normalizedLimit = limit.clamp(1, chatThreadsMaxPageSize).toInt();
      final response = await _dio.get(
        '/chat/api/channels/$channelId/threads',
        queryParameters: {'offset': offset, 'limit': normalizedLimit},
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat threads response');
      }
      return ChatThreadsPage.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取指定消息串中的回复消息。
  Future<ChatMessagesPage> getChatThreadMessages(
    int channelId,
    int threadId, {
    int pageSize = 50,
  }) async {
    await requireAuthenticated();
    try {
      final response = await _dio.get(
        '/chat/api/channels/$channelId/threads/$threadId/messages',
        queryParameters: {'page_size': pageSize},
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat thread messages response');
      }
      return ChatMessagesPage.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 拉取某个频道的消息（可分页 / 锚定）。
  ///
  /// 对应 `GET /chat/api/channels/{channelId}/messages`。
  ///
  /// - [direction]: `past`（向前加载历史）或 `future`。**只在翻页时传**：
  ///   服务端 `MessagesQuery` 是 `if target_message_id.present? && direction.blank?`
  ///   才走「围绕锚点取前后各若干条」，带上 direction 就变成单向分页。初次进
  ///   频道要的是前者，否则只能看到已读位置之前的消息。
  /// - [targetMessageId]: 锚定某条消息，围绕它取 [pageSize] 条。
  /// - [fetchFromLastRead]: 以最后已读位置作为锚点。
  Future<ChatMessagesPage> getChatMessages(
    int channelId, {
    int pageSize = 50,
    String? direction,
    int? targetMessageId,
    bool fetchFromLastRead = false,
  }) async {
    await requireAuthenticated();
    try {
      final response = await _dio.get(
        '/chat/api/channels/$channelId/messages',
        queryParameters: {
          'page_size': pageSize,
          'direction': ?direction,
          'target_message_id': ?targetMessageId,
          if (fetchFromLastRead) 'fetch_from_last_read': true,
        },
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat messages response');
      }
      return ChatMessagesPage.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 全局搜索当前用户可见的聊天消息。
  ///
  /// 对应 `GET /chat/api/search`。每条消息旁会附带所属 `channel`，
  /// `offset` 按已加载结果数递增；排序仅支持 relevance / latest。
  Future<ChatMessageSearchPage> searchChatMessages({
    required String query,
    ChatMessageSearchSort sort = ChatMessageSearchSort.relevance,
    int offset = 0,
    int limit = 20,
    int? channelId,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return ChatMessageSearchPage(
        hits: const [],
        limit: limit,
        offset: offset,
      );
    }

    await requireAuthenticated();
    try {
      final response = await _dio.get(
        '/chat/api/search',
        queryParameters: {
          'query': normalizedQuery,
          'sort': sort.apiValue,
          'offset': offset,
          'limit': limit.clamp(1, 40),
          'channel_id': ?channelId,
        },
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid chat search response');
      }
      return ChatMessageSearchPage.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 发送一条聊天消息。
  ///
  /// 对应 `POST /chat/{channelId}`（路由表里是
  /// `post "/:chat_channel_id" => "api/channel_messages#create"`，
  /// `/chat/api/channels/{id}/messages` 只有 GET，没有 POST）。
  /// [stagedId] 是客户端暂存 ID，服务端会原样放进 `sent` 事件回传。
  /// 成功响应为 `{success: "OK", message_id: <int>}`。
  Future<int> sendChatMessage(
    int channelId, {
    required String message,
    String? stagedId,
    int? inReplyToId,
  }) async {
    await requireAuthenticated();
    try {
      final response = await _dio.post(
        '/chat/$channelId',
        data: {
          'message': message,
          'staged_id': ?stagedId,
          'in_reply_to_id': ?inReplyToId,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          // 发送失败由聊天页展示本地化 SnackBar，避免全局拦截器重复提示。
          extra: {'showErrorToast': false},
        ),
      );
      final body = response.data;
      if (body is! Map) {
        throw const FormatException('Invalid send chat message response');
      }
      final messageId = body['message_id'];
      if (messageId is! int) {
        throw const FormatException('Missing message_id in send response');
      }
      return messageId;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 删除一条聊天消息。
  Future<void> deleteChatMessage(int channelId, int messageId) async {
    await requireAuthenticated();
    try {
      await _dio.delete(
        '/chat/api/channels/$channelId/messages/$messageId',
        options: Options(extra: {'showErrorToast': false}),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 添加或移除聊天消息的表情回应。
  Future<void> publishChatReaction(
    int channelId,
    int messageId, {
    required String emoji,
    required bool add,
  }) async {
    await requireAuthenticated();
    try {
      await _dio.put(
        '/chat/$channelId/react/$messageId',
        data: {'react_action': add ? 'add' : 'remove', 'emoji': emoji},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: {'showErrorToast': false},
        ),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> setChatMessagePinned(
    int channelId,
    int messageId, {
    required bool pinned,
  }) async {
    await requireAuthenticated();
    final path = '/chat/api/channels/$channelId/messages/$messageId/pin';
    try {
      if (pinned) {
        await _dio.post(
          path,
          options: Options(extra: {'showErrorToast': false}),
        );
      } else {
        await _dio.delete(
          path,
          options: Options(extra: {'showErrorToast': false}),
        );
      }
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> rebakeChatMessage(int channelId, int messageId) async {
    await requireAuthenticated();
    try {
      await _dio.put(
        '/chat/$channelId/$messageId/rebake',
        options: Options(extra: {'showErrorToast': false}),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> flagChatMessage(
    int channelId,
    int messageId,
    int flagTypeId, {
    String? message,
  }) async {
    await requireAuthenticated();
    try {
      await _dio.post(
        '/chat/api/channels/$channelId/messages/$messageId/flags',
        data: {
          'flag_type_id': flagTypeId,
          if (message != null && message.isNotEmpty) 'message': message,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: {'showErrorToast': false},
        ),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建聊天消息收藏，返回 bookmark id。
  Future<int> bookmarkChatMessage(int messageId) async {
    await requireAuthenticated();
    try {
      final response = await _dio.post(
        '/bookmarks.json',
        data: {
          'bookmarkable_id': messageId,
          'bookmarkable_type': 'Chat::Message',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: {'showErrorToast': false},
        ),
      );
      final data = response.data;
      if (data is Map && data['id'] is int) return data['id'] as int;
      throw const FormatException('Invalid chat bookmark response');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 上报频道已读位置。
  ///
  /// 对应 `PUT /chat/api/channels/{channelId}/read`。参数名是 `message_id`
  /// （`Chat::UpdateUserChannelLastRead` 的契约），不是 `last_read_message_id`。
  Future<void> markChatChannelRead(int channelId, int lastReadMessageId) async {
    await requireAuthenticated();
    try {
      await _dio.put(
        '/chat/api/channels/$channelId/read',
        data: {'message_id': lastReadMessageId},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          // 后台静默上报，失败不该弹 toast 打扰用户
          extra: {'showErrorToast': false},
        ),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> requireAuthenticated() async {
    // 注意：不要用 isAuthenticated——它只反映内存里的 _tToken，而 credentials
    // 是异步从 storage 加载的，页面冷启动时可能尚未就绪，会把已登录用户误判为
    // 未登录。这里回退读持久化 storage，反映真实的持久化登录态。
    if (_username != null && _username!.isNotEmpty) return;
    final persisted = await _storage.read(key: DiscourseService._usernameKey);
    if (persisted != null && persisted.isNotEmpty) {
      _username = persisted;
      return;
    }
    throw Exception(S.current.error_notLoggedInNoUsername);
  }
}
