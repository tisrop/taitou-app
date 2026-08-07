import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/widgets/user/trust_level_info_sheet.dart';

Widget _testApp(Widget child) {
  return TranslationProvider(
    child: MaterialApp(
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
  testWidgets('shows every trust level and marks the current one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(const TrustLevelInfoContent(currentLevel: 2, canChat: true)),
    );

    expect(find.byKey(const ValueKey('trust-level-current')), findsOneWidget);
    for (var level = 0; level <= 4; level++) {
      expect(find.byKey(ValueKey('trust-level-row-$level')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('trust-level-chat-available')),
      findsOneWidget,
    );
    expect(find.text('L2 成员'), findsWidgets);
  });

  testWidgets('trust level badge invokes its details action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _testApp(
        Center(child: TrustLevelBadge(level: 1, onTap: () => tapped = true)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('trust-level-badge-1')));

    expect(tapped, isTrue);
  });
}
