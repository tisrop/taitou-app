import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_message.dart';
import '../../services/chat_summary_service.dart';
import '../../services/toast_service.dart';

/// 「总结消息」的结果面板：进来就开流，逐字追加。
class ChatSummarySheet extends ConsumerStatefulWidget {
  const ChatSummarySheet({
    super.key,
    required this.channelTitle,
    required this.hours,
    required this.messages,
    required this.truncated,
  });

  final String channelTitle;
  final int hours;
  final List<ChatMessage> messages;

  /// 消息数超上限、只总结了最近一批
  final bool truncated;

  @override
  ConsumerState<ChatSummarySheet> createState() => _ChatSummarySheetState();
}

class _ChatSummarySheetState extends ConsumerState<ChatSummarySheet> {
  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<String>? _sub;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // 面板关掉就断流，别让请求在后台空跑
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    final model = ref.read(defaultTextAiModelProvider);
    if (model == null) {
      setState(() {
        _error = context.l10n.chat_summarizeNoModel;
        _done = true;
      });
      return;
    }

    final service = ChatSummaryService(
      ref.read(aiChatServiceProvider),
      AiProviderListNotifier.getApiKey,
    );

    _sub =
        service
            .summarize(
              provider: model.provider,
              model: model.model,
              channelTitle: widget.channelTitle,
              hours: widget.hours,
              messages: widget.messages,
            )
            .listen(
              (delta) {
                if (!mounted) return;
                setState(() => _buffer.write(delta));
              },
              onError: (Object e) {
                if (!mounted) return;
                setState(() {
                  _error = switch (e) {
                    ChatSummaryException(error: ChatSummaryError.noContent) =>
                      context.l10n.chat_summarizeEmpty,
                    ChatSummaryException(error: ChatSummaryError.noApiKey) =>
                      context.l10n.chat_summarizeNoModel,
                    _ => context.l10n.chat_summarizeFailed,
                  };
                  _done = true;
                });
              },
              onDone: () {
                if (!mounted) return;
                setState(() => _done = true);
              },
            );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _buffer.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.chat_summarizeTruncated(widget.messages.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          )
        else if (text.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          SelectableText(text, style: theme.textTheme.bodyMedium),
        if (_done && _error == null && text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                final copied = context.l10n.chat_summarizeCopied;
                Clipboard.setData(ClipboardData(text: text)).then(
                  (_) => ToastService.showSuccess(copied),
                );
              },
              icon: const Icon(Symbols.content_copy_rounded, size: 18),
              label: Text(context.l10n.chat_summarizeCopy),
            ),
          ),
        ],
      ],
    );
  }
}
