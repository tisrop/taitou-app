import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Notion API 异常。
class NotionApiException implements Exception {
  NotionApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() =>
      'NotionApiException(${statusCode ?? '-'}${code != null ? '/$code' : ''}): $message';
}

/// Notion API 薄封装。
///
/// 设计：
/// - 用独立 Dio 实例，不带论坛 cookie；headers 固定 Authorization + Notion-Version
/// - 不做缓存、不做重试（除 429 速率限制）；调用方自己控制时序
/// - 方法返回原始 JSON Map，让上层决定怎么解析；只在 HTTP 非 2xx 时抛
class NotionClient {
  NotionClient(this.token, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.notion.com/v1/',
              headers: {
                'Authorization': 'Bearer $token',
                'Notion-Version': _notionVersion,
                'Content-Type': 'application/json',
              },
              // Notion 大多 < 5s，留点余量给国内网络。
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              // 我们自己根据 statusCode 抛 NotionApiException
              validateStatus: (_) => true,
            ),
          );

  static const String _notionVersion = '2022-06-28';

  final String token;
  final Dio _dio;

  /// 查询 database 里匹配 (topicId, postId) 的第一个 page id。
  /// [postId] 传 `null` 表示查"整篇话题"的 page (Post ID 字段为空或 0)。
  /// 找不到返回 null。
  Future<String?> queryPage(
    String databaseId, {
    required int topicId,
    int? postId,
    String topicIdProperty = 'Topic ID',
    String postIdProperty = 'Post ID',
  }) async {
    final filters = <Map<String, dynamic>>[
      {
        'property': topicIdProperty,
        'number': {'equals': topicId},
      },
    ];
    if (postId != null && postId > 0) {
      filters.add({
        'property': postIdProperty,
        'number': {'equals': postId},
      });
    } else {
      // 整篇话题:Post ID 字段为空,或显式为 0
      filters.add({
        'or': [
          {
            'property': postIdProperty,
            'number': {'is_empty': true},
          },
          {
            'property': postIdProperty,
            'number': {'equals': 0},
          },
        ],
      });
    }
    final body = {
      'filter': {'and': filters},
      'page_size': 1,
    };
    final res = await _post('databases/$databaseId/query', body);
    final results = res['results'] as List?;
    if (results == null || results.isEmpty) return null;
    return (results.first as Map<String, dynamic>)['id'] as String?;
  }

  /// 已废弃的旧接口,保留过渡。请改用 [queryPage]。
  @Deprecated('Use queryPage instead')
  Future<String?> queryPageByTopicId(
    String databaseId,
    int topicId, {
    String topicIdProperty = 'Topic ID',
  }) {
    return queryPage(
      databaseId,
      topicId: topicId,
      postId: null,
      topicIdProperty: topicIdProperty,
    );
  }

  /// 创建 page。[children] 最多 100 个 block。
  Future<Map<String, dynamic>> createPage({
    required String databaseId,
    required Map<String, dynamic> properties,
    List<Map<String, dynamic>>? children,
  }) {
    return _post('pages', {
      'parent': {'database_id': databaseId},
      'properties': properties,
      if (children != null && children.isNotEmpty) 'children': children,
    });
  }

  /// 向已有 block / page 追加 children，最多 100 个 / 次。
  Future<Map<String, dynamic>> appendBlockChildren(
    String blockId,
    List<Map<String, dynamic>> children,
  ) {
    return _patch('blocks/$blockId/children', {'children': children});
  }

  /// archive 一个 page（Notion 的「软删」）。
  Future<Map<String, dynamic>> archivePage(String pageId) {
    return _patch('pages/$pageId', {'archived': true});
  }

  /// 在某 parent page 下创建一个新的 database，properties 按本插件需要的 schema。
  /// 返回创建后的 database JSON（含 id）。
  Future<Map<String, dynamic>> createDatabaseForExport({
    required String parentPageId,
    required String title,
  }) {
    return _post('databases', {
      'parent': {'type': 'page_id', 'page_id': parentPageId},
      'title': [
        {
          'type': 'text',
          'text': {'content': title},
        },
      ],
      'properties': {
        'Name': {'title': {}},
        'URL': {'url': {}},
        'Topic ID': {'number': {}},
        'Post ID': {'number': {}},
        'Author': {'rich_text': {}},
        'Created': {'date': {}},
        'Synced': {'date': {}},
      },
    });
  }

  /// 仅用于「测试连接」：拉一下 database meta，能拿到说明 token + db id 都对。
  Future<Map<String, dynamic>> retrieveDatabase(String databaseId) {
    return _get('databases/$databaseId');
  }

  /// 在已有 database 上补一个 Number 类型的 property(没有则新增,已有则无操作)。
  /// 用于把"老版本一键创建"的 database 升级到新 schema(加 Post ID)。
  Future<void> ensureNumberProperty(
    String databaseId,
    String propertyName,
  ) async {
    final db = await retrieveDatabase(databaseId);
    final props = db['properties'] as Map<String, dynamic>?;
    if (props != null && props.containsKey(propertyName)) return;
    await _patch('databases/$databaseId', {
      'properties': {
        propertyName: {'number': {}},
      },
    });
  }

  /// 检查 database 是否含某个 property。
  Future<bool> hasProperty(String databaseId, String propertyName) async {
    final db = await retrieveDatabase(databaseId);
    final props = db['properties'] as Map<String, dynamic>?;
    return props != null && props.containsKey(propertyName);
  }

  // -- internal --

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _request(() => _dio.get<dynamic>(path));
    return res;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    return _request(() => _dio.post<dynamic>(path, data: body));
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) {
    return _request(() => _dio.patch<dynamic>(path, data: body));
  }

  /// 包装一次请求 —— 处理 429 重试 + 非 2xx 转 NotionApiException。
  /// 429 重试最多 3 次,采用 Retry-After 头或线性退避。
  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final Response<dynamic> resp;
      try {
        resp = await send();
      } on DioException catch (e) {
        throw NotionApiException(
          e.message ?? 'network error',
          statusCode: e.response?.statusCode,
        );
      }
      final code = resp.statusCode ?? 0;
      if (code == 429) {
        final retryAfter = double.tryParse(
          resp.headers.value('Retry-After') ?? '',
        );
        final wait = Duration(
          milliseconds: ((retryAfter ?? 1.0 + attempt) * 1000).toInt(),
        );
        debugPrint('[Notion] 429, retry after ${wait.inMilliseconds}ms');
        await Future<void>.delayed(wait);
        continue;
      }
      if (code < 200 || code >= 300) {
        final data = resp.data;
        String message = 'HTTP $code';
        String? errCode;
        if (data is Map) {
          message = (data['message'] as String?) ?? message;
          errCode = data['code'] as String?;
        }
        throw NotionApiException(message, statusCode: code, code: errCode);
      }
      final data = resp.data;
      if (data is Map<String, dynamic>) return data;
      return <String, dynamic>{};
    }
    throw NotionApiException('Notion API rate-limited too long');
  }
}
