import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_action_bar.dart';

void main() {
  testWidgets('multiple reactions render a combined count and users entry', (
    tester,
  ) async {
    var usersSheetOpened = false;
    final loadingReplies = ValueNotifier<bool>(false);
    final showReplies = ValueNotifier<bool>(false);
    addTearDown(loadingReplies.dispose);
    addTearDown(showReplies.dispose);

    final post = Post(
      id: 1,
      username: 'author',
      avatarTemplate: '',
      cooked: '<p>content</p>',
      postNumber: 1,
      postType: 1,
      updatedAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      likeCount: 0,
      replyCount: 0,
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: Scaffold(
            body: PostActionBar(
              post: post,
              isGuest: false,
              isOwnPost: false,
              isLiking: false,
              reactions: const [
                PostReaction(id: 'heart', type: 'emoji', count: 3),
                PostReaction(id: '+1', type: 'emoji', count: 2),
              ],
              currentUserReaction: const PostReaction(
                id: '+1',
                type: 'emoji',
                count: 2,
              ),
              likeButtonKey: GlobalKey(),
              replies: const [],
              isLoadingRepliesNotifier: loadingReplies,
              showRepliesNotifier: showReplies,
              onToggleLike: () {},
              onReactionSelected: (_) {},
              onShowReactionUsers: (_) => usersSheetOpened = true,
              onShowMoreMenu: () {},
              onToggleReplies: () {},
              hideRepliesButton: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(usersSheetOpened, isTrue);
  });
}
