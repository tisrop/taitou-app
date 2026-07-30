import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/gamification.dart';
import 'package:fluxdo/pages/gamification_leaderboard_page.dart';

void main() {
  testWidgets('shows personal rank and leaderboard scores', (tester) async {
    Future<GamificationLeaderboardResponse> loadPage(int page) async {
      return GamificationLeaderboardResponse(
        leaderboard: const GamificationLeaderboard(id: 1, name: 'Community'),
        users: const [
          GamificationUserScore(
            id: 10,
            username: 'alice',
            name: 'Alice',
            avatarTemplate: '',
            totalScore: 128,
            position: 1,
          ),
        ],
        personal: const GamificationPersonalScore(
          user: GamificationUserScore(
            id: 20,
            username: 'bob',
            avatarTemplate: '',
            totalScore: 42,
            position: 8,
          ),
          position: 8,
        ),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        child: TranslationProvider(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: GamificationLeaderboardPage(loadPage: loadPage),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('积分排行'), findsOneWidget);
    expect(find.text('你的排名'), findsOneWidget);
    expect(find.text('#8'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('continues pagination when a full page only has duplicates', (
    tester,
  ) async {
    final requestedPages = <int>[];
    final firstPageUsers = List.generate(
      20,
      (index) => GamificationUserScore(
        id: index,
        username: 'user$index',
        avatarTemplate: '',
        totalScore: 100 - index,
        position: index + 1,
      ),
    );

    Future<GamificationLeaderboardResponse> loadPage(int page) async {
      requestedPages.add(page);
      final users = switch (page) {
        0 || 1 => firstPageUsers,
        2 => const [
          GamificationUserScore(
            id: 100,
            username: 'unique-user',
            name: 'Unique User',
            avatarTemplate: '',
            totalScore: 1,
            position: 21,
          ),
        ],
        _ => const <GamificationUserScore>[],
      };
      return GamificationLeaderboardResponse(
        leaderboard: const GamificationLeaderboard(id: 1, name: 'Community'),
        users: users,
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        child: TranslationProvider(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: GamificationLeaderboardPage(loadPage: loadPage),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(CustomScrollView);
    await tester.drag(scrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(requestedPages, containsAllInOrder([0, 1, 2]));
    expect(find.text('Unique User'), findsOneWidget);
  });
}
