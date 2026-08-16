part of 'discourse_service.dart';

/// GIF 选择器（站点在 `/gifs/` 下代理的 Tenor 形状接口，图源 Klipy）。
///
/// - `GET /gifs/categories.json` → `{locale, tags: [{searchterm, name, image, path}]}`
/// - `GET /gifs/search.json?q=…&pos=…` → `{next, results: [{id, media_formats, …}]}`
///
/// categories.json 里每项的 `path`（`/v2/search?q=…`）是上游 Tenor 的内部路径，
/// 站点没有原样暴露，用不上；点分类等价于拿它的 `searchterm` 调一次搜索
/// （和 Odoo 的同款 picker 一致）。
mixin _GifsMixin on _DiscourseServiceBase {
  static const _gifsRoot = '/gifs';

  /// 分类列表。这份数据基本不变，缓存到进程结束。
  List<GifCategory>? _gifCategoriesCache;

  Future<List<GifCategory>> getGifCategories() async {
    final cached = _gifCategoriesCache;
    if (cached != null) return cached;
    try {
      final response = await _dio.get(
        '$_gifsRoot/categories.json',
        // 面板自己会展示错误态，不需要全局 toast
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid gif categories response');
      }
      final list = GifCategory.listFromJson(Map<String, dynamic>.from(raw));
      _gifCategoriesCache = list;
      return list;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 搜索 GIF。
  ///
  /// [cursor] 传上一页响应里的 `next`；首页传 `0`（接口的起始位置约定）。
  Future<GifSearchPage> searchGifs(String query, {String? cursor}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const GifSearchPage(items: []);
    try {
      final response = await _dio.get(
        '$_gifsRoot/search.json',
        queryParameters: {'q': trimmed, 'pos': cursor ?? '0'},
        options: Options(extra: {'showErrorToast': false}),
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid gif search response');
      }
      return GifSearchPage.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
