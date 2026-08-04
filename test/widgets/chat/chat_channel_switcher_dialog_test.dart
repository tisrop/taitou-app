import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/chat/chat_channel_switcher_dialog.dart';

void main() {
  test('选择一名其他成员时创建一对一直接消息', () {
    expect(
      directMessageConversationTypeFor(1),
      DirectMessageConversationType.oneToOne,
    );
  });

  test('未选择其他成员时不能创建直接消息', () {
    expect(directMessageConversationTypeFor(0), isNull);
  });

  test('选择多名其他成员时创建群聊', () {
    expect(
      directMessageConversationTypeFor(2),
      DirectMessageConversationType.group,
    );
  });
}
