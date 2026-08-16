import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/gif.dart';

/// 用户提供的 categories.json 真实片段
const _categoriesJson = '''
{
  "locale": "en",
  "tags": [
    {
      "searchterm": "love",
      "path": "/v2/search?q=love&locale=en&component=categories&contentfilter=high",
      "image": "https://static.klipy.com/ii/ce286d05b8e1a47cd4f32b0e1b6dec0e/63/03/abn7c95q.gif",
      "name": "#love",
      "id": "4686121372877682"
    },
    {
      "searchterm": "thank you",
      "path": "/v2/search?q=thank you&locale=en&component=categories&contentfilter=high",
      "image": "https://static.klipy.com/ii/50d7c955398dfd7e3c8ba5281154280f/db/47/3PeSwTbjqDINy5t.gif",
      "name": "#thank you",
      "id": "4592975974015739"
    }
  ]
}
''';

Map<String, dynamic> decode(String s) => json.decode(s) as Map<String, dynamic>;

void main() {
  group('GifCategory', () {
    test('解析 tags 列表', () {
      final list = GifCategory.listFromJson(decode(_categoriesJson));
      expect(list.length, 2);
      expect(list.first.searchTerm, 'love');
      expect(list.first.image, endsWith('abn7c95q.gif'));
    });

    test('displayName 去掉接口自带的 # 前缀', () {
      final list = GifCategory.listFromJson(decode(_categoriesJson));
      expect(list.first.name, '#love');
      expect(list.first.displayName, 'love');
      expect(list[1].displayName, 'thank you');
    });

    test('缺 searchterm 或 image 的条目被丢弃', () {
      final list = GifCategory.listFromJson({
        'tags': [
          {'searchterm': '', 'image': 'https://e.com/a.gif', 'name': '#x'},
          {'searchterm': 'ok', 'image': '', 'name': '#ok'},
          {
            'searchterm': 'good',
            'image': 'https://e.com/b.gif',
            'name': '#good',
          },
        ],
      });
      expect(list.length, 1);
      expect(list.single.searchTerm, 'good');
    });

    test('tags 缺失或类型不对时返回空列表，不抛异常', () {
      expect(GifCategory.listFromJson({}), isEmpty);
      expect(GifCategory.listFromJson({'tags': 'nope'}), isEmpty);
    });
  });

  group('GifSearchPage', () {
    Map<String, dynamic> result({
      required Map<String, dynamic> formats,
      String id = '1',
      String? description = 'Cry GIF',
    }) => {
      'id': id,
      'content_description': description,
      'media_formats': formats,
    };

    test('解析 results 与 next 游标', () {
      final page = GifSearchPage.fromJson({
        'next': 'CAgQpIGj',
        'results': [
          result(
            formats: {
              'gif': {
                'url': 'https://static.klipy.com/big.gif',
                'dims': [480, 270],
              },
              'tinygif': {
                'url': 'https://static.klipy.com/small.gif',
                'dims': [220, 124],
              },
            },
          ),
        ],
      });

      expect(page.nextCursor, 'CAgQpIGj');
      expect(page.items.length, 1);
      final item = page.items.single;
      // 插入用大图，列表展示用小图
      expect(item.url, 'https://static.klipy.com/big.gif');
      expect(item.previewUrl, 'https://static.klipy.com/small.gif');
      expect(item.width, 480);
      expect(item.height, 270);
    });

    test('next 为空串时视作没有下一页', () {
      final page = GifSearchPage.fromJson({'next': '', 'results': []});
      expect(page.nextCursor, isNull);
    });

    test('next 回到 "0" 视作到底，避免翻页绕回第一页死循环', () {
      // 首次请求传 pos=0，接口没有更多结果时 next 会回 "0"
      expect(
        GifSearchPage.fromJson({'next': '0', 'results': []}).nextCursor,
        isNull,
      );
      expect(
        GifSearchPage.fromJson({'next': 0, 'results': []}).nextCursor,
        isNull,
      );
    });

    test('next 给成数字时也能取到游标', () {
      final page = GifSearchPage.fromJson({'next': 30, 'results': []});
      expect(page.nextCursor, '30');
    });

    test('只有 tinygif 时降级用它当原图', () {
      final page = GifSearchPage.fromJson({
        'results': [
          result(
            formats: {
              'tinygif': {
                'url': 'https://static.klipy.com/only.gif',
                'dims': [220, 190],
              },
            },
          ),
        ],
      });
      final item = page.items.single;
      expect(item.url, 'https://static.klipy.com/only.gif');
      expect(item.previewUrl, item.url);
    });

    test('只提供 webp 时仍能解析 Klipy 搜索结果', () {
      final page = GifSearchPage.fromJson({
        'next': 'Mg==',
        'results': [
          result(
            id: '5368076752517710',
            formats: {
              'webp': {
                'url': 'https://static.klipy.com/happy.webp',
                'dims': [360, 360],
              },
            },
          ),
        ],
      });

      expect(page.nextCursor, 'Mg==');
      expect(page.items, hasLength(1));
      final item = page.items.single;
      expect(item.url, 'https://static.klipy.com/happy.webp');
      expect(item.previewUrl, item.url);
      expect(item.width, 360);
      expect(item.height, 360);
    });

    test('拿不到任何可用 URL 的条目被跳过，不影响同页其它结果', () {
      final page = GifSearchPage.fromJson({
        'results': [
          {'id': 'bad', 'media_formats': {}},
          {'id': 'alsoBad'},
          result(
            id: 'good',
            formats: {
              'gif': {
                'url': 'https://static.klipy.com/good.gif',
                'dims': [100, 100],
              },
            },
          ),
        ],
      });
      expect(page.items.length, 1);
      expect(page.items.single.id, 'good');
    });

    test('dims 缺失时宽高为 0，aspectRatio 兜底为 1 不会除零', () {
      final page = GifSearchPage.fromJson({
        'results': [
          result(
            formats: {
              'gif': {'url': 'https://static.klipy.com/nodims.gif'},
            },
          ),
        ],
      });
      final item = page.items.single;
      expect(item.width, 0);
      expect(item.height, 0);
      expect(item.aspectRatio, 1.0);
    });

    test('toMarkdown 产出 Discourse 图片语法', () {
      final page = GifSearchPage.fromJson({
        'results': [
          result(
            description: 'Happy Baby Laughing',
            formats: {
              'gif': {
                'url': 'https://static.klipy.com/a.gif',
                'dims': [332, 498],
              },
            },
          ),
        ],
      });
      expect(
        page.items.single.toMarkdown(),
        '![Happy Baby Laughing|332x498](https://static.klipy.com/a.gif)',
      );
    });

    test('toMarkdown 转义描述中的 Markdown 分隔字符', () {
      final page = GifSearchPage.fromJson({
        'results': [
          result(
            description: r'Cat [waves] (again) \ wow',
            formats: {
              'gif': {
                'url': 'https://static.klipy.com/a.gif',
                'dims': [320, 180],
              },
            },
          ),
        ],
      });
      expect(
        page.items.single.toMarkdown(),
        r'![Cat \[waves\] \(again\) \\ wow|320x180](https://static.klipy.com/a.gif)',
      );
    });

    test('缺描述时 alt 退回 GIF', () {
      final page = GifSearchPage.fromJson({
        'results': [
          result(
            description: null,
            formats: {
              'gif': {
                'url': 'https://static.klipy.com/a.gif',
                'dims': [10, 10],
              },
            },
          ),
        ],
      });
      expect(page.items.single.toMarkdown(), startsWith('![GIF|10x10]'));
    });
  });
}
