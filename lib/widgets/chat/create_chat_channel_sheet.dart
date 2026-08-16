import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/chat/chat_channel.dart';
import '../../models/emoji.dart';
import '../../providers/category_provider.dart';
import '../../providers/core_providers.dart';
import '../common/overlay/app_bottom_sheet.dart';
import '../markdown_editor/emoji_picker.dart';

Future<ChatChannel?> showCreateChatChannelSheet(BuildContext context) {
  final formKey = GlobalKey<_CreateChatChannelFormState>();
  return AppBottomSheet.show<ChatChannel>(
    context: context,
    style: AppSheetStyle.card,
    title: context.l10n.chat_newChannel,
    showTitleDivider: true,
    maxHeightFactor: 0.94,
    contentPadding: EdgeInsets.zero,
    footer: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: () => formKey.currentState?.submit(),
          child: Text(context.l10n.chat_createChannel),
        ),
      ),
    ),
    builder: (_) => _CreateChatChannelForm(key: formKey),
  );
}

class _CreateChatChannelForm extends ConsumerStatefulWidget {
  const _CreateChatChannelForm({super.key});

  @override
  ConsumerState<_CreateChatChannelForm> createState() =>
      _CreateChatChannelFormState();
}

class _CreateChatChannelFormState
    extends ConsumerState<_CreateChatChannelForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();

  int? _categoryId;
  Emoji? _emoji;
  bool _autoJoinUsers = false;
  bool _threadingEnabled = false;
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickEmoji() async {
    final selected = await AppBottomSheet.show<Emoji>(
      context: context,
      title: context.l10n.chat_channelEmoji,
      contentPadding: EdgeInsets.zero,
      showTitleDivider: true,
      maxHeightFactor: 0.82,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.68,
        child: EmojiPicker(
          bottomPadding: 16,
          onEmojiSelected: (emoji) => Navigator.of(sheetContext).pop(emoji),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _emoji = selected);
  }

  Future<void> submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final channel = await ref
          .read(discourseServiceProvider)
          .createCategoryChatChannel(
            categoryId: _categoryId!,
            name: _nameController.text,
            slug: _slugController.text,
            description: _descriptionController.text,
            emoji: _emoji?.name,
            autoJoinUsers: _autoJoinUsers,
            threadingEnabled: _threadingEnabled,
          );
      if (mounted) Navigator.of(context).pop(channel);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = context.l10n.chat_createChannelFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FieldLabel(context.l10n.chat_channelName, required: true),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? context.l10n.chat_channelNameRequired
                  : null,
            ),
            const SizedBox(height: 24),
            _FieldLabel(context.l10n.chat_channelSlug),
            const SizedBox(height: 8),
            TextFormField(
              controller: _slugController,
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            const SizedBox(height: 24),
            _FieldLabel(context.l10n.chat_channelDescription),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 24),
            _FieldLabel(context.l10n.chat_selectCategory, required: true),
            const SizedBox(height: 8),
            categoriesAsync.when(
              data: (categories) {
                final writable = categories
                    .where((category) => category.canCreateTopic)
                    .toList();
                final options = writable.isEmpty ? categories : writable;
                return DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  hint: Text(context.l10n.chat_selectCategoryHint),
                  validator: (value) =>
                      value == null ? context.l10n.chat_categoryRequired : null,
                  items: [
                    for (final category in options) _categoryItem(category),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _categoryId = value),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => OutlinedButton.icon(
                onPressed: () => ref.invalidate(categoriesProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.common_retry),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chat_categoryPermissionsHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _FieldLabel(context.l10n.chat_channelEmoji),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickEmoji,
                  icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
                  label: Text(
                    _emoji == null
                        ? context.l10n.chat_chooseEmoji
                        : ':${_emoji!.name}:',
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _emoji == null || _submitting
                      ? null
                      : () => setState(() => _emoji = null),
                  child: Text(context.l10n.chat_resetEmoji),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingCheckbox(
              value: _autoJoinUsers,
              enabled: !_submitting,
              title: context.l10n.chat_autoJoinUsers,
              description: context.l10n.chat_autoJoinUsersDescription,
              onChanged: (value) => setState(() => _autoJoinUsers = value),
            ),
            const SizedBox(height: 18),
            _SettingCheckbox(
              value: _threadingEnabled,
              enabled: !_submitting,
              title: context.l10n.chat_enableThreads,
              description: context.l10n.chat_enableThreadsDescription,
              onChanged: (value) => setState(() => _threadingEnabled = value),
            ),
            if (_submitting) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
            ],
            if (_submitError != null) ...[
              const SizedBox(height: 16),
              Text(
                _submitError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  DropdownMenuItem<int> _categoryItem(Category category) {
    return DropdownMenuItem<int>(
      value: category.id,
      child: Row(
        children: [
          if (category.readRestricted) ...[
            const Icon(Icons.lock_outline_rounded, size: 17),
            const SizedBox(width: 7),
          ],
          Expanded(child: Text(category.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        children: required
            ? [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ]
            : null,
      ),
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _SettingCheckbox extends StatelessWidget {
  const _SettingCheckbox({
    required this.value,
    required this.enabled,
    required this.title,
    required this.description,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (next) => onChanged(next ?? false) : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
