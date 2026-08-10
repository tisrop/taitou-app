import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/emoji.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/markdown_editor/emoji_autocomplete.dart';

Widget _wrap(Widget child) {
  return TranslationProvider(
    child: MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    ),
  );
}

Emoji _emoji(String name, {List<String> aliases = const []}) {
  return Emoji(
    name: name,
    url: 'https://example.invalid/$name.png',
    group: 'test',
    searchAliases: aliases,
  );
}

void main() {
  test('emoji autocomplete results prefer names and remove duplicates', () {
    final results = filterEmojiAutocompleteResults([
      _emoji('smiley'),
      _emoji('smile'),
      _emoji('heart', aliases: ['smile']),
      _emoji('smiley'),
    ], 'smil');

    expect(results.map((emoji) => emoji.name), ['smile', 'smiley', 'heart']);
  });

  testWidgets('typing :keyword shows candidates and replaces the shortcode', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        EmojiAutocomplete(
          controller: controller,
          focusNode: focusNode,
          debounceMs: 1,
          dataSource: (term) async => [
            if (term == 'smi') _emoji('smile'),
            if (term == 'smi') _emoji('smiley'),
          ],
          child: TextField(controller: controller, focusNode: focusNode),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    controller.value = const TextEditingValue(
      text: 'hello :smi world',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();

    expect(find.text(':smile:'), findsOneWidget);
    expect(find.text(':smiley:'), findsOneWidget);

    await tester.tap(find.text(':smile:'));
    await tester.pump();

    expect(controller.text, 'hello :smile: world');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
    expect(find.text(':smiley:'), findsNothing);
  });

  testWidgets('does not trigger inside a word or for a bare colon', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var calls = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        EmojiAutocomplete(
          controller: controller,
          focusNode: focusNode,
          debounceMs: 1,
          dataSource: (_) async {
            calls++;
            return [_emoji('smile')];
          },
          child: TextField(controller: controller, focusNode: focusNode),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    controller.value = const TextEditingValue(
      text: 'time:sm',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pump(const Duration(milliseconds: 2));
    expect(calls, 0);
    expect(find.text(':smile:'), findsNothing);

    controller.value = const TextEditingValue(
      text: 'time: ',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump(const Duration(milliseconds: 2));
    expect(calls, 0);
    expect(find.text(':smile:'), findsNothing);
  });

  testWidgets('arrow keys and enter select the highlighted emoji', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        EmojiAutocomplete(
          controller: controller,
          focusNode: focusNode,
          debounceMs: 1,
          dataSource: (_) async => [_emoji('smile'), _emoji('smiley')],
          child: TextField(controller: controller, focusNode: focusNode),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    controller.value = const TextEditingValue(
      text: ':smi',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, ':smiley:');
  });
}
