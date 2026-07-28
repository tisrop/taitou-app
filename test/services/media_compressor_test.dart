/// Android 媒体压缩策略层：验证码率预算与递降档位。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/media_transcoder/media_compressor.dart';

void main() {
  group('码率预算(脚本同款)', () {
    test('音频:60s 文件预算充裕 → 三档递降且钳 12k..96k', () {
      final tiers = audioProfilesFor(const Duration(seconds: 60));
      // budget = (4MB-96KB)*8/60 ≈ 546k → 0.72 档钳到 96k
      expect(tiers[0].audioBitrate, 96000);
      expect(tiers[1].audioBitrate, 96000, reason: '0.45 档 245k 仍触顶');
      expect(tiers[2].audioBitrate, 96000, reason: '0.28 档 152k 仍触顶');
      // 超长音频(1 小时):预算 9.1k → 全档触底 12k
      final long = audioProfilesFor(const Duration(hours: 1));
      expect(long.every((t) => t.audioBitrate == 12000), isTrue);
    });

    test('视频四档:HEVC 优先两档 + H264 兜底两档,码率递降', () {
      final tiers = videoProfilesFor(const Duration(minutes: 5));
      expect(tiers.map((t) => t.codec).toList(), [
        'hevc',
        'hevc',
        'h264',
        'h264',
      ]);
      expect(tiers[0].audioBitrate, 24000);
      expect(tiers[0].videoBitrate, greaterThan(tiers[1].videoBitrate));
      expect(
        tiers[1].videoBitrate,
        tiers[2].videoBitrate,
        reason: '同 0.66 折扣,仅 codec 不同',
      );
      expect(tiers[3].videoBitrate, greaterThanOrEqualTo(12000));
    });

    test('短视频预算高 → HEVC 720p 起步;HEVC 分辨率阈值放宽', () {
      final tiers = videoProfilesFor(const Duration(seconds: 30));
      expect(tiers[0].audioBitrate, 32000);
      expect(tiers[0].codec, 'hevc');
      expect(tiers[0].height, 720);
      expect(tiers[0].fps, 30);
      // 第二档 hevc ≈ 0.66*1.06M ≈ 700k:除 0.65 折算 >900k → 仍 720p;
      // 同码率的 h264 档(第三档)只到 480p —— 阈值放宽生效
      expect(tiers[1].height, 720);
      expect(tiers[2].height, 480);
    });
  });
}
