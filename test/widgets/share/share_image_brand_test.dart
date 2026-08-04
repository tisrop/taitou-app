import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/constants.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/share/ai_share_image_widget.dart';
import 'package:fluxdo/widgets/share/share_image_preview.dart';

void main() {
  testWidgets('share image uses the current app brand', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: Scaffold(
            body: AiShareImageWidget(
              messages: const [],
              topicTitle: '测试话题',
              topicId: 1,
              repaintBoundaryKey: GlobalKey(),
              shareTheme: ShareImageTheme.classic,
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('LINUX DO'), findsNothing);
  });
}
