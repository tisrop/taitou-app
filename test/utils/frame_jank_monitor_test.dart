import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/frame_jank_monitor.dart';

void main() {
  test('非帧构建阶段立即刷新 revision', () {
    FrameJankMonitor.revision.value = 0;

    FrameJankMonitor.clear();

    expect(FrameJankMonitor.revision.value, 1);
  });

  testWidgets('帧构建阶段延迟并合并 revision 刷新', (tester) async {
    FrameJankMonitor.revision.value = 0;
    late int revisionBeforeClear;
    late int revisionDuringBuild;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _RevisionBuildProbe(
          onBuild: (before, during) {
            revisionBeforeClear = before;
            revisionDuringBuild = during;
          },
        ),
      ),
    );

    expect(revisionDuringBuild, revisionBeforeClear);
    expect(FrameJankMonitor.revision.value, revisionBeforeClear + 1);
  });
}

class _RevisionBuildProbe extends StatelessWidget {
  const _RevisionBuildProbe({required this.onBuild});

  final void Function(int before, int during) onBuild;

  @override
  Widget build(BuildContext context) {
    final before = FrameJankMonitor.revision.value;
    FrameJankMonitor.clear();
    FrameJankMonitor.clear();
    onBuild(before, FrameJankMonitor.revision.value);
    return const SizedBox.shrink();
  }
}
