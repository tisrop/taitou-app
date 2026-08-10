import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/assignment.dart';
import 'package:fluxdo/models/topic.dart';

Map<String, dynamic> _topicDetailJson({
  Map<String, dynamic>? assignedToUser,
  Map<String, dynamic>? assignedToGroup,
  String? assignmentNote,
  String? assignmentStatus,
  Map<String, dynamic>? indirectlyAssignedTo,
}) {
  final json = <String, dynamic>{
    'id': 1,
    'title': 'Topic',
    'slug': 'topic',
    'posts_count': 0,
    'category_id': 1,
    'post_stream': {'posts': <dynamic>[], 'stream': <dynamic>[]},
  };
  if (assignedToUser != null) json['assigned_to_user'] = assignedToUser;
  if (assignedToGroup != null) json['assigned_to_group'] = assignedToGroup;
  if (assignmentNote != null) json['assignment_note'] = assignmentNote;
  if (assignmentStatus != null) json['assignment_status'] = assignmentStatus;
  if (indirectlyAssignedTo != null) {
    json['indirectly_assigned_to'] = indirectlyAssignedTo;
  }
  return json;
}

void main() {
  group('AssignSuggestions', () {
    test('解析候选用户和允许指定的群组', () {
      final suggestions = AssignSuggestions.fromJson({
        'suggestions': [
          {
            'id': 7,
            'username': 'alice',
            'name': 'Alice',
            'avatar_template': '/user_avatar/example/alice/{size}/1_2.png',
          },
        ],
        'assign_allowed_on_groups': ['support'],
        'assign_allowed_for_groups': ['staff', 'moderators'],
      });

      expect(suggestions.suggestions.single.id, 7);
      expect(suggestions.suggestions.single.username, 'alice');
      expect(suggestions.assignAllowedGroups, ['support']);
      expect(suggestions.assignAllowedForGroups, ['staff', 'moderators']);
    });

    test('缺少可选数组时返回空集合', () {
      final suggestions = AssignSuggestions.fromJson(const {});

      expect(suggestions.suggestions, isEmpty);
      expect(suggestions.assignAllowedGroups, isEmpty);
      expect(suggestions.assignAllowedForGroups, isEmpty);
    });
  });

  group('TopicDetail assignment parsing', () {
    test('兼容 assigned_to_user 缺少 id 的插件响应', () {
      final detail = TopicDetail.fromJson(
        _topicDetailJson(
          assignedToUser: {
            'username': 'alice',
            'name': 'Alice',
            'avatar_template': '/user_avatar/example/alice/{size}/1_2.png',
          },
          assignmentNote: 'Follow up with the customer',
          assignmentStatus: 'In Progress',
        ),
      );

      expect(detail.isAssigned, isTrue);
      expect(detail.assignedToUser?.id, -1);
      expect(detail.assignedToUser?.username, 'alice');
      expect(detail.assignedToUser?.displayName, 'Alice');
      expect(detail.assignmentNote, 'Follow up with the customer');
      expect(detail.assignmentStatus, 'In Progress');
    });

    test('解析话题群组和帖子级用户、群组指定', () {
      final detail = TopicDetail.fromJson(
        _topicDetailJson(
          assignedToGroup: {'name': 'support'},
          indirectlyAssignedTo: {
            '101': {
              'post_number': 2,
              'assigned_to': {
                'username': 'bob',
                'name': 'Bob',
                'avatar_template': '/user_avatar/example/bob/{size}/1_2.png',
              },
              'assignment_note': 'Check the logs',
              'assignment_status': 'New',
            },
            '102': {
              'post_number': 3,
              'assigned_to': {'name': 'moderators'},
              'assignment_note': 'Review policy',
              'assignment_status': 'Done',
            },
          },
        ),
      );

      expect(detail.assignedToGroupName, 'support');
      expect(detail.indirectlyAssignedTo.keys, containsAll([101, 102]));

      final userAssignment = detail.indirectlyAssignedTo[101]!;
      expect(userAssignment.postNumber, 2);
      expect(userAssignment.assignedToUser?.username, 'bob');
      expect(userAssignment.displayName, 'Bob');
      expect(userAssignment.note, 'Check the logs');
      expect(userAssignment.status, 'New');

      final groupAssignment = detail.indirectlyAssignedTo[102]!;
      expect(groupAssignment.postNumber, 3);
      expect(groupAssignment.assignedToGroupName, 'moderators');
      expect(groupAssignment.displayName, 'moderators');
    });

    test('忽略无效帖子 id、无效记录和缺少指定目标的记录', () {
      final detail = TopicDetail.fromJson(
        _topicDetailJson(
          indirectlyAssignedTo: {
            'not-a-post-id': {
              'assigned_to': {'name': 'support'},
            },
            '103': 'not-a-map',
            '104': {'post_number': 4, 'assigned_to': <String, dynamic>{}},
          },
        ),
      );

      expect(detail.indirectlyAssignedTo, isEmpty);
    });

    test('copyWith 会保留服务端指定状态', () {
      final detail = TopicDetail.fromJson(
        _topicDetailJson(
          assignedToGroup: {'name': 'support'},
          assignmentNote: 'Keep me',
          assignmentStatus: 'New',
          indirectlyAssignedTo: {
            '101': {
              'post_number': 2,
              'assigned_to': {'name': 'moderators'},
            },
          },
        ),
      );

      final copied = detail.copyWith(title: 'Updated');

      expect(copied.assignedToGroupName, 'support');
      expect(copied.assignmentNote, 'Keep me');
      expect(copied.assignmentStatus, 'New');
      expect(copied.indirectlyAssignedTo[101]?.displayName, 'moderators');
    });
  });
}
