import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/chat_composer_utils.dart';

void main() {
  group('insertChatComposerText', () {
    test('inserts at the saved cursor position', () {
      final result = insertChatComposerText(
        const TextEditingValue(text: '你好世界'),
        ':smile:',
        selection: const TextSelection.collapsed(offset: 2),
      );

      expect(result.text, '你好:smile:世界');
      expect(result.selection, const TextSelection.collapsed(offset: 9));
    });

    test('replaces the selected text', () {
      final result = insertChatComposerText(
        const TextEditingValue(text: 'hello world'),
        ':wave:',
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      );

      expect(result.text, 'hello :wave:');
      expect(result.selection, const TextSelection.collapsed(offset: 12));
    });

    test('appends when the saved selection is no longer valid', () {
      final result = insertChatComposerText(
        const TextEditingValue(text: 'hello'),
        ':wave:',
        selection: const TextSelection.collapsed(offset: 20),
      );

      expect(result.text, 'hello:wave:');
      expect(result.selection, const TextSelection.collapsed(offset: 11));
    });
  });
}
