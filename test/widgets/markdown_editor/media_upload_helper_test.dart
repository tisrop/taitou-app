/// 媒体改名上传 helper:short-url 播放路径换算与标签生成。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/media_upload_helper.dart';

void main() {
  group('附件扩展名白名单', () {
    test('普通用户只使用站点基础白名单并规范化格式', () {
      final extensions = deriveAttachmentAllowedExtensions(
        siteSettings: {
          'authorized_extensions': ' JPG | .pdf | zip | jpg ',
          'authorized_extensions_for_staff': 'apk|aab',
        },
        currentUser: {'admin': false, 'moderator': false},
      );

      expect(extensions, ['jpg', 'pdf', 'zip']);
    });

    test('staff 合并专属白名单并去重', () {
      final extensions = deriveAttachmentAllowedExtensions(
        siteSettings: {
          'authorized_extensions': 'jpg|pdf',
          'authorized_extensions_for_staff': 'pdf|apk|aab',
        },
        currentUser: {'moderator': true},
      );

      expect(extensions, ['jpg', 'pdf', 'apk', 'aab']);
    });

    test('当前用户可用名单包含通配符时不限制文件选择器', () {
      expect(
        deriveAttachmentAllowedExtensions(
          siteSettings: {'authorized_extensions': '*'},
          currentUser: null,
        ),
        isNull,
      );
      expect(
        deriveAttachmentAllowedExtensions(
          siteSettings: {
            'authorized_extensions': 'jpg|pdf',
            'authorized_extensions_for_staff': '*',
          },
          currentUser: {'admin': true},
        ),
        isNull,
      );
    });

    test('非 staff 忽略 staff 通配符，配置缺失时交给服务端校验', () {
      expect(
        deriveAttachmentAllowedExtensions(
          siteSettings: {
            'authorized_extensions': 'jpg|pdf',
            'authorized_extensions_for_staff': '*',
          },
          currentUser: {'admin': false, 'moderator': false},
        ),
        ['jpg', 'pdf'],
      );
      expect(
        deriveAttachmentAllowedExtensions(
          siteSettings: null,
          currentUser: null,
        ),
        isNull,
      );
    });
  });

  test('upload:// 短链 → /uploads/short-url/<b62>.xz(去原扩展)', () {
    expect(
      mediaShortUrlToXzPath('upload://lwDn83PDeB3xOUoEeZI9v77qGJa.mp4'),
      '/uploads/short-url/lwDn83PDeB3xOUoEeZI9v77qGJa.xz',
    );
    expect(
      mediaShortUrlToXzPath('upload://abc'),
      '/uploads/short-url/abc.xz',
    );
    // 非短链兜底:仅换扩展
    expect(
      mediaShortUrlToXzPath('/uploads/default/original/1X/a.mp3'),
      '/uploads/default/original/1X/a.xz',
    );
  });

  test('audio 标签形态(脚本 makeTag 同款)', () {
    expect(
      buildMediaTag(
        isAudio: true,
        srcPath: '/uploads/short-url/abc.xz',
        mime: 'audio/mpeg',
      ),
      '<audio controls>\n'
      '  <source src="/uploads/short-url/abc.xz" type="audio/mpeg">\n'
      '</audio>',
    );
  });

  test('语音消息包 [wrap=voice] 壳', () {
    final tag = buildMediaTag(
      isAudio: true,
      srcPath: '/uploads/short-url/abc.xz',
      mime: 'audio/mp4',
      voice: true,
    );
    expect(tag, startsWith('[wrap=voice]\n<audio controls>'));
    expect(tag, endsWith('[/wrap]'));
  });

  test('video 标签带默认宽高', () {
    final tag = buildMediaTag(
      isAudio: false,
      srcPath: '/uploads/short-url/xyz.xz',
      mime: 'video/mp4',
    );
    expect(tag, contains('<video width="640" height="360" controls>'));
    expect(tag,
        contains('<source src="/uploads/short-url/xyz.xz" type="video/mp4">'));
  });
}
