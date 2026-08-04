import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/chat/chat_message.dart';
import 'package:fluxdo/pages/chat_search_page.dart';

void main() {
  ChatMessage message({required String raw, String? cooked}) => ChatMessage(
    id: 1,
    message: raw,
    cooked: cooked,
    chatChannelId: 7,
    user: const ChatMessageUser(id: 3, username: 'alice'),
  );

  testWidgets('公共搜索使用单标题和紧凑顶部布局', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: TranslationProvider(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: const ChatSearchPage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('搜索聊天'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TextField)).dy, lessThan(130));
  });

  test('公共搜索将 GIF Markdown 转换为可渲染的图片 HTML', () {
    final html = chatSearchMessageRenderedHtml(
      message(
        raw: r'![Greetings: Man Waving Hello](https://static.klipy.com/a.gif)',
      ),
    );

    expect(html, contains('<img'));
    expect(html, contains('https://static.klipy.com/a.gif'));
    expect(chatSearchContentImageHtml(html), contains('<img'));
  });

  test('公共搜索将 shortcode 表情转换为可渲染的 emoji 图片', () {
    final html = chatSearchMessageRenderedHtml(
      message(raw: ':globe_showing_europe_africa:'),
    );

    expect(html, contains('<img'));
    expect(chatSearchEmojiHtml(html), contains('emoji'));
  });

  test('公共搜索优先使用服务端 cooked 图片内容', () {
    const cooked = '<p><img src="https://example.com/original.png"></p>';

    final html = chatSearchMessageRenderedHtml(
      message(
        raw: '![thumbnail](https://example.com/thumbnail.png)',
        cooked: cooked,
      ),
    );

    expect(html, cooked);
  });

  test('公共搜索不把 emoji 图片当成正文图片缩略图', () {
    const cooked =
        '<p><img src="/images/emoji/twemoji/earth_africa.png" '
        'class="emoji only-emoji" alt=":earth_africa:"></p>';

    expect(chatSearchContentImageHtml(cooked), isNull);
    expect(chatSearchEmojiHtml(cooked), contains('earth_africa'));
  });

  test('公共搜索缩略图只保留第一张正文图片', () {
    const cooked =
        '<p>hello</p>'
        '<p><img src="https://example.com/first.gif"></p>'
        '<p><img src="https://example.com/second.png"></p>';

    final imageHtml = chatSearchContentImageHtml(cooked);

    expect(imageHtml, contains('first.gif'));
    expect(imageHtml, isNot(contains('second.png')));
    expect(imageHtml, isNot(contains('hello')));
  });
}
