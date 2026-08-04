import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_message.dart';
import 'package:fluxdo/services/chat_summary_service.dart';

ChatMessage msg({
  required int id,
  required String text,
  String username = 'alice',
  String name = '',
  String? createdAt = '2026-08-04T10:00:00.000Z',
  String? deletedAt,
}) {
  return ChatMessage.fromJson({
    'id': id,
    'message': text,
    'chat_channel_id': 1,
    'created_at': createdAt,
    'deleted_at': deletedAt,
    'user': {'id': 1, 'username': username, 'name': name},
  });
}

void main() {
  group('ChatSummaryService.buildTranscript', () {
    test('输出「时间 昵称: 正文」逐行记录', () {
      final text = ChatSummaryService.buildTranscript([
        msg(id: 1, text: '早上好', username: 'alice', name: '爱丽丝'),
        msg(id: 2, text: '在的', username: 'bob'),
      ]);

      final lines = text.split('\n');
      expect(lines.length, 2);
      // 昵称优先于 username
      expect(lines[0], contains('爱丽丝: 早上好'));
      expect(lines[1], contains('bob: 在的'));
      // 带时间戳前缀
      expect(lines[0], startsWith('['));
    });

    test('跳过已删除消息与空白消息', () {
      final text = ChatSummaryService.buildTranscript([
        msg(id: 1, text: '保留'),
        msg(id: 2, text: '删掉的', deletedAt: '2026-08-04T11:00:00.000Z'),
        msg(id: 3, text: '   '),
      ]);
      expect(text.split('\n').length, 1);
      expect(text, contains('保留'));
      expect(text, isNot(contains('删掉的')));
    });

    test('单条超长消息被截断', () {
      final long = 'x' * 800;
      final text = ChatSummaryService.buildTranscript([msg(id: 1, text: long)]);
      expect(text, contains('…'));
      // 500 字上限 + 省略号，远小于原文
      expect(text.length, lessThan(700));
    });

    test('没有可用内容时返回空串', () {
      expect(ChatSummaryService.buildTranscript([]), '');
      expect(
        ChatSummaryService.buildTranscript([
          msg(id: 1, text: '', createdAt: null),
        ]),
        '',
      );
    });

    test('缺 created_at 时不输出时间前缀但保留正文', () {
      final text = ChatSummaryService.buildTranscript([
        msg(id: 1, text: '无时间', createdAt: null),
      ]);
      expect(text, 'alice: 无时间');
    });
  });

  group('ChatSummaryService 提示词', () {
    test('用户提示词带上频道名与时间范围', () {
      final prompt = ChatSummaryService.buildUserPrompt(
        channelTitle: 'General',
        hours: 6,
        transcript: 'alice: hi',
      );
      expect(prompt, contains('General'));
      expect(prompt, contains('6 小时'));
      expect(prompt, contains('alice: hi'));
    });

    test('系统提示词要求不编造内容', () {
      expect(ChatSummaryService.buildSystemPrompt(), contains('不要编造'));
    });
  });
}
