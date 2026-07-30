import '../utils/time_utils.dart';
import '../utils/url_helper.dart';

/// Gamification 排行榜配置。
class GamificationLeaderboard {
  const GamificationLeaderboard({
    required this.id,
    required this.name,
    this.defaultPeriod,
    this.fromDate,
    this.toDate,
    this.periodFilterDisabled = false,
  });

  final int id;
  final String name;
  final String? defaultPeriod;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool periodFilterDisabled;

  factory GamificationLeaderboard.fromJson(Map<String, dynamic> json) {
    return GamificationLeaderboard(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '',
      defaultPeriod: json['default_period']?.toString(),
      fromDate: _asDateTime(json['from_date']),
      toDate: _asDateTime(json['to_date']),
      periodFilterDisabled: json['period_filter_disabled'] as bool? ?? false,
    );
  }
}

/// 排行榜中的用户积分与名次。
class GamificationUserScore {
  const GamificationUserScore({
    required this.id,
    required this.username,
    required this.avatarTemplate,
    required this.totalScore,
    required this.position,
    this.name,
  });

  final int id;
  final String username;
  final String? name;
  final String avatarTemplate;
  final int totalScore;
  final int position;

  String get displayName => name?.isNotEmpty == true ? name! : username;

  String getAvatarUrl({int size = 96}) {
    final template = avatarTemplate.replaceAll('{size}', '$size');
    return UrlHelper.resolveUrlWithCdn(template);
  }

  factory GamificationUserScore.fromJson(
    Map<String, dynamic> json, {
    int? position,
  }) {
    return GamificationUserScore(
      id: _asInt(json['id']),
      username: json['username'] as String? ?? '',
      name: json['name'] as String?,
      avatarTemplate: json['avatar_template'] as String? ?? '',
      totalScore: _asInt(json['total_score']),
      position: position ?? _asInt(json['position']),
    );
  }
}

/// 当前用户的排行榜位置。服务端把用户信息嵌在 `user` 字段中。
class GamificationPersonalScore {
  const GamificationPersonalScore({required this.user, required this.position});

  final GamificationUserScore user;
  final int position;

  factory GamificationPersonalScore.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final userJson = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{};
    final position = _asInt(json['position'] ?? userJson['position']);
    return GamificationPersonalScore(
      user: GamificationUserScore.fromJson(userJson, position: position),
      position: position,
    );
  }
}

class GamificationLeaderboardResponse {
  const GamificationLeaderboardResponse({
    required this.leaderboard,
    required this.users,
    this.personal,
    this.reason,
  });

  final GamificationLeaderboard leaderboard;
  final List<GamificationUserScore> users;
  final GamificationPersonalScore? personal;

  /// 缓存尚未生成时服务端会返回 202，并在这里说明原因。
  final String? reason;

  bool get isPreparing => reason?.isNotEmpty == true && users.isEmpty;

  factory GamificationLeaderboardResponse.fromJson(Map<String, dynamic> json) {
    final rawLeaderboard = json['leaderboard'];
    final leaderboardJson = rawLeaderboard is Map
        ? Map<String, dynamic>.from(rawLeaderboard)
        : Map<String, dynamic>.from(json);

    final rawPersonal = json['personal'];
    final personal = rawPersonal is Map && rawPersonal.isNotEmpty
        ? GamificationPersonalScore.fromJson(
            Map<String, dynamic>.from(rawPersonal),
          )
        : null;

    return GamificationLeaderboardResponse(
      leaderboard: GamificationLeaderboard.fromJson(leaderboardJson),
      users: (json['users'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                GamificationUserScore.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      personal: personal,
      reason: json['reason'] as String?,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  return TimeUtils.parseUtcTime(value.toString());
}
