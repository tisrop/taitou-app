import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/png_encoder.dart';

void main() {
  // 内部解码:验证 PNG 字节结构(signature / IHDR / chunk CRC / 双 IDAT-IEND)。
  // 不依赖任何第三方图像库做往返 —— image 包已移除。
  group('PngEncoder 字节结构', () {
    test('PNG signature 正确', () {
      final src = Uint8List.fromList([0, 0, 0, 0]);
      final png = const PngEncoder().encodeRgba(src, 1, 1);
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('IHDR: 宽高 / 色深 / 色彩类型正确', () {
      final src = Uint8List(2 * 3 * 4);
      final png = const PngEncoder().encodeRgba(src, 2, 3);
      // IHDR 紧跟 signature(8)+ length(4) + 'IHDR'(4) = 偏移 16 开始是 13 字节数据
      final ihdr = png.sublist(16, 16 + 13);
      // width(4) height(4) bitdepth(1) colortype(1) compress(1) filter(1) interlace(1)
      expect(_u32(ihdr, 0), 2);
      expect(_u32(ihdr, 4), 3);
      expect(ihdr[8], 8); // bit depth
      expect(ihdr[9], 6); // RGBA
      expect(ihdr[10], 0); // deflate
      expect(ihdr[11], 0); // standard filter
      expect(ihdr[12], 0); // no interlace
    });

    test('包含 IDAT 与 IEND chunk', () {
      final src = Uint8List.fromList([10, 20, 30, 40]);
      final png = const PngEncoder().encodeRgba(src, 1, 1);
      expect(_hasChunkType(png, [73, 68, 65, 84]), isTrue); // 'IDAT'
      expect(_hasChunkType(png, [73, 69, 78, 68]), isTrue); // 'IEND'
    });

    test('每个 chunk 的 CRC32 正确(PNG 解码器会校验)', () {
      final src = Uint8List(4 * 4 * 4);
      for (var i = 0; i < src.length; i++) {
        src[i] = (i * 7) & 0xff;
      }
      final png = const PngEncoder().encodeRgba(src, 4, 4);
      // 遍历所有 chunk,重算 CRC 与文件内 CRC 比较
      var offset = 8; // 跳过 signature
      while (offset < png.length) {
        final length = _u32(png, offset);
        final crcInFile = _u32(png, offset + 8 + length);
        final recomputed = _crc32(png, offset + 4, offset + 8 + length);
        expect(crcInFile, recomputed, reason: 'chunk @ $offset CRC mismatch');
        offset += 12 + length;
      }
    });

    test('长度不足时抛 ArgumentError', () {
      expect(
        () => const PngEncoder().encodeRgba(Uint8List(3), 1, 1),
        throwsArgumentError,
      );
    });
  });
}

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

bool _hasChunkType(Uint8List png, List<int> typeAscii) {
  for (var i = 8; i + 4 <= png.length; i++) {
    if (png[i] == typeAscii[0] &&
        png[i + 1] == typeAscii[1] &&
        png[i + 2] == typeAscii[2] &&
        png[i + 3] == typeAscii[3]) {
      return true;
    }
  }
  return false;
}

int _crc32(Uint8List buf, int start, int end) {
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) {
    crc ^= buf[i];
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
