import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/chat/chat_channel.dart';
import 'package:fluxdo/models/chat/chat_message.dart';
import 'package:fluxdo/pages/chat_page.dart';
import 'package:fluxdo/providers/chat/chat_channel_list_provider.dart';

class _TestChatChannelListNotifier extends ChatChannelListNotifier {
  _TestChatChannelListNotifier(this.initialValue);

  final ChatChannelIndex initialValue;

  @override
  Future<ChatChannelIndex> build() async => initialValue;

  void applyFetchedIndex(ChatChannelIndex index) {
    state = AsyncData(mergeFetchedIndex(index));
  }
}

class _DeferredChatChannelListNotifier extends ChatChannelListNotifier {
  _DeferredChatChannelListNotifier(this.initialValue);

  final Future<ChatChannelIndex> initialValue;

  @override
  Future<ChatChannelIndex> build() async {
    return mergeFetchedIndex(await initialValue);
  }
}

class _EventuallyVisibleChatChannelListNotifier
    extends _TestChatChannelListNotifier {
  _EventuallyVisibleChatChannelListNotifier(super.initialValue);

  int refreshCount = 0;

  @override
  List<Duration> get channelVisibilityRetryDelays => const [
    Duration.zero,
    Duration.zero,
    Duration.zero,
  ];

  @override
  Future<ChatChannelIndex?> refreshSilently() async {
    refreshCount++;
    if (refreshCount < 3) return initialValue;
    return ChatChannelIndex(
      publicChannels: initialValue.publicChannels,
      directMessageChannels: const [
        ChatChannel(id: 9, title: '小张', chatableType: 'DirectMessage'),
      ],
    );
  }
}

void main() {
  testWidgets('频道最后消息时间按今天、近 7 天和更早日期显示', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(alwaysUse24HourFormat: true),
            child: Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    final now = DateTime(2026, 7, 2, 16);

    expect(
      formatChatChannelLastMessageTime(
        context,
        DateTime(2026, 7, 2, 14, 5),
        now: now,
      ),
      '14:05',
    );
    expect(
      formatChatChannelLastMessageTime(
        context,
        DateTime(2026, 6, 30, 9),
        now: now,
      ),
      '星期二',
    );
    expect(
      formatChatChannelLastMessageTime(
        context,
        DateTime(2026, 6, 20, 9),
        now: now,
      ),
      '2026/6/20',
    );
    expect(formatChatChannelLastMessageTime(context, null, now: now), isEmpty);
  });

  testWidgets('频道列表在右侧展示最后一条消息时间', (tester) async {
    final messageTime = DateTime.now().subtract(const Duration(minutes: 10));
    final index = ChatChannelIndex(
      publicChannels: [
        ChatChannel(
          id: 1,
          title: 'General',
          chatableType: 'Category',
          lastMessage: ChatMessage(
            id: 10,
            message: 'hello',
            createdAt: messageTime,
            chatChannelId: 1,
            user: const ChatMessageUser(id: 2, username: 'alice'),
          ),
        ),
        const ChatChannel(id: 2, title: '无消息频道', chatableType: 'Category'),
      ],
      directMessageChannels: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatChannelListProvider.overrideWith(
            () => _TestChatChannelListNotifier(index),
          ),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: const ChatPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(ChatPage));
    final expectedTime = formatChatChannelLastMessageTime(
      pageContext,
      messageTime,
    );
    expect(find.text(expectedTime), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('无消息频道'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });

  test('删除直接消息后只从本地频道列表移除目标频道', () async {
    const index = ChatChannelIndex(
      publicChannels: [
        ChatChannel(id: 1, title: '公共频道', chatableType: 'Category'),
      ],
      directMessageChannels: [
        ChatChannel(id: 2, title: '小张', chatableType: 'DirectMessage'),
        ChatChannel(id: 3, title: '小李', chatableType: 'DirectMessage'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        chatChannelListProvider.overrideWith(
          () => _TestChatChannelListNotifier(index),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatChannelListProvider.future);

    container.read(chatChannelListProvider.notifier).removeChannel(2);

    final updated = container.read(chatChannelListProvider).requireValue;
    expect(updated.publicChannels.map((channel) => channel.id), [1]);
    expect(updated.directMessageChannels.map((channel) => channel.id), [3]);
  });

  test('服务端目录尚未收录时保留已发布的直接消息', () async {
    const serverIndex = ChatChannelIndex(
      publicChannels: [
        ChatChannel(id: 1, title: '公共频道', chatableType: 'Category'),
      ],
      directMessageChannels: [],
    );
    const directMessage = ChatChannel(
      id: 9,
      title: '小张',
      chatableType: 'DirectMessage',
    );
    late _TestChatChannelListNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        chatChannelListProvider.overrideWith(
          () => notifier = _TestChatChannelListNotifier(serverIndex),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatChannelListProvider.future);

    notifier.upsertChannel(directMessage);
    notifier.applyFetchedIndex(serverIndex);

    final updated = container.read(chatChannelListProvider).requireValue;
    expect(updated.publicChannels.map((channel) => channel.id), [1]);
    expect(updated.directMessageChannels.map((channel) => channel.id), [9]);
  });

  test('初始目录加载期间发布的直接消息不会被迟到响应覆盖', () async {
    const serverIndex = ChatChannelIndex(
      publicChannels: [
        ChatChannel(id: 1, title: '公共频道', chatableType: 'Category'),
      ],
      directMessageChannels: [],
    );
    const directMessage = ChatChannel(
      id: 9,
      title: '小张',
      chatableType: 'DirectMessage',
    );
    final initialResponse = Completer<ChatChannelIndex>();
    final merged = Completer<ChatChannelIndex>();
    final container = ProviderContainer(
      overrides: [
        chatChannelListProvider.overrideWith(
          () => _DeferredChatChannelListNotifier(initialResponse.future),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(chatChannelListProvider, (_, next) {
      final index = next.value;
      if (index != null &&
          index.publicChannels.any((channel) => channel.id == 1) &&
          index.directMessageChannels.any((channel) => channel.id == 9) &&
          !merged.isCompleted) {
        merged.complete(index);
      }
    });
    addTearDown(subscription.close);

    container
        .read(chatChannelListProvider.notifier)
        .upsertChannel(directMessage);
    expect(
      container
          .read(chatChannelListProvider)
          .requireValue
          .directMessageChannels
          .single
          .id,
      9,
    );

    initialResponse.complete(serverIndex);
    final updated = await merged.future;
    expect(updated.publicChannels.map((channel) => channel.id), [1]);
    expect(updated.directMessageChannels.map((channel) => channel.id), [9]);
  });

  test('首条消息发布后重试直到服务端目录确认直接消息', () async {
    const serverIndex = ChatChannelIndex(
      publicChannels: [],
      directMessageChannels: [],
    );
    late _EventuallyVisibleChatChannelListNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        chatChannelListProvider.overrideWith(
          () =>
              notifier = _EventuallyVisibleChatChannelListNotifier(serverIndex),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatChannelListProvider.future);

    final visible = await notifier.refreshUntilChannelVisible(9);

    expect(visible, isTrue);
    expect(notifier.refreshCount, 3);
  });

  testWidgets('直接消息支持左滑删除，公开频道不可滑动删除', (tester) async {
    const index = ChatChannelIndex(
      publicChannels: [
        ChatChannel(id: 1, title: '公共频道', chatableType: 'Category'),
      ],
      directMessageChannels: [
        ChatChannel(id: 2, title: '小张', chatableType: 'DirectMessage'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatChannelListProvider.overrideWith(
            () => _TestChatChannelListNotifier(index),
          ),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            home: const ChatPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsOneWidget);
    expect(
      find.ancestor(of: find.text('公共频道'), matching: find.byType(Dismissible)),
      findsNothing,
    );

    final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
    expect(dismissible.direction, DismissDirection.endToStart);

    await tester.drag(find.text('小张'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除对话'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('确定要从直接消息列表中删除“小张”吗？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('小张'), findsOneWidget);
  });
}
