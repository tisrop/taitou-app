import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/node/node.dart';
import 'package:fluxdo_render/src/parser/paragraph_parser.dart';

void main() {
  final parser = ParagraphParser();

  test('hashtag 提取 ref、显示名与 use 图标', () {
    final nodes = parser.parse(
      '<p><a class="hashtag-cooked" href="/c/dev/4" '
      'data-ref="dev" data-slug="dev">'
      '<svg class="d-icon d-icon-folder"><use href="#folder"></use></svg>'
      '<span>开发调优</span></a></p>',
    );

    final paragraph = nodes.single as ParagraphNode;
    final link = paragraph.inlines.single as LinkRun;
    expect(link.href, '/c/dev/4');
    expect(link.hashtagRef, 'dev');
    expect(link.hashtagIcon, 'folder');
    expect(link.children, const [TextRun('开发调优')]);
  });

  test('use 缺失时从 d-icon class 提取图标', () {
    final nodes = parser.parse(
      '<p><a class="hashtag-cooked" href="/tag/dev" data-slug="dev">'
      '<svg class="d-icon d-icon-tag"></svg><span>dev</span></a></p>',
    );

    final paragraph = nodes.single as ParagraphNode;
    final link = paragraph.inlines.single as LinkRun;
    expect(link.hashtagRef, 'dev');
    expect(link.hashtagIcon, 'tag');
  });

  test('hashtagIcon 参与 LinkRun 相等性', () {
    const folder = LinkRun(
      href: '/c/dev/4',
      children: [TextRun('开发调优')],
      hashtagRef: 'dev',
      hashtagIcon: 'folder',
    );
    const tag = LinkRun(
      href: '/c/dev/4',
      children: [TextRun('开发调优')],
      hashtagRef: 'dev',
      hashtagIcon: 'tag',
    );

    expect(folder, isNot(tag));
    expect(folder.hashCode, isNot(tag.hashCode));
  });
}
