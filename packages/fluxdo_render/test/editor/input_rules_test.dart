/// input rules(markdown 快捷语法)测试:块级/行内规则矩阵、触发排除、
/// undo 语义(一步回字面文本)。
library;

import 'dart:ui' show TextRange;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/input/input_rules.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';
import 'package:fluxdo_render/src/editor/model/editor_state.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';

/// 模拟打字:插入文本后触发规则(typedChar = 末字符)。
InputRuleOutcome type(EditorState s, String text) {
  s.insertText(text);
  final blockId = s.selection!.extent.blockId;
  return tryApplyInputRules(s, blockId,
      typedChar: text[text.length - 1]);
}

EditorState empty() {
  final s = EditorState.fromTexts(['']);
  addTearDown(s.dispose);
  s.updateSelection(EditorSelection.collapsed(
      EditorPosition(blockId: s.blocks.first.id, offset: 0)));
  return s;
}

TextBlock first(EditorState s) => s.blocks.first as TextBlock;

void main() {
  group('块级规则', () {
    test('# 空格 → H1;###### → H6;7 个 # 不触发', () {
      var s = empty();
      expect(type(s, '# '), InputRuleOutcome.applied);
      expect(first(s).isHeading, isTrue);
      expect(first(s).headingLevel, 1);
      expect(first(s).content.text, '', reason: '标记已删');
      expect(s.selection!.extent.offset, 0);

      s = empty();
      expect(type(s, '###### '), InputRuleOutcome.applied);
      expect(first(s).headingLevel, 6);

      s = empty();
      expect(type(s, '####### '), InputRuleOutcome.none);
      expect(first(s).isHeading, isFalse);
    });

    test('- / * / 1. / 7) → 列表;> → 引用层', () {
      var s = empty();
      expect(type(s, '- '), InputRuleOutcome.applied);
      expect(first(s).isListItem, isTrue);
      expect(first(s).ordered, isFalse);

      s = empty();
      expect(type(s, '* '), InputRuleOutcome.applied);
      expect(first(s).isListItem, isTrue);

      s = empty();
      expect(type(s, '1. '), InputRuleOutcome.applied);
      expect(first(s).ordered, isTrue);
      expect(first(s).listStart, 1);

      s = empty();
      expect(type(s, '7) '), InputRuleOutcome.applied);
      expect(first(s).listStart, 7);

      s = empty();
      expect(type(s, '> '), InputRuleOutcome.applied);
      expect(first(s).containers.single, isA<QuoteFrame>());
      // 再叠一层
      expect(type(s, '> '), InputRuleOutcome.applied);
      expect(first(s).containers.length, 2);
    });

    test('--- 空格 → hrRequest 且标记清空', () {
      final s = empty();
      expect(type(s, '--- '), InputRuleOutcome.hrRequest);
      expect(first(s).content.text, '');
    });

    test('排除:行中打标记不触发;heading 内不再转换;标记区含原子不触发', () {
      var s = empty();
      s.insertText('文字');
      expect(type(s, '# '), InputRuleOutcome.none, reason: '非行首');

      s = empty();
      type(s, '# ');
      s.insertText('标题');
      expect(type(s, '- '), InputRuleOutcome.none, reason: 'heading 内');

      s = empty();
      s.insertAtom(const EmojiRun(name: 'smile', url: 'u'));
      expect(type(s, '# '), InputRuleOutcome.none, reason: '原子在标记区');
    });

    test('undo 语义:一步回字面文本', () {
      final s = empty();
      type(s, '# ');
      expect(first(s).isHeading, isTrue);
      s.undo();
      expect(first(s).isHeading, isFalse);
      expect(first(s).content.text, '# ', reason: 'undo 回到字面标记');
    });
  });

  group('行内规则', () {
    test('**x** → strong;*x* → em;`x` → code;~~x~~ → del', () {
      var s = empty();
      expect(type(s, '前**粗体**'), InputRuleOutcome.applied);
      var b = first(s);
      expect(b.content.text, '前粗体');
      expect(b.content.marks.single,
          const MarkSpan(start: 1, end: 3, kind: MarkKind.strong));
      expect(s.selection!.extent.offset, 3, reason: '光标落内容尾');

      s = empty();
      expect(type(s, '*斜*'), InputRuleOutcome.applied);
      expect(first(s).content.marks.single.kind, MarkKind.em);

      s = empty();
      expect(type(s, '`code`'), InputRuleOutcome.applied);
      b = first(s);
      expect(b.content.text, 'code');
      expect(b.content.marks.single.kind, MarkKind.inlineCode);

      s = empty();
      expect(type(s, '~~删~~'), InputRuleOutcome.applied);
      expect(first(s).content.marks.single.kind, MarkKind.lineThrough);
    });

    test('排除:** 空内容/带空格边缘不触发;code mark 内不触发', () {
      var s = empty();
      expect(type(s, '****'), InputRuleOutcome.none);

      s = empty();
      expect(type(s, '** x**'), InputRuleOutcome.none, reason: '首空格');

      // 光标在 inlineCode mark 内部:字面量区,不触发。
      // (code 边界之后打 *x* 该触发 —— 新字符不在 code 里。)
      final s2 = EditorState(blocks: [
        TextBlock(
          id: 'e_0',
          content: EditableTextContent(text: 'a*x*', marks: const [
            MarkSpan(start: 0, end: 4, kind: MarkKind.inlineCode),
          ]),
        ),
      ]);
      addTearDown(s2.dispose);
      s2.updateSelection(const EditorSelection.collapsed(
          EditorPosition(blockId: 'e_0', offset: 4)));
      expect(
        tryApplyInputRules(s2, 'e_0', typedChar: '*'),
        InputRuleOutcome.none,
      );
    });

    test('undo 语义:一步回字面定界符', () {
      final s = empty();
      type(s, '**粗**');
      expect(first(s).content.text, '粗');
      s.undo();
      expect(first(s).content.text, '**粗**');
      expect(first(s).content.marks, isEmpty);
    });

    test('composing 中不触发', () {
      final s = empty();
      s.insertText('**x**');
      s.updateComposing(const TextRange(start: 0, end: 5));
      expect(
        tryApplyInputRules(s, s.blocks.first.id, typedChar: '*'),
        InputRuleOutcome.none,
      );
    });
  });
}
