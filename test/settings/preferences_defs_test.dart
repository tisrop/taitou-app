import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/settings/definitions/preferences_defs.dart';
import 'package:fluxdo/settings/settings_model.dart';

Future<List<SettingsModel>> _pumpAndCollectBasicItems(
  WidgetTester tester,
) async {
  late List<SettingsModel> items;
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
        home: Builder(
          builder: (context) {
            items = buildPreferencesGroups(context)
                .firstWhere(
                  (group) => group.title == context.l10n.preferences_basic,
                )
                .items;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );

  return items;
}

void main() {
  testWidgets('基础设置包含全屏侧滑返回开关', (tester) async {
    final items = await _pumpAndCollectBasicItems(tester);

    expect(items.map((item) => item.id), contains('fullscreenSwipeBack'));
  });
}
