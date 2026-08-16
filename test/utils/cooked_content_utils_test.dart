import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/cooked_content_utils.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

/// 用真实 cooked HTML 过一遍解析器，避免手搓节点树跑偏。
CookedBubbleStyle styleOf(String cooked) =>
    cookedBubbleStyleOf(ParagraphParser().parse(cooked));

void main() {
  group('cookedBubbleStyleOf 纯图片', () {
    test('单张外链图片', () {
      expect(
        styleOf(
          '<p><img src="https://static.klipy.com/a.webp" '
          'alt="Happy Baby Laughing" width="332" height="498"></p>',
        ),
        CookedBubbleStyle.image,
      );
    });

    test('图片前后的换行空白文本不影响判定', () {
      expect(
        styleOf('<p>\n  <img src="https://e.com/a.png">\n</p>\n'),
        CookedBubbleStyle.image,
      );
    });

    test('lightbox 包装的上传图', () {
      expect(
        styleOf(
          '<div class="lightbox-wrapper">'
          '<a class="lightbox" href="https://e.com/orig.png" title="a.png">'
          '<img src="https://e.com/thumb.png" width="690" height="388">'
          '<div class="meta">'
          '<span class="filename">a.png</span>'
          '<span class="informations">1024×576 120 KB</span>'
          '</div></a></div>',
        ),
        CookedBubbleStyle.image,
      );
    });

    test('多张图片', () {
      expect(
        styleOf(
          '<p><img src="https://e.com/a.png"><img src="https://e.com/b.png"></p>',
        ),
        CookedBubbleStyle.image,
      );
    });

    test('图片 + emoji 混排按图片处理', () {
      expect(
        styleOf(
          '<p><img src="https://e.com/a.png">'
          '<img src="/images/emoji/twemoji/smile.png" title=":smile:" '
          'class="emoji" alt=":smile:"></p>',
        ),
        CookedBubbleStyle.image,
      );
    });
  });

  group('cookedBubbleStyleOf 纯 emoji', () {
    test('整段独立大表情（only-emoji）', () {
      expect(
        styleOf(
          '<p><img src="/images/emoji/twemoji/tada.png" alt=":tada:" '
          'class="emoji only-emoji" title=":tada:"></p>',
        ),
        CookedBubbleStyle.emoji,
      );
    });

    test('多个 emoji 连排', () {
      expect(
        styleOf(
          '<p><img src="/images/emoji/twemoji/a.png" class="emoji" alt=":a:">'
          '<img src="/images/emoji/twemoji/b.png" class="emoji" alt=":b:"></p>',
        ),
        CookedBubbleStyle.emoji,
      );
    });

    test('emoji 夹文字仍是普通气泡', () {
      expect(
        styleOf(
          '<p>哈 <img src="/images/emoji/twemoji/a.png" class="emoji" '
          'alt=":a:"></p>',
        ),
        CookedBubbleStyle.bubble,
      );
    });
  });

  group('cookedBubbleStyleOf 普通气泡', () {
    test('纯文字', () {
      expect(styleOf('<p>大家好</p>'), CookedBubbleStyle.bubble);
    });

    test('图文混排', () {
      expect(
        styleOf('<p>看这个 <img src="https://e.com/a.png"></p>'),
        CookedBubbleStyle.bubble,
      );
    });

    test('图片 + 独立文字段落', () {
      expect(
        styleOf('<p><img src="https://e.com/a.png"></p><p>说明文字</p>'),
        CookedBubbleStyle.bubble,
      );
    });

    test('空内容', () {
      expect(styleOf(''), CookedBubbleStyle.bubble);
      expect(styleOf('<p></p>'), CookedBubbleStyle.bubble);
    });

    test('代码块 / 引用', () {
      expect(styleOf('<pre><code>print(1)</code></pre>'), CookedBubbleStyle.bubble);
      expect(styleOf('<blockquote><p>引用</p></blockquote>'), CookedBubbleStyle.bubble);
    });
  });
}
