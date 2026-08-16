import 'package:flutter/services.dart';

/// 将 [text] 插入聊天输入框当前选区，并把光标移动到插入内容末尾。
///
/// [selection] 用于保留弹出菜单或 BottomSheet 前的光标位置；无效或越界时
/// 自动退化为文本末尾，避免第三方输入法留下的旧选区导致 RangeError。
TextEditingValue insertChatComposerText(
  TextEditingValue value,
  String text, {
  TextSelection? selection,
}) {
  final current = value.text;
  final effectiveSelection = selection ?? value.selection;
  final hasValidSelection =
      effectiveSelection.isValid &&
      effectiveSelection.start <= current.length &&
      effectiveSelection.end <= current.length;
  final start = hasValidSelection ? effectiveSelection.start : current.length;
  final end = hasValidSelection ? effectiveSelection.end : current.length;
  final updated = current.replaceRange(start, end, text);

  return TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}
