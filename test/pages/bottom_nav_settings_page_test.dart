import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/navigation/nav_entry_registry.dart';
import 'package:fluxdo/pages/bottom_nav_settings_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestCurrentUserNotifier extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

Future<void> _pumpPage(WidgetTester tester, {required double width}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentUserProvider.overrideWith(_TestCurrentUserNotifier.new),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: const BottomNavSettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('手机底栏最多启用 5 项', (tester) async {
    await _pumpPage(tester, width: 500);

    expect(find.textContaining('/5 项'), findsOneWidget);
  });

  testWidgets('平板底栏最多启用 7 项', (tester) async {
    await _pumpPage(tester, width: 800);

    expect(find.textContaining('/7 项'), findsOneWidget);
  });

  testWidgets('桌面底栏允许启用全部入口', (tester) async {
    await _pumpPage(tester, width: 1400);

    final entryCount = NavEntryRegistry.buildAll().length;
    expect(find.textContaining('/$entryCount 项'), findsOneWidget);
  });
}
