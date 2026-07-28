import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/constants.dart';
import 'package:fluxdo/services/clipboard_topic_link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ClipboardTopicLinkService.instance;

  tearDown(() {
    service.clearSeenForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ClipboardTopicLinkService.findFirstTopicLink', () {
    test('识别支持的话题链接格式', () {
      final cases = <String, String>{
        '${AppConstants.baseUrl}/t/123': '${AppConstants.baseUrl}/t/123',
        '${AppConstants.baseUrl}/t/123/5': '${AppConstants.baseUrl}/t/123/5',
        '${AppConstants.baseUrl}/t/topic-slug/123':
            '${AppConstants.baseUrl}/t/topic-slug/123',
        '${AppConstants.baseUrl}/t/topic-slug/123/5':
            '${AppConstants.baseUrl}/t/topic-slug/123/5',
      };

      for (final entry in cases.entries) {
        final candidate = service.findFirstTopicLink(entry.key);

        expect(candidate, isNotNull);
        expect(candidate!.normalizedUrl, entry.value);
        expect(candidate.uri.toString(), entry.value);
      }
    });

    test('从任意文本中提取第一个有效话题链接', () {
      final candidate = service.findFirstTopicLink(
        '先忽略 https://openxinsheng.com/u/user，再打开 https://openxinsheng.com/t/first/101 和 https://openxinsheng.com/t/second/202',
      );

      expect(candidate, isNotNull);
      expect(candidate!.normalizedUrl, '${AppConstants.baseUrl}/t/first/101');
    });

    test('保留 query 和 fragment，并统一 scheme 与 host 大小写', () {
      final candidate = service.findFirstTopicLink(
        '看看 HTTPS://WWW.OPENXINSHENG.COM:443/t/topic-slug/123/5?foo=Bar#post_5.',
      );

      expect(candidate, isNotNull);
      expect(
        candidate!.normalizedUrl,
        'https://www.openxinsheng.com/t/topic-slug/123/5?foo=Bar#post_5',
      );
    });

    test('支持无 scheme 的本站链接', () {
      final candidate = service.findFirstTopicLink('openxinsheng.com/t/123、');

      expect(candidate, isNotNull);
      expect(candidate!.normalizedUrl, '${AppConstants.baseUrl}/t/123');
    });

    test('用户页、登录链接、普通页面、非本站域名不触发', () {
      final invalidTexts = <String>[
        'https://openxinsheng.com/u/user',
        'https://openxinsheng.com/session/email-login/token',
        'https://openxinsheng.com/latest',
        'https://example.com/t/123',
        'https://not-openxinsheng.com/t/123',
        'https://meta.openxinsheng.com/t/123',
        'https://example.com/openxinsheng.com/t/123',
        'https://example.com/?next=https://openxinsheng.com/t/123',
        'https://example.com/?a=1&next=https://openxinsheng.com/t/123',
        'https://example.com/?next=(https://openxinsheng.com/t/123)',
        'https://example.com/?next=foo:https://openxinsheng.com/t/123',
        'mailto:openxinsheng.com/t/123',
        'foo:openxinsheng.com/t/123/5',
        'https://openxinsheng.com/t/topic-slug',
        'https://openxinsheng.com/t/123/not-post-number',
        'https://openxinsheng.com/t/topic-slug/123/not-post-number',
      ];

      for (final text in invalidTexts) {
        expect(service.findFirstTopicLink(text), isNull, reason: text);
      }
    });
  });

  group('ClipboardTopicLinkService.checkClipboard', () {
    test('enabled 为 false 时不读取剪贴板', () async {
      var readCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              readCount++;
              return <String, dynamic>{'text': '${AppConstants.baseUrl}/t/123'};
            }
            return null;
          });

      final candidate = await service.checkClipboard(enabled: false);

      expect(candidate, isNull);
      expect(readCount, 0);
    });

    test('找到有效新链接后不会在展示前记录 hash', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{
                'text': 'https://openxinsheng.com:443/t/123',
              };
            }
            return null;
          });

      final first = await service.checkClipboard(enabled: true);
      final second = await service.checkClipboard(enabled: true);

      expect(first, isNotNull);
      expect(first!.normalizedUrl, '${AppConstants.baseUrl}/t/123');
      expect(second, isNotNull);
      expect(second!.normalizedHash, first.normalizedHash);
    });

    test('标记已提示后，同一规范化链接再次检查返回 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{
                'text': 'https://openxinsheng.com:443/t/123',
              };
            }
            return null;
          });

      final first = await service.checkClipboard(enabled: true);
      expect(first, isNotNull);
      await service.markPrompted(first!);

      final second = await service.checkClipboard(enabled: true);

      expect(first.normalizedUrl, '${AppConstants.baseUrl}/t/123');
      expect(second, isNull);
    });

    test('传入已持久化的 hash 时不重复返回同一链接', () async {
      final known = service.findFirstTopicLink('${AppConstants.baseUrl}/t/123');
      expect(known, isNotNull);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{
                'text': 'https://openxinsheng.com:443/t/123',
              };
            }
            return null;
          });

      final candidate = await service.checkClipboard(
        enabled: true,
        lastPromptedHash: known!.normalizedHash,
      );

      expect(candidate, isNull);
    });

    test('标记已提示时写入持久化 hash', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final candidate = service.findFirstTopicLink(
        '${AppConstants.baseUrl}/t/123',
      );
      expect(candidate, isNotNull);

      await service.markPrompted(candidate!, prefs: prefs);

      expect(
        prefs.getInt(ClipboardTopicLinkService.lastPromptedHashPrefsKey),
        candidate.normalizedHash,
      );
    });

    test('读取剪贴板失败时返回 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              throw PlatformException(code: 'clipboard-error');
            }
            return null;
          });

      final candidate = await service.checkClipboard(enabled: true);

      expect(candidate, isNull);
    });
  });
}
