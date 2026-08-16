import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/chat/chat_channel.dart';
import 'package:fluxdo/models/chat/chat_message.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/chat_channel_page.dart';
import 'package:fluxdo/providers/chat/chat_channel_list_provider.dart';
import 'package:fluxdo/providers/chat/chat_list_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';

class _TestChatListNotifier extends ChatListNotifier {
  _TestChatListNotifier(
    super.channelId, {
    this.initialState = const ChatListState(isLoading: false),
  });

  final ChatListState initialState;
  final List<int> markedReadMessageIds = [];

  @override
  ChatListState build() => initialState;

  @override
  Future<void> send(String text, {ChatMessage? inReplyTo}) async {
    final nextId = state.messages.isEmpty ? 1 : state.messages.last.id + 1;
    state = state.copyWith(messages: [...state.messages, _message(nextId)]);
  }

  @override
  Future<void> markReadThrough(int messageId) async {
    markedReadMessageIds.add(messageId);
  }

  void emitMessage(ChatMessage message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }
}

class _LoadingChatListNotifier extends ChatListNotifier {
  _LoadingChatListNotifier(super.channelId);

  @override
  ChatListState build() => const ChatListState();
}

class _TestChatChannelListNotifier extends ChatChannelListNotifier {
  _TestChatChannelListNotifier(this.initialValue);

  final ChatChannelIndex initialValue;

  @override
  Future<ChatChannelIndex> build() async => initialValue;
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}

class _TestCurrentUserNotifier extends CurrentUserNotifier {
  _TestCurrentUserNotifier(this.initialUser);

  final User? initialUser;

  @override
  FutureOr<User?> build() => initialUser;
}

void main() {
  testWidgets('空的一对一直接消息展示对话对象和专属输入提示', (tester) async {
    const channel = ChatChannel(
      id: 12,
      title: '彭于晏',
      chatableType: 'DirectMessage',
      directMessageUsers: [
        ChatMessageUser(
          id: 2,
          username: 'eddie',
          name: '彭于晏',
          avatarTemplate: '',
        ),
      ],
    );

    await tester.pumpWidget(_testApp(channel));
    await tester.pumpAndSettle();

    expect(find.text('你是 #彭于晏 中的第一个用户'), findsOneWidget);
    expect(find.text('抢先发言，开启对话。'), findsOneWidget);
    expect(find.text('1 个用户在这里'), findsOneWidget);
    expect(find.text('还没有消息，来发第一条吧'), findsNothing);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, '与 @eddie 聊天');
  });

  testWidgets('直接会话头像用户名入口打开频道详情和成员页', (tester) async {
    const channel = ChatChannel(
      id: 15,
      title: '彭于晏',
      chatableType: 'DirectMessage',
      membershipsCount: 1,
      threadingEnabled: true,
      currentUserMembership: ChatChannelMembership(
        following: true,
        muted: false,
        notificationLevel: ChatChannelNotificationLevel.always,
      ),
      directMessageUsers: [
        ChatMessageUser(
          id: 2,
          username: 'eddie',
          name: '彭于晏',
          avatarTemplate: '',
        ),
      ],
    );

    final navigatorObserver = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      _testApp(
        channel,
        navigatorObservers: [navigatorObserver],
        currentUser: User(
          id: 1,
          username: 'current-user',
          name: '当前用户',
          avatarTemplate: '',
          trustLevel: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final detailsTrigger = find.byKey(
      const ValueKey('chat-channel-details-trigger'),
    );
    expect(detailsTrigger, findsOneWidget);

    await tester.tap(detailsTrigger);
    await tester.pumpAndSettle();

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('将频道设为免打扰'), findsOneWidget);
    expect(find.text('发送推送通知'), findsOneWidget);
    expect(find.text('所有活动'), findsOneWidget);
    expect(find.text('启用消息串'), findsOneWidget);
    expect(find.text('频道信息'), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('无限期'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-channel-members-entry')));
    await tester.pumpAndSettle();

    expect(find.text('当前用户'), findsOneWidget);
    expect(find.text('@current-user'), findsOneWidget);
    expect(find.text('彭于晏'), findsOneWidget);
    expect(find.text('@eddie'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-channel-member-eddie')));

    expect(navigatorObserver.lastPushedRoute?.settings.name, '/u/eddie');
    expect(navigatorObserver.lastPushedRoute?.settings.arguments, 'eddie');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('删除对话'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('删除对话'), findsOneWidget);
  });

  testWidgets('新建私聊加载历史期间立即显示可交互空状态', (tester) async {
    const channel = ChatChannel(
      id: 14,
      title: '彭于晏',
      chatableType: 'DirectMessage',
      directMessageUsers: [
        ChatMessageUser(id: 2, username: 'eddie', name: '彭于晏'),
      ],
    );

    await tester.pumpWidget(_testApp(channel, loadingChatList: true));
    await tester.pump();

    expect(find.text('抢先发言，开启对话。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('发送消息后反向列表回到最新消息', (tester) async {
    const channel = ChatChannel(id: 16, title: '长频道', chatableType: 'Category');
    final notifier = _TestChatListNotifier(
      channel.id,
      initialState: ChatListState(
        messages: List.generate(40, (index) => _message(index + 1)),
        isLoading: false,
      ),
    );

    await tester.pumpWidget(_testApp(channel, chatListNotifier: notifier));
    await tester.pumpAndSettle();

    final position = _messageListPosition(tester);
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '新消息');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(position.pixels, closeTo(position.minScrollExtent, 1));
  });

  testWidgets('仅在频道前台且位于最新消息附近时上报实时消息已读', (tester) async {
    const channel = ChatChannel(
      id: 17,
      title: '实时频道',
      chatableType: 'Category',
    );
    final notifier = _TestChatListNotifier(
      channel.id,
      initialState: ChatListState(
        messages: List.generate(40, (index) => _message(index + 1)),
        isLoading: false,
      ),
    );

    await tester.pumpWidget(_testApp(channel, chatListNotifier: notifier));
    await tester.pumpAndSettle();
    notifier.markedReadMessageIds.clear();

    notifier.emitMessage(_message(41));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, contains(41));

    final position = _messageListPosition(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    notifier.markedReadMessageIds.clear();

    notifier.emitMessage(_message(42));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, isNot(contains(42)));

    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, contains(42));

    notifier.markedReadMessageIds.clear();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      ),
    );
    await tester.pumpAndSettle();

    notifier.emitMessage(_message(43));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, isNot(contains(43)));

    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, contains(43));

    notifier.markedReadMessageIds.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    notifier.emitMessage(_message(44));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, isNot(contains(44)));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.markedReadMessageIds, contains(44));
  });

  testWidgets('空的公开频道继续展示通用空状态和输入提示', (tester) async {
    const channel = ChatChannel(
      id: 13,
      title: '站务讨论',
      chatableType: 'Category',
    );

    await tester.pumpWidget(_testApp(channel));
    await tester.pumpAndSettle();

    expect(find.text('还没有消息，来发第一条吧'), findsOneWidget);
    expect(find.textContaining('第一个用户'), findsNothing);
    expect(
      find.byKey(const ValueKey('chat-channel-details-trigger')),
      findsNothing,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, '输入消息…');
  });
}

Widget _testApp(
  ChatChannel channel, {
  bool loadingChatList = false,
  _TestChatListNotifier? chatListNotifier,
  User? currentUser,
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  final index = ChatChannelIndex(
    publicChannels: channel.isDirectMessage ? const [] : [channel],
    directMessageChannels: channel.isDirectMessage ? [channel] : const [],
  );

  return ProviderScope(
    overrides: [
      !loadingChatList
          ? chatListProvider(channel.id).overrideWith(
              () => chatListNotifier ?? _TestChatListNotifier(channel.id),
            )
          : chatListProvider(
              channel.id,
            ).overrideWith(() => _LoadingChatListNotifier(channel.id)),
      chatChannelListProvider.overrideWith(
        () => _TestChatChannelListNotifier(index),
      ),
      currentUserProvider.overrideWith(
        () => _TestCurrentUserNotifier(currentUser),
      ),
    ],
    child: TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        navigatorObservers: navigatorObservers,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: ChatChannelPage(
          channelId: channel.id,
          title: channel.title,
          channel: channel,
        ),
      ),
    ),
  );
}

ChatMessage _message(int id) {
  return ChatMessage(
    id: id,
    message: '消息 $id',
    createdAt: DateTime.utc(2026, 1, 1, 0, id),
    chatChannelId: 1,
    user: const ChatMessageUser(id: 2, username: 'other-user'),
  );
}

ScrollPosition _messageListPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  return tester.state<ScrollableState>(scrollable).position;
}
