import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/responsive.dart';
import 'package:fluxdo/widgets/user/user_profile_skeleton.dart';

void main() {
  Future<void> pumpSkeleton(
    WidgetTester tester, {
    required double width,
    double height = 600,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: UserProfileSkeleton()));
  }

  testWidgets('759px 使用竖版骨架屏', (tester) async {
    await pumpSkeleton(tester, width: 759);

    expect(
      find.byKey(const ValueKey('user-profile-skeleton-narrow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('user-profile-skeleton-wide')),
      findsNothing,
    );
  });

  testWidgets('760px 切换到宽版并固定资料栏宽度', (tester) async {
    await pumpSkeleton(tester, width: 760);

    expect(
      find.byKey(const ValueKey('user-profile-skeleton-wide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('user-profile-skeleton-narrow')),
      findsNothing,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('user-profile-skeleton-info-panel')),
          )
          .width,
      UserProfileWideLayout.infoPanelWidth,
    );
  });

  testWidgets('宽版在短高度横屏下不溢出', (tester) async {
    await pumpSkeleton(tester, width: 760, height: 320);

    expect(
      find.byKey(const ValueKey('user-profile-skeleton-wide')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
