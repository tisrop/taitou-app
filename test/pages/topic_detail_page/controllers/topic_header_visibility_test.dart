import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/controllers/topic_header_visibility.dart';

void main() {
  test('第一页未加载时不能把中心锚点误判为话题顶部', () {
    expect(
      shouldTreatMissingTopicHeaderAsTop(
        hasFirstPost: false,
        hasScrollClients: true,
        scrollOffset: 0,
        appBarHeight: 80,
      ),
      isFalse,
    );
  });

  test('首帖已加载且偏移位于 AppBar 范围内时视为顶部', () {
    expect(
      shouldTreatMissingTopicHeaderAsTop(
        hasFirstPost: true,
        hasScrollClients: true,
        scrollOffset: 40,
        appBarHeight: 80,
      ),
      isTrue,
    );
  });

  test('列表未挂载或偏移超过 AppBar 时不视为顶部', () {
    expect(
      shouldTreatMissingTopicHeaderAsTop(
        hasFirstPost: true,
        hasScrollClients: false,
        scrollOffset: 0,
        appBarHeight: 80,
      ),
      isFalse,
    );
    expect(
      shouldTreatMissingTopicHeaderAsTop(
        hasFirstPost: true,
        hasScrollClients: true,
        scrollOffset: 81,
        appBarHeight: 80,
      ),
      isFalse,
    );
  });

  test('首帖状态连续为未加载时仍需重新检查标题栏', () {
    expect(
      shouldRecheckMissingTopicHeader(
        previousHasFirstPost: false,
        nextHasFirstPost: false,
      ),
      isTrue,
    );
    expect(
      shouldRecheckMissingTopicHeader(
        previousHasFirstPost: true,
        nextHasFirstPost: true,
      ),
      isFalse,
    );
    expect(
      shouldRecheckMissingTopicHeader(
        previousHasFirstPost: false,
        nextHasFirstPost: true,
      ),
      isFalse,
    );
  });
}
