import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/app_state_refresher.dart';
import 'package:fluxdo/providers/topic_list/tab_state_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('登录调用页卸载后仍使用提前捕获的根容器刷新', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pinned_category_ids': ['1', '2'],
    });
    final preferences = await SharedPreferences.getInstance();

    ProviderContainer? capturedContainer;
    StateSetter? updateHost;
    var showLoginCaller = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              if (!showLoginCaller) return const Text('replacement');
              return Builder(
                builder: (context) {
                  capturedContainer = ProviderScope.containerOf(
                    context,
                    listen: false,
                  );
                  return const Text('login caller');
                },
              );
            },
          ),
        ),
      ),
    );

    final container = capturedContainer!;
    container.read(currentTabCategoryIdProvider.notifier).state = 1;

    updateHost!(() => showLoginCaller = false);
    await tester.pump();
    expect(find.text('login caller'), findsNothing);

    final refresh = AppStateRefresher.refreshAfterRouteTransition(container);
    await tester.pump();
    await refresh;

    expect(container.read(staleTabsProvider), {null, 2});

    // 消化 refreshAll 的延迟刷新，避免计时器越过测试生命周期。
    await tester.pump(const Duration(seconds: 1));
  });
}
