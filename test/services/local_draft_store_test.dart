import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/draft.dart';
import 'package:fluxdo/services/local_draft_store.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> box;
  late DateTime now;
  var sequence = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_draft_store_test_');
    box = await Hive.openBox<Map>(
      'local_drafts_${sequence++}',
      path: tempDir.path,
    );
    now = DateTime.utc(2026, 6, 13, 12);
  });

  tearDown(() async {
    if (box.isOpen) await box.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  LocalDraftStore createStore() =>
      LocalDraftStore(boxFactory: () async => box, now: () => now);

  test('按账号和 draftKey 隔离并完整恢复草稿数据', () async {
    final store = createStore();
    const data = DraftData(
      title: '标题',
      reply: '正文',
      categoryId: 7,
      tags: ['flutter', 'desktop'],
      action: 'createTopic',
    );

    await store.write(
      accountId: 'alice',
      draftKey: Draft.newTopicKey,
      data: data,
      sequence: 3,
    );

    final restored = await store.read('alice', Draft.newTopicKey);
    expect(restored, isNotNull);
    expect(restored!.data.toJson(), data.toJson());
    expect(restored.sequence, 3);
    expect(restored.updatedAt, now);
    expect(await store.read('bob', Draft.newTopicKey), isNull);
    expect(await store.read('alice', 'topic_42'), isNull);
  });

  test('条件删除不会让旧保存结果误删更新后的本地内容', () async {
    final store = createStore();
    const oldData = DraftData(reply: '旧内容', action: 'reply');
    const newData = DraftData(reply: '新内容', action: 'reply');

    await store.write(
      accountId: 'alice',
      draftKey: 'topic_42',
      data: newData,
      sequence: 5,
    );

    expect(
      await store.deleteIfMatches(
        accountId: 'alice',
        draftKey: 'topic_42',
        data: oldData,
      ),
      isFalse,
    );
    expect((await store.read('alice', 'topic_42'))!.data.reply, '新内容');

    expect(
      await store.deleteIfMatches(
        accountId: 'alice',
        draftKey: 'topic_42',
        data: newData,
      ),
      isTrue,
    );
    expect(await store.read('alice', 'topic_42'), isNull);
  });

  test('读取时清理超过保留期的本地草稿', () async {
    final store = createStore();
    await store.write(
      accountId: 'alice',
      draftKey: 'topic_42',
      data: const DraftData(reply: '过期内容', action: 'reply'),
      sequence: 1,
    );

    now = now.add(const Duration(days: 31));

    expect(await store.read('alice', 'topic_42'), isNull);
    expect(box.isEmpty, isTrue);
  });
}
