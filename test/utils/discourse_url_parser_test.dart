import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/discourse_url_parser.dart';

void main() {
  group('分类链接', () {
    test('支持普通和多级分类路径', () {
      expect(DiscourseUrlParser.parseCategory('/c/dev/4')?.categoryId, 4);
      expect(
        DiscourseUrlParser.parseCategory(
          '/c/root/child/42/l/latest',
        )?.categoryId,
        42,
      );
      expect(
        DiscourseUrlParser.parseCategory('https://example.com/c/9')?.categoryId,
        9,
      );
    });

    test('非分类路径返回 null', () {
      expect(DiscourseUrlParser.parseCategory('/tag/dev'), isNull);
      expect(DiscourseUrlParser.parseCategory('/c/dev'), isNull);
    });
  });

  group('标签链接', () {
    test('支持 tag/tags 并解码中文', () {
      expect(DiscourseUrlParser.parseTag('/tag/dev'), 'dev');
      expect(
        DiscourseUrlParser.parseTag(
          '/tags/%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD',
        ),
        '人工智能',
      );
    });

    test('畸形转义不抛异常', () {
      expect(DiscourseUrlParser.parseTag('/tag/%ZZ'), '%ZZ');
    });
  });
}
