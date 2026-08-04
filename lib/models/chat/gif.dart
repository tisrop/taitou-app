/// GIF 选择器的数据模型。
///
/// 站点在 `/gifs/` 下代理了一层 Tenor 形状的接口（图源是 Klipy）：
/// - `GET /gifs/categories.json` → `{locale, tags: [...]}`
/// - `GET /gifs/v2/search?q=…` → `{next, results: [...]}`
library;

import '../../utils/url_helper.dart';

/// 分类标签（categories.json 里的一项）。
class GifCategory {
  /// 点进去用的搜索词，如 `love`
  final String searchTerm;

  /// 展示名，接口给的是带 `#` 前缀的形式（`#love`）
  final String name;

  /// 分类封面 GIF
  final String image;

  const GifCategory({
    required this.searchTerm,
    required this.name,
    required this.image,
  });

  /// 去掉接口自带的 `#` 前缀，UI 自己决定要不要加。
  String get displayName => name.startsWith('#') ? name.substring(1) : name;

  static List<GifCategory> listFromJson(Map<String, dynamic> json) {
    final tags = json['tags'];
    if (tags is! List) return const [];
    return tags
        .whereType<Map<String, dynamic>>()
        .map(GifCategory._fromJson)
        .where((c) => c.searchTerm.isNotEmpty && c.image.isNotEmpty)
        .toList();
  }

  factory GifCategory._fromJson(Map<String, dynamic> json) {
    return GifCategory(
      searchTerm: json['searchterm'] as String? ?? '',
      name: json['name'] as String? ?? '',
      image: UrlHelper.resolveUrlWithCdn(json['image'] as String? ?? ''),
    );
  }
}

/// 一条搜索结果。
class GifItem {
  final String id;

  /// 插入消息用的原图 URL（优先大图）
  final String url;

  /// 列表里展示用的小图 URL
  final String previewUrl;

  final int width;
  final int height;

  /// 无障碍描述，也用作插入 markdown 的 alt
  final String description;

  const GifItem({
    required this.id,
    required this.url,
    required this.previewUrl,
    required this.width,
    required this.height,
    required this.description,
  });

  /// 宽高比。接口偶尔给 0，兜个 1 避免除零把布局撑坏。
  double get aspectRatio => (width > 0 && height > 0) ? width / height : 1.0;

  /// 插进聊天输入框的 markdown。和 Discourse 图片语法一致：
  /// `![描述|宽x高](url)`
  String toMarkdown() {
    final escapedDescription = description
        .replaceAll(r'\', r'\\')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    return '![$escapedDescription|${width}x$height]($url)';
  }

  /// `media_formats` 里按清晰度从高到低挑一个可用的。
  /// Tenor 形状常见键：gif / mediumgif / tinygif / nanogif；Klipy 的搜索
  /// 响应也可能只提供 webp。
  static const _urlPreference = [
    'gif',
    'mediumgif',
    'webp',
    'tinygif',
    'nanogif',
  ];
  static const _previewPreference = [
    'tinygif',
    'nanogif',
    'webp',
    'mediumgif',
    'gif',
  ];

  static List<GifItem> listFromJson(Map<String, dynamic> json) {
    final results = json['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(GifItem._tryFromJson)
        .whereType<GifItem>()
        .toList();
  }

  /// 下一页游标。
  ///
  /// 接口沿用 Tenor 的位置约定：首次请求传 `pos=0`，响应里的 `next` 是下次
  /// 要传的位置。**没有更多结果时 `next` 会回到 `"0"`**，此时必须当作"到底了"
  /// —— 否则会拿着 0 反复请求第一页，翻页永远停不下来。
  static String? nextCursorFromJson(Map<String, dynamic> json) {
    final next = json['next'];
    // 少数实现把 next 给成数字
    final value = next is String ? next : (next is num ? '$next' : null);
    if (value == null || value.isEmpty || value == '0') return null;
    return value;
  }

  /// 解析失败（拿不到任何可用 URL）返回 null，让调用方直接跳过这一条，
  /// 而不是整页崩掉。
  static GifItem? _tryFromJson(Map<String, dynamic> json) {
    final formats = json['media_formats'];
    if (formats is! Map<String, dynamic>) return null;

    final main = _pick(formats, _urlPreference);
    if (main == null) return null;
    final preview = _pick(formats, _previewPreference) ?? main;

    return GifItem(
      id: json['id']?.toString() ?? main.url,
      url: main.url,
      previewUrl: preview.url,
      width: main.width,
      height: main.height,
      description:
          (json['content_description'] as String?)?.trim().isNotEmpty == true
          ? (json['content_description'] as String).trim()
          : 'GIF',
    );
  }

  static ({String url, int width, int height})? _pick(
    Map<String, dynamic> formats,
    List<String> preference,
  ) {
    for (final key in preference) {
      final entry = formats[key];
      if (entry is! Map<String, dynamic>) continue;
      final url = entry['url'] as String?;
      if (url == null || url.isEmpty) continue;
      // dims 是 [宽, 高]
      final dims = entry['dims'];
      final width = dims is List && dims.length >= 2 && dims[0] is int
          ? dims[0] as int
          : 0;
      final height = dims is List && dims.length >= 2 && dims[1] is int
          ? dims[1] as int
          : 0;
      return (
        url: UrlHelper.resolveUrlWithCdn(url),
        width: width,
        height: height,
      );
    }
    return null;
  }
}

/// 一页搜索结果 + 下一页游标。
class GifSearchPage {
  final List<GifItem> items;
  final String? nextCursor;

  const GifSearchPage({required this.items, this.nextCursor});

  factory GifSearchPage.fromJson(Map<String, dynamic> json) {
    return GifSearchPage(
      items: GifItem.listFromJson(json),
      nextCursor: GifItem.nextCursorFromJson(json),
    );
  }
}
