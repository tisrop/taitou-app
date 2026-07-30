// ignore_for_file: invalid_use_of_protected_member

part of '../post_footer_section.dart';

extension _PostFooterReactionActions on _PostFooterSectionState {
  bool _hasStandardLike(Post post) {
    return post.actionsSummary?.any((item) {
          if (item is! Map) return false;
          return item['id'] == 2 && item['acted'] == true;
        }) ??
        false;
  }

  void _syncReactionToProvider(
    List<PostReaction> reactions,
    PostReaction? currentUserReaction,
  ) {
    // 经活跃实例注册表找回页面 provider:页面 params 带 UUID instanceId,
    // 这里凭 topicId 直接 new 一个空 instanceId 的 params 只会命中(并
    // 凭空创建+全量拉取)一个孤儿实例,更新落不到在显示的数据上。
    final params = TopicDetailNotifier.activeParamsFor(widget.topicId);
    if (params == null) return;

    try {
      ref
          .read(topicDetailProvider(params).notifier)
          .updatePostReaction(widget.post.id, reactions, currentUserReaction);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _toggleLike() async {
    if (_isLiking) return;

    HapticFeedback.lightImpact();
    setState(() => _isLiking = true);

    try {
      final usesPluginReactions =
          AppConstants.siteCustomization.discourseReactionsEnabled ||
          widget.post.reactions != null;
      if (!usesPluginReactions) {
        final wasLiked = _currentUserReaction != null;
        if (wasLiked) {
          await _service.unlikePost(widget.post.id);
        } else {
          await _service.likePost(widget.post.id);
        }
        if (!mounted) return;

        final oldCount = _reactions.isEmpty ? 0 : _reactions.first.count;
        final newCount = (oldCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
        setState(() {
          _reactions = newCount > 0
              ? [PostReaction(id: 'heart', type: 'emoji', count: newCount)]
              : [];
          _currentUserReaction = wasLiked
              ? null
              : PostReaction(id: 'heart', type: 'emoji', count: newCount);
        });
        _syncReactionToProvider(_reactions, _currentUserReaction);
        return;
      }

      final reactionId = _currentUserReaction?.id ?? 'heart';
      final result = await _service.toggleReaction(widget.post.id, reactionId);
      if (!mounted) return;

      setState(() {
        _reactions = result['reactions'] as List<PostReaction>;
        _currentUserReaction = result['currentUserReaction'] as PostReaction?;
      });

      _syncReactionToProvider(_reactions, _currentUserReaction);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isLiking = false);
      }
    }
  }

  Future<void> _toggleReaction(String reactionId) async {
    try {
      final result = await _service.toggleReaction(widget.post.id, reactionId);
      if (!mounted) return;

      setState(() {
        _reactions = result['reactions'] as List<PostReaction>;
        _currentUserReaction = result['currentUserReaction'] as PostReaction?;
      });

      _syncReactionToProvider(_reactions, _currentUserReaction);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  void _showReactionUsers(BuildContext context, {String? reactionId}) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PostReactionUsersSheet(
        postId: widget.post.id,
        initialReactionId: reactionId,
      ),
    );
  }
}
