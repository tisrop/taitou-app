import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/topic_more_topics.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Topic _topic(int id, String title) {
  return Topic(
    id: id,
    title: title,
    slug: 'topic-$id',
    postsCount: 3,
    replyCount: 2,
    views: 0,
    likeCount: 0,
    categoryId: '1',
  );
}

TopicDetail _detail({
  List<Topic> suggested = const [],
  List<Topic> related = const [],
  String archetype = 'regular',
}) {
  return TopicDetail(
    id: 1,
    title: 'Current topic',
    slug: 'current-topic',
    postsCount: 0,
    postStream: PostStream(posts: const [], stream: const []),
    categoryId: 1,
    closed: false,
    archived: false,
    archetype: archetype,
    suggestedTopics: suggested,
    relatedTopics: related,
  );
}

Future<void> _pumpSection(
  WidgetTester tester,
  TopicDetail detail, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: Scaffold(body: MoreTopicsSection(detail: detail)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('同时存在两组时显示切换标签并默认展示相关话题', (tester) async {
    await _pumpSection(
      tester,
      _detail(
        related: [_topic(10, 'Related topic')],
        suggested: [_topic(20, 'Suggested topic')],
      ),
    );

    expect(find.byKey(const ValueKey('more-topics-section')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('more-topics-related-tab')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('more-topics-suggested-tab')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('more-topic-10')), findsOneWidget);
    expect(find.text('Related topic'), findsOneWidget);
    expect(find.text('Suggested topic'), findsNothing);
  });

  testWidgets('点击建议话题标签后切换列表', (tester) async {
    await _pumpSection(
      tester,
      _detail(
        related: [_topic(10, 'Related topic')],
        suggested: [_topic(20, 'Suggested topic')],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('more-topics-suggested-tab')));
    await tester.pump();

    expect(find.byKey(const ValueKey('more-topic-10')), findsNothing);
    expect(find.byKey(const ValueKey('more-topic-20')), findsOneWidget);
    expect(find.text('Related topic'), findsNothing);
    expect(find.text('Suggested topic'), findsOneWidget);
  });

  testWidgets('私信不展示更多话题', (tester) async {
    await _pumpSection(
      tester,
      _detail(
        archetype: 'private_message',
        related: [_topic(10, 'Related topic')],
      ),
    );

    expect(find.byKey(const ValueKey('more-topics-section')), findsNothing);
  });

  testWidgets('关闭设置后不展示更多话题', (tester) async {
    await _pumpSection(
      tester,
      _detail(related: [_topic(10, 'Related topic')]),
      preferences: {'pref_show_suggested_topics': false},
    );

    expect(find.byKey(const ValueKey('more-topics-section')), findsNothing);
  });
}
