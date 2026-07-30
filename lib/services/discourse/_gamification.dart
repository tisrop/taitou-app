part of 'discourse_service.dart';

mixin _GamificationMixin on _DiscourseServiceBase {
  /// 获取 discourse-gamification 排行榜。
  ///
  /// `page` 从 0 开始。默认请求全时段；调用方也可传插件支持的其他周期。
  ///
  /// 不要在这里覆盖 Dio 的 `validateStatus`：默认排行榜端点可能返回 3xx，
  /// 需要交给全局重定向拦截器解析实际排行榜地址。
  Future<GamificationLeaderboardResponse> getGamificationLeaderboard({
    int? leaderboardId,
    int page = 0,
    String period = 'all_time',
  }) async {
    final resolvedLeaderboardId =
        leaderboardId ??
        AppConstants.siteCustomization.gamificationLeaderboardId;
    final path = resolvedLeaderboardId == null
        ? '/leaderboard.json'
        : '/leaderboard/$resolvedLeaderboardId.json';
    final response = await _dio.get(
      path,
      queryParameters: {'page': page, 'period': period},
    );

    final raw = response.data;
    if (raw is! Map) {
      throw const FormatException('Invalid gamification leaderboard response');
    }
    return GamificationLeaderboardResponse.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }
}
