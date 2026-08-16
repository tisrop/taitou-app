import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_voting_answer_header.dart';

Widget _wrap(Widget child) {
  return TranslationProvider(
    child: MaterialApp(
      locale: const Locale('zh'),
      navigatorKey: navigatorKey,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('问答头部显示回答数并支持票数/活动排序切换', (tester) async {
    var selectedActivity = false;
    await tester.pumpWidget(
      _wrap(
        PostVotingAnswerHeader(
          answerCount: 3,
          isActivityMode: false,
          onSortChanged: (value) => selectedActivity = value,
        ),
      ),
    );

    expect(find.text('3 个回答'), findsOneWidget);
    expect(find.text(S.current.postVoting_sortVotes), findsOneWidget);
    expect(find.text(S.current.postVoting_sortActivity), findsOneWidget);

    await tester.tap(find.text(S.current.postVoting_sortActivity));
    expect(selectedActivity, isTrue);

    await tester.pumpWidget(
      _wrap(
        PostVotingAnswerHeader(
          answerCount: 3,
          isActivityMode: true,
          onSortChanged: (value) => selectedActivity = value,
        ),
      ),
    );
    await tester.tap(find.text(S.current.postVoting_sortVotes));
    expect(selectedActivity, isFalse);
  });
}
