import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/pages/image_viewer_page.dart';

void main() {
  testWidgets('图片查看器 Hero 参与用户手势返回动画', (tester) async {
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
          home: const ImageViewerPage(
            imageUrl: 'https://example.com/image.png',
            heroTag: 'profile-avatar',
          ),
        ),
      ),
    );

    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'profile-avatar');
    expect(hero.transitionOnUserGestures, isTrue);
  });

  testWidgets('从非 PageRoute 弹层打开时禁用 Hero 配对', (tester) async {
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
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => TextButton(
                  onPressed: () => ImageViewerPage.open(
                    dialogContext,
                    'https://example.com/image.png',
                    heroTag: 'dialog-image',
                  ),
                  child: const Text('open viewer'),
                ),
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open viewer'));
    await tester.pump();

    final viewer = tester.widget<ImageViewerPage>(
      find.byType(ImageViewerPage),
    );
    expect(viewer.heroTag, isNull);
  });
}
