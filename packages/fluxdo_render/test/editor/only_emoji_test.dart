/// 编辑器大表情判定与行高回归测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/editor.dart';
import 'package:fluxdo_render/fluxdo_render.dart';
import 'package:fluxdo_render/src/editor/widget/editable_paragraph.dart';

EmojiRun _emoji([String name = 'tada']) => EmojiRun(name: name, url: '');

EditableTextContent _content(List<EmojiRun> emojis, {String between = ''}) {
  var content = EditableTextContent.empty;
  for (var i = 0; i < emojis.length; i++) {
    if (i > 0 && between.isNotEmpty) {
      content = content.insert(content.length, between);
    }
    content = content.insertAtom(content.length, emojis[i]);
  }
  return content;
}

List<bool> _flags(EditableTextContent content) => content
    .toInlines(forEditing: true)
    .whereType<EmojiRun>()
    .map((emoji) => emoji.isOnlyEmoji)
    .toList();

void main() {
  group('大表情按软换行逐行判定', () {
    test('每行 1～3 个纯 emoji 放大，4 个不放大', () {
      expect(_flags(_content([_emoji()])), [true]);
      expect(
        _flags(_content([_emoji('a'), _emoji('b'), _emoji('c')], between: ' ')),
        [true, true, true],
      );
      expect(
        _flags(_content([
          _emoji('a'),
          _emoji('b'),
          _emoji('c'),
          _emoji('d'),
        ])),
        [false, false, false, false],
      );
    });

    test('回车和下一行文字不会让上一行表情缩回去', () {
      var content = _content([_emoji()]);
      content = content.insert(content.length, '\n下一行');
      expect(_flags(content), [true]);
      expect(content.hasOnlyEmojiLine, isTrue);
    });

    test('各行独立：纯表情行放大，混排行保持普通尺寸', () {
      var content = _content([_emoji('first')]);
      content = content.insert(content.length, '\n');
      content = content.insertAtom(content.length, _emoji('second'));
      content = content.insert(content.length, ' text');
      expect(_flags(content), [true, false]);
    });

    test('原有 only-emoji 在同行加入文字后会恢复普通尺寸', () {
      var content = EditableTextContent.fromInlines([
        const EmojiRun(name: 'tada', url: '', isOnlyEmoji: true),
      ]);
      content = content.insert(content.length, ' text');
      expect(_flags(content), [false]);
      expect(content.hasOnlyEmojiLine, isFalse);
    });

    test('空段、纯文字和其他原子不算大表情行', () {
      expect(EditableTextContent.empty.hasOnlyEmojiLine, isFalse);
      expect(EditableTextContent(text: 'text').hasOnlyEmojiLine, isFalse);
      final mention = EditableTextContent.empty.insertAtom(
        0,
        const MentionRun(username: 'sam', href: '/u/sam'),
      );
      expect(mention.hasOnlyEmojiLine, isFalse);
    });
  });

  testWidgets('编辑段落为大表情放开固定行高钳制', (tester) async {
    final sizes = <double>[];
    final factory = NodeFactory(
      emojiImageBuilder: (context, emoji, size) {
        sizes.add(size);
        return SizedBox.square(dimension: size);
      },
    );
    final state = EditorState(
      blocks: [
        TextBlock(id: 'e_0', content: _content([_emoji()])),
      ],
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FluxdoEditor(
            state: state,
            nodeFactory: factory,
            baseTextStyle: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(sizes, contains(32.0));
    final height = tester.getSize(find.byType(EditableParagraph)).height;
    expect(
      height,
      greaterThanOrEqualTo(48),
      reason: '32dp 表情加上下各 0.5em 外边距，不应被 25.6px strut 压扁',
    );
  });
}
