/// 编辑器硬件键盘处理。
///
/// 职责边界(对齐 appflowy keyboard_service_widget 的分层):
/// - **可打印字符不在这里处理** —— 全部走 IME(updateEditingValue);
/// - 本层只管导航/结构键:方向、Backspace/Delete、Enter、Ctrl 组合;
/// - **composing 非空时一律让路**(返回 ignored,平台把按键交给 IME 处理
///   候选窗上下移动/翻页等)。
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/editable_text_content.dart' show MarkKind;
import '../model/editor_state.dart';

/// 处理结果由调用方(FluxdoEditor 的 Focus.onKeyEvent)透传给框架。
///
/// [onMoveVertical]:上下键的垂直光标移动。需要行几何(RenderParagraph),
/// 纯 EditorState 做不了 → 由 FluxdoEditor 注入实现。
///
/// [onClipboardCopy]/[onClipboardCut]/[onClipboardPaste]:剪贴板三键。
/// 剪贴板 IO(Clipboard API)与粘贴的 markdown 导入(cook 链路,异步)
/// 都不属于纯状态层 → 由 FluxdoEditor 注入;未注入时按键不处理(ignored)。
///
/// 退格/删除/回车在**框架侧本地处理**并返回 handled(EditableText +
/// DefaultTextEditingShortcuts 同款,平台不再收到该键)。段落切换时重开
/// 输入连接，框架会按 client ID 丢弃旧连接的迟到消息。
KeyEventResult handleEditorKeyEvent(
  EditorState state,
  KeyEvent event, {
  required void Function() onEdited,
  void Function(int direction, {required bool extend})? onMoveVertical,
  void Function()? onClipboardCopy,
  void Function()? onClipboardCut,
  void Function()? onClipboardPaste,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }

  // IME 预编辑中:候选窗需要方向/回车/退格 —— 用 skipRemainingHandlers
  // 而非 ignored:事件仍交还平台(IME 正常收到),但**不再冒泡**到上层
  // Shortcuts(否则方向键会触发 DirectionalFocusIntent,焦点被遍历走)。
  if (state.hasComposing) {
    return KeyEventResult.skipRemainingHandlers;
  }

  final pressed = HardwareKeyboard.instance;
  final primary = pressed.isControlPressed;
  final shift = pressed.isShiftPressed;

  // 跨段选区 + 可打印字符:IME 窗口只覆盖单段,平台模型里没有这个跨段
  // 选区 —— 直接放行会让平台把字符插进**过期的单段模型**,再经 diff 写进
  // 错误位置。先本地删选区(收敛为单段折叠光标,监听器会同步 setEditingState
  // 刷新平台模型),然后 skipRemainingHandlers 把按键交还平台 IME:
  // 渠道 FIFO 保证平台先应用新模型再处理该键 → 字符插在正确位置。
  final sel = state.selection;
  if (sel != null && !sel.isSingleBlock) {
    final ch = event.character;
    final isPrintable =
        ch != null && ch.isNotEmpty && !primary && ch.codeUnitAt(0) >= 0x20;
    if (isPrintable) {
      state.deleteSelection();
      onEdited();
      return KeyEventResult.skipRemainingHandlers;
    }
  }

  bool handled = true;
  switch (event.logicalKey) {
    case LogicalKeyboardKey.arrowLeft:
      state.moveCaretHorizontal(-1, extend: shift);
    case LogicalKeyboardKey.arrowRight:
      state.moveCaretHorizontal(1, extend: shift);
    case LogicalKeyboardKey.arrowUp:
      onMoveVertical?.call(-1, extend: shift);
    case LogicalKeyboardKey.arrowDown:
      onMoveVertical?.call(1, extend: shift);
    case LogicalKeyboardKey.backspace:
      state.backspace();
      onEdited();
    case LogicalKeyboardKey.delete:
      state.deleteForward();
      onEdited();
    // primary+Enter 不吃:落到底部返回 ignored('\n' < 0x20 不触发
    // skipRemainingHandlers),冒泡给宿主的提交快捷键(Cmd/Ctrl+Enter 发送)。
    case LogicalKeyboardKey.enter when !primary:
    case LogicalKeyboardKey.numpadEnter when !primary:
      state.sealHistory();
      state.splitBlock();
      onEdited();
    case LogicalKeyboardKey.tab:
      // 列表项:缩进/反缩进;普通文本块:插入制表符(Shift+Tab 无操作,
      // 但仍 handled —— 防 Tab 焦点遍历把焦点带走)。
      final sel = state.selection;
      final block = sel == null
          ? null
          : state.textBlockById(sel.extent.blockId);
      if (block != null && block.isListItem) {
        if (shift) {
          state.outdentListItem();
        } else {
          state.indentListItem();
        }
      } else if (!shift) {
        state.insertText('\t');
      }
      onEdited();
    // ---- 格式快捷键(M2) ----
    case LogicalKeyboardKey.keyB when primary:
      state.toggleMark(MarkKind.strong);
      onEdited();
    case LogicalKeyboardKey.keyI when primary:
      state.toggleMark(MarkKind.em);
      onEdited();
    case LogicalKeyboardKey.keyE when primary:
      state.toggleMark(MarkKind.inlineCode);
      onEdited();
    case LogicalKeyboardKey.keyX when primary && shift:
      state.toggleMark(MarkKind.lineThrough);
      onEdited();
    // 块级格式(对齐 Discourse composer toolbar 键位):
    // Cmd/Ctrl+Shift+7/8/9 列表与引用、Cmd/Ctrl+Alt+0..4 段落/标题。
    // 注:键位清单同步维护于宿主 composer_shortcuts.dart(帮助浮层/
    // tooltip 事实源),改动需两处同步。
    case LogicalKeyboardKey.digit7 when primary && shift:
      state.toggleList(ordered: true);
      onEdited();
    case LogicalKeyboardKey.digit8 when primary && shift:
      state.toggleList(ordered: false);
      onEdited();
    case LogicalKeyboardKey.digit9 when primary && shift:
      state.toggleQuote();
      onEdited();
    case LogicalKeyboardKey.digit0 when primary && pressed.isAltPressed:
      state.setHeading(null);
      onEdited();
    case LogicalKeyboardKey.digit1 when primary && pressed.isAltPressed:
      state.setHeading(1);
      onEdited();
    case LogicalKeyboardKey.digit2 when primary && pressed.isAltPressed:
      state.setHeading(2);
      onEdited();
    case LogicalKeyboardKey.digit3 when primary && pressed.isAltPressed:
      state.setHeading(3);
      onEdited();
    case LogicalKeyboardKey.digit4 when primary && pressed.isAltPressed:
      state.setHeading(4);
      onEdited();
    // ---- 剪贴板 ----
    case LogicalKeyboardKey.keyC when primary:
      if (onClipboardCopy == null) {
        handled = false;
      } else {
        onClipboardCopy();
      }
    case LogicalKeyboardKey.keyX when primary:
      if (onClipboardCut == null) {
        handled = false;
      } else {
        onClipboardCut();
      }
    case LogicalKeyboardKey.keyV when primary:
      if (onClipboardPaste == null) {
        handled = false;
      } else {
        onClipboardPaste();
      }
    case LogicalKeyboardKey.keyA when primary:
      state.selectAll();
    case LogicalKeyboardKey.keyZ when primary && shift:
      state.redo();
      onEdited();
    case LogicalKeyboardKey.keyZ when primary:
      state.undo();
      onEdited();
    default:
      handled = false;
  }
  if (handled) return KeyEventResult.handled;

  // 无修饰可打印字符:skipRemainingHandlers —— 事件交还平台走 IME
  // insertText 路径(注:不能 handled,否则嵌入层不再路由给
  // NSTextInputContext,字符进不了输入通道),同时**不冒泡** Flutter
  // 框架内的上层 handler。否则宿主 app 的全局单键快捷键(j/k/d/s
  // 话题导航等,其文本输入豁免只认 EditableText 祖先)会把字母抢走,
  // 表现为"很多字母打不出来"。
  final ch = event.character;
  if (!primary &&
      ch != null &&
      ch.isNotEmpty &&
      ch.codeUnitAt(0) >= 0x20 &&
      ch.codeUnitAt(0) != 0x7f) {
    return KeyEventResult.skipRemainingHandlers;
  }
  return KeyEventResult.ignored;
}
