import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/doc_converter.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';
import 'package:fluxdo_render/src/editor/model/editor_block.dart';
import 'package:fluxdo_render/src/editor/model/markdown_serializer.dart';
import 'package:fluxdo_render/src/node/inline_node.dart';

void main() {
  const hashtag = LinkRun(
    href: '/c/dev/4',
    hashtagRef: 'dev',
    hashtagIcon: 'folder',
    children: [TextRun('开发调优')],
  );

  test('hashtag 作为行内原子进入编辑白名单', () {
    expect(isEditableInline(hashtag), isTrue);

    final content = EditableTextContent.fromInlines(const [
      TextRun('看看 '),
      hashtag,
      TextRun(' 板块'),
    ]);
    expect(content.text, '看看 ￼ 板块');
    expect(content.atoms[3], same(hashtag));
  });

  test('序列化原样写回带类型后缀的 ref', () {
    final content = EditableTextContent.fromInlines(const [
      TextRun('看看 '),
      LinkRun(
        href: '/tag/dev',
        hashtagRef: 'dev::tag',
        children: [TextRun('dev')],
      ),
    ]);

    final markdown = docToMarkdown([TextBlock(id: 'b0', content: content)]);
    expect(markdown.trim(), '看看 #dev::tag');
  });
}
