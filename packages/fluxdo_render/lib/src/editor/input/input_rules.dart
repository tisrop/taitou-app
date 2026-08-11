/// Markdown 快捷语法(input rules)—— 类 Notion 输入体验的核心。
///
/// 对齐官方 ProseMirror composer 的 buildInputRules(core/inputrules.js):
/// - **块级**(行首标记 + 空格触发):`# `→标题、`- `/`* `→无序列表、
///   `1. `→有序列表、`> `→引用层;
/// - **行内**(收尾定界符触发):`**x**`→粗体、`*x*`→斜体、`` `x` ``→
///   行内代码、`~~x~~`→删除线;
/// - **hr**(`---` + 空格):由 [InputRuleOutcome.hrRequest] 上抛,视图层
///   经 cook 链路插分隔线岛(状态层不造岛)。
///
/// 触发时机:IME 文本落地后、无 composing 时(EditorImeClient 调用)。
/// 中文 composing 期间绝不触发 —— 预编辑文本是临时的。
///
/// 撤销语义(官方 undoable 同款):规则应用前 seal —— undo 一步回到
/// 字面文本(`**粗**` 原样),再 undo 才删字符。
///
/// 排除:光标处于 inlineCode mark 内时行内规则不触发(代码里写 `*` 是
/// 字面量);块级规则对 heading/listItem 块不触发(已是结构块)。
library;

import '../model/editable_text_content.dart';
import '../model/editor_state.dart';

/// 规则应用结果。
enum InputRuleOutcome {
  /// 无规则命中。
  none,

  /// 已应用(文档已变,调用方需 reconcile IME)。
  applied,

  /// `---` 命中:请求视图层插入分隔线(状态层不产岛节点)。
  /// 触发行文本已清空。
  hrRequest,
}

/// 对 [blockId] 块在光标处尝试应用 input rules。
///
/// [typedChar]:本次输入落地的最后一个字符(触发器判定用;IME 批量
/// 上屏时为末字符)。只有 ' '(块级触发)与定界符尾字符(行内触发)
/// 才可能命中,其余字符 O(1) 直接返回。
InputRuleOutcome tryApplyInputRules(
  EditorState state,
  String blockId, {
  required String typedChar,
}) {
  if (state.hasComposing) return InputRuleOutcome.none;
  final sel = state.selection;
  if (sel == null || !sel.isCollapsed || sel.extent.blockId != blockId) {
    return InputRuleOutcome.none;
  }
  final block = state.textBlockById(blockId);
  if (block == null) return InputRuleOutcome.none;

  if (typedChar == ' ') {
    return _tryBlockRules(state, block, sel.extent.offset);
  }
  if (typedChar == '*' ||
      typedChar == '`' ||
      typedChar == '~' ||
      typedChar == '_') {
    return _tryInlineRules(state, block, sel.extent.offset);
  }
  if (typedChar == ']') {
    final completed = _tryBbcodeAttrRules(state, block, sel.extent.offset);
    if (completed != InputRuleOutcome.none) return completed;
    final opened = _tryBbcodeOpenRules(state, block, sel.extent.offset);
    if (opened != InputRuleOutcome.none) return opened;
  }
  return _tryBbcodeInsidePairRules(state, block, sel.extent.offset);
}

// ---------------------------------------------------------------------
// 块级规则(行首标记 + 空格)
// ---------------------------------------------------------------------

final _headingRe = RegExp(r'^(#{1,6}) $');
final _bulletRe = RegExp(r'^[-*] $');
final _orderedRe = RegExp(r'^(\d{1,9})[.)] $');
final _quoteRe = RegExp(r'^> $');
final _hrRe = RegExp(r'^(---|\*\*\*|___) $');

InputRuleOutcome _tryBlockRules(EditorState state, TextBlock block, int caret) {
  // 块级标记必须在**行首起敲**:光标前的全部文本就是标记本身。
  // (含 '\n' 软换行的段落里,只认真正的块首 —— 对齐官方
  // textblockTypeInputRule 的 ^ 锚定。)
  final before = block.content.text.substring(0, caret);
  if (before.contains('\n')) return InputRuleOutcome.none;
  // 标记区不能有原子(emoji 后打 "# " 不是标题意图)
  for (var i = 0; i < caret; i++) {
    if (block.content.isAtomAt(i)) return InputRuleOutcome.none;
  }

  // hr:任何块类型都可触发(空段打 --- )
  final hr = _hrRe.firstMatch(before);
  if (hr != null && block.isParagraph) {
    state.sealHistory();
    state.applyBlockInputRule(
      block.id,
      markerLength: caret,
      transform: (b) => b, // 类型不变,仅清标记;岛由视图层插
    );
    return InputRuleOutcome.hrRequest;
  }

  // 已是结构块(heading/listItem)不再转换;引用层可继续叠标记
  final heading = _headingRe.firstMatch(before);
  if (heading != null && !block.isHeading && !block.isListItem) {
    final level = heading.group(1)!.length;
    state.sealHistory();
    state.applyBlockInputRule(
      block.id,
      markerLength: caret,
      transform: (b) => b.asHeading(level),
    );
    return InputRuleOutcome.applied;
  }

  if (_bulletRe.hasMatch(before) && !block.isListItem && !block.isHeading) {
    state.sealHistory();
    state.applyBlockInputRule(
      block.id,
      markerLength: caret,
      transform: (b) => b.asListItem(ordered: false),
    );
    return InputRuleOutcome.applied;
  }

  final ordered = _orderedRe.firstMatch(before);
  if (ordered != null && !block.isListItem && !block.isHeading) {
    final start = int.tryParse(ordered.group(1)!) ?? 1;
    state.sealHistory();
    state.applyBlockInputRule(
      block.id,
      markerLength: caret,
      transform: (b) => b.asListItem(ordered: true, listStart: start),
    );
    return InputRuleOutcome.applied;
  }

  if (_quoteRe.hasMatch(before) && block.isParagraph) {
    state.sealHistory();
    state.applyBlockInputRule(
      block.id,
      markerLength: caret,
      transform: (b) => b.copyWith(
        containers: [
          QuoteFrame(groupId: nextFrameGroupId()),
          ...b.containers,
        ],
      ),
    );
    return InputRuleOutcome.applied;
  }

  return InputRuleOutcome.none;
}

// ---------------------------------------------------------------------
// 行内规则(收尾定界符)
// ---------------------------------------------------------------------

/// (正则, mark, 定界符长度)。按特异性排序:长定界符优先(`**` 先于 `*`)。
/// 内容组不允许含定界字符本身(官方 [^*]+ 同款),且首尾非空格
/// (`** x**` 不触发 —— CommonMark 语义)。
final List<(RegExp, MarkKind, int)> _inlineRules = [
  (RegExp(r'\*\*([^*\s](?:[^*]*[^*\s])?)\*\*$'), MarkKind.strong, 2),
  (RegExp(r'__([^_\s](?:[^_]*[^_\s])?)__$'), MarkKind.strong, 2),
  (RegExp(r'~~([^~\s](?:[^~]*[^~\s])?)~~$'), MarkKind.lineThrough, 2),
  (RegExp(r'`([^`]+)`$'), MarkKind.inlineCode, 1),
  // 单 * 斜体:前面不能还是 *(否则和 ** 混淆)
  (RegExp(r'(?<!\*)\*([^*\s](?:[^*]*[^*\s])?)\*$'), MarkKind.em, 1),
  (RegExp(r'(?<!_)_([^_\s](?:[^_]*[^_\s])?)_$'), MarkKind.em, 1),
];

InputRuleOutcome _tryInlineRules(
  EditorState state,
  TextBlock block,
  int caret,
) {
  final before = block.content.text.substring(0, caret);
  // 光标处于 inlineCode mark 内:字面量区,不触发
  if (block.content.marksAt(caret).contains(MarkKind.inlineCode)) {
    return InputRuleOutcome.none;
  }

  for (final (re, kind, delimLen) in _inlineRules) {
    final m = re.firstMatch(before);
    if (m == null) continue;
    final contentText = m.group(1)!;
    final matchStart =
        m.start + (m.group(0)!.length - (contentText.length + delimLen * 2));
    // 区间内含原子:FFFC 参与正则会当普通字符 —— 允许(emoji 可加粗),
    // 但含 '\n' 不允许(跨软换行不成对)。
    if (contentText.contains('\n')) continue;

    state.sealHistory();
    state.applyInlineInputRule(
      block.id,
      matchStart: matchStart,
      delimLength: delimLen,
      contentLength: contentText.length,
      kind: kind,
    );
    return InputRuleOutcome.applied;
  }
  return InputRuleOutcome.none;
}

// ---------------------------------------------------------------------
// BBCode 属性标记(color/bgcolor/size)
// ---------------------------------------------------------------------

final List<(RegExp, MarkKind, String)> _bbcodeAttrRules = [
  (
    RegExp(r'\[size=(\d{1,4})\]([^\[\s](?:[^\[]*[^\[\s])?)\[/size\]$'),
    MarkKind.size,
    '[/size]',
  ),
  (
    RegExp(r'\[color=([^\]\s]{1,64})\]([^\[\s](?:[^\[]*[^\[\s])?)\[/color\]$'),
    MarkKind.textColor,
    '[/color]',
  ),
  (
    RegExp(
      r'\[bgcolor=([^\]\s]{1,64})\]([^\[\s](?:[^\[]*[^\[\s])?)\[/bgcolor\]$',
    ),
    MarkKind.bgColor,
    '[/bgcolor]',
  ),
];

final List<(RegExp, MarkKind, String)> _bbcodeOpenRules = [
  (RegExp(r'\[size=(\d{1,4})\]$'), MarkKind.size, '[/size]'),
  (RegExp(r'\[color=([^\]\s]{1,64})\]$'), MarkKind.textColor, '[/color]'),
  (RegExp(r'\[bgcolor=([^\]\s]{1,64})\]$'), MarkKind.bgColor, '[/bgcolor]'),
];

final List<(RegExp, MarkKind, String)> _bbcodeOpenPatterns = [
  (RegExp(r'\[size=(\d{1,4})\]'), MarkKind.size, '[/size]'),
  (RegExp(r'\[color=([^\]\s]{1,64})\]'), MarkKind.textColor, '[/color]'),
  (RegExp(r'\[bgcolor=([^\]\s]{1,64})\]'), MarkKind.bgColor, '[/bgcolor]'),
];

InputRuleOutcome _tryBbcodeAttrRules(
  EditorState state,
  TextBlock block,
  int caret,
) {
  final before = block.content.text.substring(0, caret);
  if (block.content.marksAt(caret).contains(MarkKind.inlineCode)) {
    return InputRuleOutcome.none;
  }
  for (final (pattern, kind, closeTag) in _bbcodeAttrRules) {
    final match = pattern.firstMatch(before);
    if (match == null) continue;
    final attr = match.group(1)!;
    final contentText = match.group(2)!;
    if (contentText.contains('\n')) continue;
    final openLength =
        match.group(0)!.length - contentText.length - closeTag.length;
    state.sealHistory();
    state.applyInlineInputRule(
      block.id,
      matchStart: match.start,
      delimLength: closeTag.length,
      openLength: openLength,
      contentLength: contentText.length,
      kind: kind,
      attr: attr,
    );
    return InputRuleOutcome.applied;
  }
  return InputRuleOutcome.none;
}

InputRuleOutcome _tryBbcodeOpenRules(
  EditorState state,
  TextBlock block,
  int caret,
) {
  final text = block.content.text;
  if (caret <= 0 || caret >= text.length) return InputRuleOutcome.none;
  if (block.content.marksAt(caret).contains(MarkKind.inlineCode)) {
    return InputRuleOutcome.none;
  }
  final before = text.substring(0, caret);
  for (final (pattern, kind, closeTag) in _bbcodeOpenRules) {
    final match = pattern.firstMatch(before);
    if (match == null) continue;
    final rest = text.substring(caret);
    final line = rest.split('\n').first;
    final closeAt = line.indexOf(closeTag);
    if (closeAt <= 0) continue;
    final contentText = line.substring(0, closeAt);
    if (contentText.contains('[') ||
        contentText.startsWith(' ') ||
        contentText.endsWith(' ')) {
      continue;
    }
    state.sealHistory();
    state.applyInlineInputRule(
      block.id,
      matchStart: match.start,
      delimLength: closeTag.length,
      openLength: match.group(0)!.length,
      contentLength: contentText.length,
      kind: kind,
      attr: match.group(1),
      caretAtEnd: false,
    );
    return InputRuleOutcome.applied;
  }
  return InputRuleOutcome.none;
}

InputRuleOutcome _tryBbcodeInsidePairRules(
  EditorState state,
  TextBlock block,
  int caret,
) {
  final text = block.content.text;
  if (caret <= 0 || caret >= text.length) return InputRuleOutcome.none;
  if (block.content.marksAt(caret).contains(MarkKind.inlineCode)) {
    return InputRuleOutcome.none;
  }
  final before = text.substring(0, caret);
  for (final (pattern, kind, closeTag) in _bbcodeOpenPatterns) {
    if (!text.startsWith(closeTag, caret)) continue;
    RegExpMatch? lastOpen;
    for (final match in pattern.allMatches(before)) {
      lastOpen = match;
    }
    if (lastOpen == null) continue;
    final contentText = before.substring(lastOpen.end);
    if (contentText.isEmpty ||
        contentText.contains('\n') ||
        contentText.contains('[') ||
        contentText.startsWith(' ') ||
        contentText.endsWith(' ')) {
      continue;
    }
    state.sealHistory();
    state.applyInlineInputRule(
      block.id,
      matchStart: lastOpen.start,
      delimLength: closeTag.length,
      openLength: lastOpen.group(0)!.length,
      contentLength: contentText.length,
      kind: kind,
      attr: lastOpen.group(1),
    );
    return InputRuleOutcome.applied;
  }
  return InputRuleOutcome.none;
}
