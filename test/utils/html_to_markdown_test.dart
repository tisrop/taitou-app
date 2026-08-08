/// Discourse cooked → Markdown 的引用头与图片短链行为验证。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/html_to_markdown.dart';

void main() {
  group('aside.quote 头部', () {
    test('无显示名时沿用 username 首字段', () {
      final markdown = HtmlToMarkdown.convert(
        '<aside class="quote" data-username="sam" data-post="3" data-topic="42">'
        '<blockquote><p>被引内容</p></blockquote></aside>',
      );
      expect(markdown, contains('[quote="sam, post:3, topic:42"]'));
      expect(markdown, isNot(contains('username:')));
    });

    test('有显示名时保留昵称与真实用户名', () {
      final markdown = HtmlToMarkdown.convert(
        '<aside class="quote" data-username="sam" '
        'data-display-name="张三" data-post="3" data-topic="42">'
        '<blockquote><p>被引内容</p></blockquote></aside>',
      );
      expect(
        markdown,
        contains('[quote="张三, post:3, topic:42, username:sam"]'),
      );
    });
  });

  group('图片 upload:// 短链', () {
    test('data-base62-sha1 优先生成短链', () {
      final markdown = HtmlToMarkdown.convert(
        '<div class="lightbox-wrapper">'
        '<a class="lightbox" href="https://x.test/uploads/orig/abc.png" title="图片">'
        '<img src="https://x.test/uploads/opt/abc.png" '
        'data-base62-sha1="b62abc" width="690" height="345">'
        '</a></div>',
      );
      expect(markdown, contains('](upload://b62abc.png)'));
    });

    test('普通 img 无 sha1 时回退 data-orig-src', () {
      final markdown = HtmlToMarkdown.convert(
        '<p><img src="/images/transparent.png" alt="示意" '
        'data-orig-src="upload://abc.png" width="100" height="80"></p>',
      );
      expect(markdown, contains('](upload://abc.png)'));
      expect(markdown, isNot(contains('transparent.png')));
    });

    test('lightbox 无 sha1 时回退 img 的 data-orig-src', () {
      final markdown = HtmlToMarkdown.convert(
        '<div class="lightbox-wrapper">'
        '<a class="lightbox" href="https://x.test/uploads/orig/abc.png" title="图片">'
        '<img src="/images/transparent.png" data-orig-src="upload://abc.png">'
        '</a></div>',
      );
      expect(markdown, contains('](upload://abc.png)'));
    });
  });
}
