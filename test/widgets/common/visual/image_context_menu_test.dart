import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/common/visual/image_context_menu.dart';

void main() {
  testWidgets('聊天图片长按菜单使用右侧浮动样式并显示图片操作', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          navigatorKey: navigatorKey,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: Scaffold(
            body: ImageContextMenuScope(
              presentation: ImageContextMenuPresentation.compactFloating,
              onMarkAd: () {},
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ImageContextMenu.show(
                    context: context,
                    imageUrl: 'https://example.com/image.png',
                  ),
                  child: const Text('打开菜单'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();

    expect(find.text('查看图片'), findsOneWidget);
    expect(find.text('下载图片'), findsOneWidget);
    expect(find.text('分享图片'), findsOneWidget);
    expect(find.text('以图搜图'), findsOneWidget);
    expect(find.text('页面信息'), findsOneWidget);
    expect(find.text('标记广告'), findsOneWidget);
    expect(find.text('更多选项'), findsOneWidget);
    expect(find.text('看图模式'), findsNothing);
    expect(find.text('扫描二维码'), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });
}
