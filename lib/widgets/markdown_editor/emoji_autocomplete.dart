import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/s.dart';
import '../../../models/emoji.dart';
import '../../../services/discourse_cache_manager.dart';
import '../../../services/emoji_handler.dart';

/// Emoji shortcode 搜索数据源。
///
/// [term] 是用户在两个冒号之间输入的关键词，不包含冒号本身。
typedef EmojiAutocompleteDataSource = Future<List<Emoji>> Function(String term);

/// 在 emoji 列表中按 shortcode 名称和搜索别名做前缀匹配。
///
/// 名称前缀优先于别名前缀，同一优先级按 shortcode 排序；相同名称只
/// 返回一次，避免站点把同一 emoji 放进多个分组时出现重复候选。
List<Emoji> filterEmojiAutocompleteResults(
  Iterable<Emoji> emojis,
  String term, {
  int limit = 24,
}) {
  final query = term.trim().toLowerCase();
  if (query.isEmpty || limit <= 0) return const [];

  final seen = <String>{};
  final matches = <Emoji>[];
  for (final emoji in emojis) {
    final name = emoji.name.toLowerCase();
    final nameStartsWith = name.startsWith(query);
    final aliasStartsWith = emoji.searchAliases.any(
      (alias) => alias.toLowerCase().startsWith(query),
    );
    if ((nameStartsWith || aliasStartsWith) && seen.add(name)) {
      matches.add(emoji);
    }
  }

  matches.sort((a, b) {
    final aStarts = a.name.toLowerCase().startsWith(query);
    final bStarts = b.name.toLowerCase().startsWith(query);
    if (aStarts != bStarts) return aStarts ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return matches.take(limit).toList(growable: false);
}

/// 监听输入中的 `:keyword`，提供 emoji shortcode 自动补全。
///
/// 组件只负责触发词识别、浮层和文本替换，emoji 数据由 [dataSource]
/// 注入，避免编辑器与 API/缓存实现耦合。
class EmojiAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final EmojiAutocompleteDataSource dataSource;
  final Widget child;

  /// 防抖延迟（毫秒）。
  final int debounceMs;

  /// 浮层最多显示的结果数量。
  final int maxResults;

  const EmojiAutocomplete({
    super.key,
    required this.controller,
    required this.dataSource,
    required this.child,
    this.focusNode,
    this.debounceMs = 120,
    this.maxResults = 8,
  });

  @override
  State<EmojiAutocomplete> createState() => _EmojiAutocompleteState();
}

class _EmojiAutocompleteState extends State<EmojiAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  late final FocusNode _keyboardFocusNode;

  OverlayEntry? _overlayEntry;
  Timer? _debounceTimer;
  int _requestGeneration = 0;

  List<Emoji> _results = const [];
  bool _isLoading = false;
  int _selectedIndex = 0;
  int? _shortcodeStartIndex;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(skipTraversal: true);
    widget.controller.addListener(_onTextChanged);
    widget.focusNode?.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    _debounceTimer?.cancel();
    _keyboardFocusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode?.hasFocus != true) {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (_overlayEntry != null && _shortcodeStartIndex != null) {
      if (!selection.isValid ||
          !selection.isCollapsed ||
          selection.baseOffset < _shortcodeStartIndex! ||
          selection.baseOffset > text.length) {
        _removeOverlay();
        return;
      }
    }

    // TextEditingController 在设置相同文本但移动光标时仍会通知监听器。
    // 只有文本变化才需要重新计算关键词和发起搜索。
    if (text == _lastText) return;
    _lastText = text;

    if (!selection.isValid || !selection.isCollapsed) {
      _removeOverlay();
      return;
    }

    final cursor = selection.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      _removeOverlay();
      return;
    }

    final match = _emojiTriggerPattern.firstMatch(text.substring(0, cursor));
    if (match == null) {
      _removeOverlay();
      return;
    }

    final boundary = match.group(1) ?? '';
    final shortcodeStart = match.start + boundary.length;
    final term = (match.group(2) ?? '').toLowerCase();

    // 空的 `:` 不弹出候选，避免用户输入普通冒号时遮挡编辑器；
    // 至少输入一个字符后再开始补全。
    if (term.isEmpty) {
      _removeOverlay();
      return;
    }

    _shortcodeStartIndex = shortcodeStart;
    _debounceTimer?.cancel();
    final generation = ++_requestGeneration;
    _debounceTimer = Timer(Duration(milliseconds: widget.debounceMs), () {
      if (mounted) _performSearch(term, generation);
    });
  }

  Future<void> _performSearch(String term, int generation) async {
    if (!mounted || generation != _requestGeneration) return;

    setState(() {
      _isLoading = true;
      _selectedIndex = 0;
    });
    _showOverlay();

    try {
      final results = await widget.dataSource(term);
      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _results = results.take(widget.maxResults).toList(growable: false);
        _isLoading = false;
        _selectedIndex = 0;
      });
      _updateOverlay();
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _results = const [];
        _isLoading = false;
      });
      _updateOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_overlayEntry!);
  }

  void _updateOverlay() => _overlayEntry?.markNeedsBuild();

  void _removeOverlay() {
    _debounceTimer?.cancel();
    _requestGeneration++;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _results = const [];
    _isLoading = false;
    _selectedIndex = 0;
    _shortcodeStartIndex = null;
  }

  void _selectEmoji(Emoji emoji) {
    final start = _shortcodeStartIndex;
    if (start == null) return;

    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;

    final cursor = selection.baseOffset.clamp(start, text.length);
    final replacement = ':${emoji.name}:';
    final newText = text.replaceRange(start, cursor, replacement);
    final newCursor = start + replacement.length;

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
      composing: TextRange.empty,
    );
    _removeOverlay();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_overlayEntry == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();
      return KeyEventResult.handled;
    }
    if (_results.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _results.length;
      });
      _updateOverlay();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _results.length) % _results.length;
      });
      _updateOverlay();
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _selectEmoji(_results[_selectedIndex]);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final theme = Theme.of(overlayContext);
    final targetContext = _targetKey.currentContext;
    final targetBox = targetContext?.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached || !targetBox.hasSize) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(overlayContext);
    final targetPosition = targetBox.localToGlobal(Offset.zero);
    final targetSize = targetBox.size;
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final padding = mediaQuery.padding;

    final selection = widget.controller.selection;
    var cursorTop = 0.0;
    var cursorBottom = 24.0;
    if (selection.isValid) {
      final textStyle =
          theme.textTheme.bodyLarge?.copyWith(fontSize: 16) ??
          const TextStyle(fontSize: 16);
      final painter = TextPainter(
        text: TextSpan(text: widget.controller.text, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: math.max(1, targetSize.width - 24));
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: selection.baseOffset),
        Rect.zero,
      );
      cursorTop = caret.dy + 12;
      cursorBottom = cursorTop + painter.preferredLineHeight;
    }

    cursorTop = cursorTop.clamp(0.0, targetSize.height);
    cursorBottom = cursorBottom.clamp(cursorTop, targetSize.height);

    const desiredHeight = 248.0;
    final globalTop = targetPosition.dy + cursorTop;
    final globalBottom = targetPosition.dy + cursorBottom;
    final spaceAbove = globalTop - padding.top - kToolbarHeight;
    final spaceBelow =
        screenHeight - keyboardHeight - padding.bottom - globalBottom;
    final showAbove = spaceAbove >= desiredHeight && spaceAbove >= spaceBelow;
    final availableHeight = math.max(96.0, showAbove ? spaceAbove : spaceBelow);
    final menuHeight = math.min(desiredHeight, availableHeight);
    final menuWidth = math.min(
      screenWidth - 16,
      math.max(240.0, math.min(320.0, targetSize.width)),
    );

    return Positioned(
      width: menuWidth,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, showAbove ? cursorTop - 4 : cursorBottom + 4),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(height: menuHeight, child: _buildContent(theme)),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return Column(
      children: [
        if (_isLoading)
          LinearProgressIndicator(
            minHeight: 2,
            color: theme.colorScheme.primary,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _isLoading
                        ? S.current.emoji_searchHint
                        : S.current.emoji_searchNotFound,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final emoji = _results[index];
                    return _EmojiAutocompleteTile(
                      emoji: emoji,
                      selected: index == _selectedIndex,
                      onTap: () => _selectEmoji(emoji),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: KeyedSubtree(key: _targetKey, child: widget.child),
      ),
    );
  }
}

/// Emoji 补全项，显示图片和最终会插入的 shortcode。
class _EmojiAutocompleteTile extends StatelessWidget {
  final Emoji emoji;
  final bool selected;
  final VoidCallback onTap;

  const _EmojiAutocompleteTile({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = emoji.url.isNotEmpty
        ? emoji.url
        : EmojiHandler().getEmojiUrl(emoji.name);

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Image(
                image: emojiImageProvider(url),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Text(
                  ':${emoji.name}:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ':${emoji.name}:',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (selected)
              Icon(
                Icons.keyboard_return_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

final _emojiTriggerPattern = RegExp(
  r'(^|[\s\(\[\{<>"`*_~]):([A-Za-z0-9_+\-]*)$',
);
