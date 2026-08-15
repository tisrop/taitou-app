import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pm_recipient_field.dart';
import '../markdown_editor/composer_shortcuts.dart';
import '../markdown_editor/markdown_editor.dart';
import '../../models/topic.dart';
import '../../models/draft.dart';
import '../../models/pending_post.dart';
import '../../pages/pending_posts_page.dart';
import '../../services/local_notification_service.dart' show navigatorKey;
import '../../services/discourse/discourse_service.dart';
import '../../services/ai_post_review_service.dart';
import '../../services/presence_service.dart';
import '../../services/emoji_handler.dart';
import '../../services/draft_controller.dart';
import 'package:dio/dio.dart';
import '../../services/app_error_handler.dart';
import '../../services/network/exceptions/api_exception.dart';
import '../../services/toast_service.dart';
import '../../services/preloaded_data_service.dart';
import '../../l10n/s.dart';
import '../../utils/dialog_utils.dart';
import '../../providers/shortcut_provider.dart';
import '../ai/ai_post_review_button.dart';
import 'package:m3e_ui/m3e_ui.dart';

/// 显示回复底部弹框
/// [topicId] 话题 ID (回复话题/帖子时必需)
/// [categoryId] 分类 ID（可选，用于用户搜索）
/// [replyToPost] 可选，被回复的帖子
/// [targetUsername] 可选，私信目标用户名 (创建私信时必需)
/// [draftKey] 可选，恢复已有草稿时传入原草稿 key（草稿列表入口使用）
/// [preloadedDraftFuture] 预加载的草稿 Future（在点击回复按钮时就发起请求）
/// [initialContent] 可选，预填内容（划词引用时使用）
/// [initialTitle] 可选，预填标题（私信模式时使用）
/// [onEnqueued] 可选，帖子被送审时回调(携带待审内容摘要);
/// 不传时降级为 toast 提示 + 「查看」跳转待审列表页
/// 返回创建的 Post 对象，取消或失败返回 null
Future<Post?> showReplySheet({
  required BuildContext context,
  int? topicId,
  int? categoryId,
  Post? replyToPost,
  String? targetUsername,

  /// 新建私信（无预设收件人）：收件人由用户在编辑器内搜索添加
  bool composePrivateMessage = false,
  String? draftKey,
  Future<Draft?>? preloadedDraftFuture,
  String? initialContent,
  String? initialTitle,
  String? topicTitle,
  bool isPrivateMessageTopic = false,
  bool isPmWithNonHumanUser = false,
  ShortcutSurfaceConfig? shortcutSurface,
  ValueChanged<PendingPost>? onEnqueued,
}) async {
  final result = await showAppBottomSheet<Post?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    shortcutSurface: shortcutSurface,
    builder: (context) => ReplySheet(
      topicId: topicId,
      categoryId: categoryId,
      replyToPost: replyToPost,
      targetUsername: targetUsername,
      composePrivateMessage: composePrivateMessage,
      draftKey: draftKey,
      preloadedDraftFuture: preloadedDraftFuture,
      initialContent: initialContent,
      initialTitle: initialTitle,
      topicTitle: topicTitle,
      isPrivateMessageTopic: isPrivateMessageTopic,
      isPmWithNonHumanUser: isPmWithNonHumanUser,
      onEnqueued: onEnqueued,
    ),
  );
  return result;
}

/// 显示编辑帖子底部弹框
/// [topicId] 话题 ID
/// [post] 要编辑的帖子
/// [categoryId] 分类 ID（可选，用于用户搜索）
/// 返回更新后的 Post 对象，取消或失败返回 null
Future<Post?> showEditSheet({
  required BuildContext context,
  required int topicId,
  required Post post,
  int? categoryId,
  bool isPrivateMessageTopic = false,
  bool isPmWithNonHumanUser = false,
  ShortcutSurfaceConfig? shortcutSurface,
}) async {
  final result = await showAppBottomSheet<Post?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    shortcutSurface: shortcutSurface,
    builder: (context) => ReplySheet(
      topicId: topicId,
      categoryId: categoryId,
      editPost: post,
      isPrivateMessageTopic: isPrivateMessageTopic,
      isPmWithNonHumanUser: isPmWithNonHumanUser,
    ),
  );
  return result;
}

class ReplySheet extends ConsumerStatefulWidget {
  final int? topicId;
  final int? categoryId;
  final Post? replyToPost;
  final String? targetUsername;

  /// 新建私信（无预设收件人）
  final bool composePrivateMessage;
  final String? draftKey; // 恢复已有草稿时传入的原草稿 key
  final Post? editPost; // 编辑模式：要编辑的帖子
  final Future<Draft?>? preloadedDraftFuture; // 预加载的草稿
  final String? initialContent; // 预填内容（划词引用时使用）
  final String? initialTitle; // 预填标题（私信模式时使用）
  final String? topicTitle; // 普通回帖审核时带上的话题标题
  final bool isPrivateMessageTopic; // 当前话题是否为私信话题
  final bool isPmWithNonHumanUser; // 当前私信话题是否包含非真人用户
  final ValueChanged<PendingPost>? onEnqueued; // 帖子被送审时回调

  const ReplySheet({
    super.key,
    this.topicId,
    this.categoryId,
    this.replyToPost,
    this.targetUsername,
    this.composePrivateMessage = false,
    this.draftKey,
    this.editPost,
    this.preloadedDraftFuture,
    this.initialContent,
    this.initialTitle,
    this.topicTitle,
    this.isPrivateMessageTopic = false,
    this.isPmWithNonHumanUser = false,
    this.onEnqueued,
  });

  @override
  ConsumerState<ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends ConsumerState<ReplySheet> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _editorKey = GlobalKey<MarkdownEditorState>();

  bool _isSubmitting = false;
  bool _submitted = false; // 提交成功标志，防止 dispose 重新保存草稿
  bool _discarded = false; // 用户明确舍弃，防止 dispose 重新保存草稿
  bool _showEmojiPanel = false;
  bool _isLoadingRaw = false; // 编辑模式：加载原始内容中
  bool _isLoadingDraft = false; // 加载草稿中
  bool _isChangingReplyTarget = false;

  late Post? _replyToPost;

  // 表情面板高度
  static const double _emojiPanelHeight = 336.0;

  // 草稿控制器（仅在回复话题或创建私信时使用，编辑模式不使用）
  DraftController? _draftController;

  // Presence 服务（正在输入状态）
  PresenceService? _presenceService;

  // 私信收件人（初始为目标用户，从草稿恢复时还原草稿中的完整收件人列表）
  late List<String> _recipients = [
    if (widget.targetUsername != null) widget.targetUsername!,
  ];

  bool get _isPrivateMessage =>
      widget.targetUsername != null || widget.composePrivateMessage;

  /// 收件人可编辑：新建私信场景（已指定对象的「发私信给某人」不改收件人）
  bool get _canEditRecipients => widget.composePrivateMessage;

  /// 是否在私信话题中（创建新私信 或 回复已有私信话题）
  bool get _isInPrivateMessageContext =>
      _isPrivateMessage || widget.isPrivateMessageTopic;
  bool get _isEditMode => widget.editPost != null;
  bool get _canReviewPost =>
      !_isEditMode &&
      !_isPrivateMessage &&
      !_isInPrivateMessageContext &&
      widget.topicId != null;

  @override
  void initState() {
    super.initState();
    _replyToPost = widget.replyToPost;
    EmojiHandler().init();

    // 编辑模式：加载帖子原始内容
    if (_isEditMode) {
      _loadPostRaw();
    } else {
      // 预填内容（划词引用）
      if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
        _contentController.text = widget.initialContent!;
        // 光标移到末尾
        _contentController.selection = TextSelection.fromPosition(
          TextPosition(offset: _contentController.text.length),
        );
      }
      // 预填标题（私信模式）
      if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
        _titleController.text = widget.initialTitle!;
      }
      // 非编辑模式：初始化草稿控制器并加载草稿
      _initDraftController();
    }

    // 初始化 Presence 服务（非私信场景、非编辑模式）
    if (!_isInPrivateMessageContext && !_isEditMode && widget.topicId != null) {
      _presenceService = PresenceService(DiscourseService());
      _presenceService!.enterReplyChannel(widget.topicId!);
    }

    // 添加内容变化监听以触发草稿自动保存
    _contentController.addListener(_onContentChanged);
    _titleController.addListener(_onContentChanged);

    // 自动聚焦（非编辑模式时立即聚焦，编辑模式在加载完成后聚焦）
    if (!_isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isLoadingDraft) {
          _contentFocusNode.requestFocus();
        }
      });
    }
  }

  /// 初始化草稿控制器
  void _initDraftController() {
    String draftKey;
    var shouldLoadDraft = true;
    if (widget.draftKey != null) {
      // 草稿列表入口：沿用原草稿 key 恢复
      draftKey = widget.draftKey!;
    } else if (_isPrivateMessage) {
      // 对齐 Discourse（services/composer.js privateMessageDraftKey）：
      // 新私信用带时间戳的唯一 key，不自动带回其他私信的草稿，
      // 避免给 A 写一半的草稿被带进给 B 的私信窗口造成串发
      draftKey = Draft.generateNewPrivateMessageKey();
      shouldLoadDraft = false; // 全新 key 服务端必无草稿，跳过加载
    } else if (widget.topicId != null) {
      // 区分回复话题和回复帖子
      draftKey = Draft.replyKey(
        widget.topicId!,
        replyToPostNumber: _replyToPost?.postNumber,
      );
    } else {
      return;
    }

    _draftController = DraftController(draftKey: draftKey);
    if (shouldLoadDraft) {
      _loadExistingDraft();
    }
  }

  /// 加载现有草稿
  Future<void> _loadExistingDraft() async {
    setState(() => _isLoadingDraft = true);
    try {
      final draft = await _draftController?.loadDraft(
        preloadedDraftFuture: widget.preloadedDraftFuture,
      );
      if (!mounted) return;

      if (draft != null && draft.hasContent) {
        // 回复模式直接恢复，不需要确认
        _restoreDraft(draft);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
        _contentFocusNode.requestFocus();
      }
    }
  }

  /// 舍弃草稿
  Future<void> _discardDraft() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.post_discardTitle),
        content: Text(context.l10n.post_discardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.common_discard),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _discarded = true;
      await _draftController?.deleteDraft();
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 恢复草稿内容
  void _restoreDraft(Draft draft) {
    if (draft.data.reply != null) {
      // 有预填内容时，将草稿追加到引用内容后面
      if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
        _contentController.text = '${widget.initialContent}${draft.data.reply}';
      } else {
        _contentController.text = draft.data.reply!;
      }
    }
    if (_isPrivateMessage) {
      if (draft.data.title != null) {
        _titleController.text = draft.data.title!;
      }
      // 对齐 Discourse loadDraft：收件人以草稿数据为准（支持多收件人）
      final recipients = draft.data.recipients;
      if (recipients != null && recipients.isNotEmpty) {
        setState(() => _recipients = List.of(recipients));
      }
    }
  }

  /// 内容变化时触发草稿保存
  void _onContentChanged() {
    if (_isEditMode || _draftController == null) return;

    _draftController!.scheduleSave(_currentDraftData());
  }

  DraftData _currentDraftData() {
    return DraftData(
      reply: _contentController.text,
      title: _isPrivateMessage ? _titleController.text : null,
      action: _isPrivateMessage ? 'privateMessage' : 'reply',
      replyToPostNumber: _replyToPost?.postNumber,
      recipients: _isPrivateMessage ? _recipients : null,
      archetypeId: _isPrivateMessage ? 'private_message' : 'regular',
    );
  }

  Future<void> _changeReplyTarget(Post? target) async {
    if (_isPrivateMessage || _isEditMode || widget.topicId == null) return;
    if (_replyToPost?.postNumber == target?.postNumber) return;

    setState(() => _isChangingReplyTarget = true);

    final previous = _draftController;
    previous?.disable();
    await previous?.deleteDraft();
    previous?.dispose();
    if (!mounted) return;

    setState(() {
      _replyToPost = target;
      _draftController = DraftController(
        draftKey: Draft.replyKey(
          widget.topicId!,
          replyToPostNumber: target?.postNumber,
        ),
      );
      _isChangingReplyTarget = false;
    });
    _draftController?.scheduleSave(_currentDraftData());
  }

  /// 加载帖子原始内容
  Future<void> _loadPostRaw() async {
    setState(() => _isLoadingRaw = true);
    try {
      final raw = await DiscourseService().getPostRaw(widget.editPost!.id);
      if (mounted && raw != null) {
        _contentController.text = raw;
        // 加载完成后聚焦并将光标移到末尾
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _contentFocusNode.requestFocus();
          _contentController.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentController.text.length),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(
          S.current.post_loadContentFailed(
            e.toString().replaceAll('Exception: ', ''),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRaw = false);
    }
  }

  @override
  void dispose() {
    // 移除监听器
    _contentController.removeListener(_onContentChanged);
    _titleController.removeListener(_onContentChanged);

    // 关闭时处理草稿：已提交则跳过，有内容则保存，无内容则删除
    if (_draftController != null && !_submitted && !_discarded) {
      final hasContent =
          _contentController.text.trim().isNotEmpty ||
          (_isPrivateMessage && _titleController.text.trim().isNotEmpty);
      if (hasContent) {
        // 异步保存，不阻塞 dispose
        _draftController!.saveNow(_currentDraftData());
      } else {
        // 内容为空，删除草稿
        _draftController!.deleteDraft();
      }
    }
    _draftController?.dispose();

    // 释放 Presence 服务（会自动离开频道）
    _presenceService?.dispose();

    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _showError(String message) {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.common_hint),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _showError(S.current.post_contentRequired);
      return;
    }

    // 最小字数校验
    final preloaded = PreloadedDataService();
    final minLength = widget.isPmWithNonHumanUser
        ? 1
        : _isInPrivateMessageContext
        ? await preloaded.getMinPmPostLength()
        : await preloaded.getMinPostLength();
    if (content.length < minLength) {
      ToastService.showInfo(S.current.createTopic_minContentLength(minLength));
      return;
    }

    if (_isPrivateMessage && _titleController.text.trim().isEmpty) {
      _showError(S.current.post_titleRequired);
      return;
    }

    // 新建私信必须有收件人（已指定对象的场景收件人固定，天然非空）
    if (_isPrivateMessage && _recipients.isEmpty) {
      _showError(S.current.pm_noRecipient);
      return;
    }

    setState(() => _isSubmitting = true);
    // 对齐 Discourse 前端 composer.set("disableDrafts", true):
    // 发送途中关掉自动保存,避免与 PostCreator 推进的 draft_sequence 撞 409
    _draftController?.disable();

    try {
      if (_isEditMode) {
        // 编辑模式：更新帖子
        final updatedPost = await DiscourseService().updatePost(
          postId: widget.editPost!.id,
          raw: content,
        );
        if (!mounted) return;
        Navigator.of(context).pop(updatedPost);
      } else if (_isPrivateMessage) {
        await DiscourseService().createPrivateMessage(
          targetUsernames: _recipients,
          title: _titleController.text.trim(),
          raw: content,
          draftKey: _draftController?.draftKey,
          onDraftSequence: (seq) => _draftController?.syncSequence(seq),
        );
        // 发送成功后删除草稿
        await _draftController?.deleteDraft();
        _submitted = true;
        if (!mounted) return;
        Navigator.of(context).pop(null); // 私信模式不返回 Post
      } else {
        // 回复模式：返回创建的 Post 对象
        final newPost = await DiscourseService().createReply(
          topicId: widget.topicId!,
          raw: content,
          replyToPostNumber: _replyToPost?.postNumber,
          draftKey: _draftController?.draftKey,
          onDraftSequence: (seq) => _draftController?.syncSequence(seq),
        );
        // 发送成功后删除草稿
        await _draftController?.deleteDraft();
        _submitted = true;
        if (!mounted) return;
        Navigator.of(context).pop(newPost);
      }
    } on PostEnqueuedException catch (e) {
      // 审核场景：删除草稿，提示用户，关闭编辑器
      await _draftController?.deleteDraft();
      _submitted = true;
      if (!mounted) return;
      final pending = e.pendingPost;
      if (pending != null &&
          widget.editPost == null &&
          widget.topicId != null) {
        // enqueued 响应的 pending_post 只有 {id, raw, created_at},回复目标
        // 服务端 payload 存了但本人可见接口都不吐;趁 composer 还知道上下文
        // 记入注册表,「撤回并重新编辑」才能恢复"回复某楼"而非退化为直接回复话题
        PendingReplyTargetRegistry.record(pending.id, _replyToPost?.postNumber);
      }
      if (widget.onEnqueued != null && pending != null) {
        // 宿主接管展示(如主题页底部待审块),轻提示即可
        widget.onEnqueued!(pending);
        ToastService.showInfo(S.current.post_pendingReview);
      } else {
        // 无宿主接管:toast 带「查看」入口跳待审列表页
        ToastService.show(
          S.current.post_pendingReview,
          type: ToastType.info,
          actionLabel: S.current.review_viewAction,
          onAction: () {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const PendingPostsPage()),
            );
          },
        );
      }
      Navigator.of(context).pop();
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理:发送失败,恢复草稿保存
      _draftController?.enable();
    } catch (e, s) {
      _draftController?.enable();
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 构建草稿保存状态指示器
  Widget _buildDraftStatusIndicator(DraftSaveStatus status, ThemeData theme) {
    switch (status) {
      case DraftSaveStatus.idle:
        return const SizedBox.shrink();
      case DraftSaveStatus.pending:
        return const SizedBox.shrink();
      case DraftSaveStatus.saving:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.outline,
          ),
        );
      case DraftSaveStatus.saved:
        return Icon(
          Symbols.cloud_done_rounded,
          size: 16,
          color: theme.colorScheme.outline,
        );
      case DraftSaveStatus.error:
        return Icon(
          Symbols.cloud_off_rounded,
          size: 16,
          color: theme.colorScheme.error,
        );
    }
  }

  Widget _buildComposerTitle(ThemeData theme) {
    final originalReplyTarget = widget.replyToPost;
    final canChangeReplyTarget =
        originalReplyTarget != null &&
        !_isEditMode &&
        !_isPrivateMessage &&
        widget.draftKey == null;
    final disabled =
        _isSubmitting ||
        _isLoadingRaw ||
        _isLoadingDraft ||
        _isChangingReplyTarget;

    final String label;
    if (_isEditMode) {
      label = context.l10n.post_editPostTitle(widget.editPost!.postNumber);
    } else if (_isPrivateMessage) {
      label = _canEditRecipients
          ? context.l10n.pm_newTitle
          : context.l10n.post_sendPmTitle(_recipients.join(', '));
    } else if (_replyToPost != null) {
      label = context.l10n.post_replyToUser(_replyToPost!.username);
    } else {
      label = context.l10n.post_replyToTopic;
    }

    final title = Row(
      key: const ValueKey('replyComposerTarget'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (canChangeReplyTarget) ...[
          const SizedBox(width: 2),
          Icon(
            Symbols.keyboard_arrow_down_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );

    final titleAnchor = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, maxWidth: 190),
      child: Align(alignment: Alignment.centerLeft, child: title),
    );

    // 编辑模式和私信模式既不能切换回复目标，也不能发起 AI 审核。
    // 此时不要创建空的 PopupMenuButton，避免点击标题弹出空白浮层。
    if (!canChangeReplyTarget && !_canReviewPost) return titleAnchor;

    Widget buildMenu(bool isReviewing, VoidCallback? review) {
      return PopupMenuButton<int>(
        key: const ValueKey('replyComposerMenu'),
        enabled: !disabled,
        tooltip: context.l10n.common_more,
        onSelected: (value) {
          switch (value) {
            case 1:
              review?.call();
              break;
            case 2:
              _changeReplyTarget(originalReplyTarget);
              break;
            case 3:
              _changeReplyTarget(null);
              break;
          }
        },
        itemBuilder: (context) => [
          if (canChangeReplyTarget) ...[
            PopupMenuItem<int>(
              value: 2,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _replyToPost != null
                      ? Symbols.check_rounded
                      : Symbols.reply_rounded,
                ),
                title: Text(
                  context.l10n.post_replyToUser(originalReplyTarget.username),
                ),
              ),
            ),
            PopupMenuItem<int>(
              value: 3,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _replyToPost == null
                      ? Symbols.check_rounded
                      : Symbols.forum_rounded,
                ),
                title: Text(context.l10n.post_replyToTopic),
              ),
            ),
            const PopupMenuDivider(),
          ],
          if (_canReviewPost)
            PopupMenuItem<int>(
              value: 1,
              enabled: review != null,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: isReviewing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.auto_awesome_rounded),
                title: Text(
                  isReviewing
                      ? context.l10n.aiPostReview_reviewing
                      : context.l10n.aiPostReview_button,
                ),
              ),
            ),
        ],
        child: titleAnchor,
      );
    }

    if (!_canReviewPost) return buildMenu(false, null);
    return AiPostReviewButton(
      titleBuilder: () => widget.topicTitle,
      contentBuilder: () => _contentController.text,
      target: AiPostReviewTarget.reply,
      enabled: !disabled,
      builder: (context, isReviewing, trigger) =>
          buildMenu(isReviewing, trigger),
    );
  }

  Widget _buildComposerHeader(ThemeData theme) {
    final disabled =
        _isSubmitting ||
        _isLoadingRaw ||
        _isLoadingDraft ||
        _isChangingReplyTarget;
    final submitLabel = _isEditMode
        ? context.l10n.common_save
        : context.l10n.common_send;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 13, bottom: 11),
          child: Container(
            key: const ValueKey('replyComposerDragHandle'),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
          child: Row(
            children: [
              Expanded(child: _buildComposerTitle(theme)),
              if (_draftController != null)
                ValueListenableBuilder<DraftSaveStatus>(
                  valueListenable: _draftController!.statusNotifier,
                  builder: (context, status, _) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: _buildDraftStatusIndicator(status, theme),
                  ),
                ),
              TextButton(
                key: const ValueKey('replyComposerDiscard'),
                onPressed: disabled ? null : _discardDraft,
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: Text(context.l10n.common_discard),
              ),
              const SizedBox(width: 4),
              FilledButton(
                key: const ValueKey('replyComposerSend'),
                onPressed: disabled ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(84, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: const StadiumBorder(),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: _isSubmitting
                    ? const LoadingSpinner(size: 18, color: Colors.white)
                    : Text(submitLabel),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 使用接近全屏的编辑器布局，保留系统安全区。
    // SafeArea(bottom: false)：顶部安全区域由 SafeArea 处理，
    // 底部安全区域由 ChatBottomPanelContainer 内部管理，避免双重底部间距
    // CallbackShortcuts 包整个弹层:Cmd/Ctrl+Enter 提交(对齐 Discourse
    // composer),焦点在标题输入框时同样生效;守卫与发送按钮一致。
    final sheet = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 11),
        child: FractionallySizedBox(
          heightFactor: 1,
          alignment: Alignment.bottomCenter,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            // PopScope 用于处理表情面板开启时的返回逻辑
            body: PopScope(
              canPop: !_showEmojiPanel,
              onPopInvokedWithResult: (bool didPop, dynamic result) async {
                if (didPop) return;
                if (_showEmojiPanel) {
                  _editorKey.currentState?.closeEmojiPanel();
                  setState(() => _showEmojiPanel = false);
                }
              },
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildComposerHeader(theme),

                        // 新建私信：收件人选择（已指定对象时不显示，收件人固定）
                        if (_canEditRecipients)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: PmRecipientField(
                              recipients: _recipients,
                              autofocus: true,
                              onChanged: (v) => setState(() => _recipients = v),
                            ),
                          ),
                        // 私信标题输入框（仅私信模式）
                        if (_isPrivateMessage) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                hintText: context.l10n.common_title,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              textInputAction: TextInputAction.next,
                              onTap: () {
                                if (_showEmojiPanel) {
                                  _editorKey.currentState?.closeEmojiPanel();
                                  setState(() => _showEmojiPanel = false);
                                }
                              },
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ],

                        // 2. 回帖编辑区固定使用 Markdown，严格对应参考稿：
                        // 底部只保留表情、预览和更多工具入口。
                        Expanded(
                          child: MarkdownEditor(
                            key: _editorKey,
                            controller: _contentController,
                            focusNode: _contentFocusNode,
                            hintText: context.l10n.editor_hintText,
                            expands: true,
                            toolbarAtTop: false,
                            editorMargin: EdgeInsets.zero,
                            emojiPanelHeight: _emojiPanelHeight,
                            onEmojiPanelChanged: (show) {
                              setState(() => _showEmojiPanel = show);
                            },
                            onSwitchToRich: null,
                            mentionDataSource: (term) =>
                                DiscourseService().searchUsers(
                                  term: term,
                                  topicId: widget.topicId,
                                  categoryId: widget.categoryId,
                                  includeGroups:
                                      !_isInPrivateMessageContext, // 私信不允许提及群组
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 草稿加载遮罩
                  if (_isLoadingDraft)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.7,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: const Center(child: LoadingSpinner()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        for (final activator in composerSubmitActivators())
          activator: () {
            if (!_isSubmitting && !_isLoadingRaw) _submit();
          },
      },
      child: sheet,
    );
  }
}
