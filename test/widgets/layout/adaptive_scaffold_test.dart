import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/layout/adaptive_navigation.dart';
import 'package:fluxdo/widgets/layout/adaptive_scaffold.dart';
import 'package:fluxdo/widgets/notification/notification_quick_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('手机端 barVisibility 为 0 时隐藏底部导航栏', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    SharedPreferences.setMockInitialValues({'pref_hide_bar_on_scroll': true});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(barVisibilityProvider.notifier).state = 0;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: AdaptiveScaffold(
              selectedIndex: 1,
              onDestinationSelected: (_) {},
              destinations: const [
                AdaptiveDestination(
                  id: 'home',
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页',
                ),
                AdaptiveDestination(
                  id: 'bookmarks',
                  icon: Icon(Icons.bookmark_outline_rounded),
                  selectedIcon: Icon(Icons.bookmark_rounded),
                  label: '书签',
                ),
              ],
              body: const SizedBox.expand(child: Text('body')),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsNothing);

    container.read(barVisibilityProvider.notifier).state = 1;
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('横屏侧栏通知面板让位宽包含左安全区', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoriesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(900, 500),
              padding: EdgeInsets.only(left: 24),
            ),
            child: AdaptiveScaffold(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const [
                AdaptiveDestination(
                  id: 'home',
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页',
                ),
              ],
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.byType(SidebarNotificationPanel),
        matching: find.byType(Positioned),
      ),
    );
    expect(positioned.left, 24 + 72 + 1);
  });
}
