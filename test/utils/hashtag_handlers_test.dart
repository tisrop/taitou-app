import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/pages/category_topics_page.dart';
import 'package:fluxdo/pages/tag_topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/utils/font_awesome_helper.dart';
import 'package:fluxdo/utils/hashtag_handlers.dart';
import 'package:fluxdo/utils/tag_icon_list.dart';
import 'package:fluxdo_render/fluxdo_render.dart'
    show hashtagIconResolver, hashtagTapHandler;

class _RecordingNavigatorObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  final parent = Category(
    id: 2,
    name: '开发',
    color: '000000',
    textColor: 'FFFFFF',
    slug: 'dev',
    icon: 'brain',
  );
  final child = Category(
    id: 4,
    name: '调优',
    color: '000000',
    textColor: 'FFFFFF',
    slug: 'tuning',
    parentCategoryId: 2,
  );

  tearDown(() {
    hashtagIconResolver = null;
    hashtagTapHandler = null;
  });

  testWidgets('分类继承父图标，标签读取 TagIconList', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryMapProvider.overrideWith(
            (_) => AsyncValue.data({2: parent, 4: child}),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    installHashtagHandlers();

    expect(
      hashtagIconResolver!(context, 'square-full', '/c/dev/tuning/4'),
      FontAwesomeHelper.getIcon('brain')?.data,
    );
    expect(
      hashtagIconResolver!(context, null, '/tag/人工智能'),
      TagIconList.get('人工智能')?.icon.data,
    );
    expect(hashtagIconResolver!(context, 'square-full', '/unknown'), isNull);
  });

  testWidgets('分类和中文标签点击压入对应本地页面', (tester) async {
    final observer = _RecordingNavigatorObserver();
    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryMapProvider.overrideWith(
            (_) => AsyncValue.data({2: parent, 4: child}),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    installHashtagHandlers();

    expect(
      hashtagTapHandler!(context, '/c/dev/tuning/4', 'tuning', '调优'),
      isTrue,
    );
    final categoryRoute = observer.routes.last as MaterialPageRoute<void>;
    final categoryPage = categoryRoute.builder(context) as CategoryTopicsPage;
    expect(categoryPage.category, same(child));

    expect(
      hashtagTapHandler!(context, '/tag/123-tag', '人工智能::tag', '人工智能'),
      isTrue,
    );
    final tagRoute = observer.routes.last as MaterialPageRoute<void>;
    final tagPage = tagRoute.builder(context) as TagTopicsPage;
    expect(tagPage.tagName, '人工智能');

    final routeCount = observer.routes.length;
    expect(hashtagTapHandler!(context, '/unknown', null, 'unknown'), isFalse);
    expect(observer.routes, hasLength(routeCount));
  });
}
