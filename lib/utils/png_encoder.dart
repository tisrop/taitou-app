import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// 极简 RGBA8888 → PNG 编码器。
///
/// 替代 `package:image` 在 [ScreenshotUtils] 分块截图拼接场景下的唯一用途:
/// 把一份原始 RGBA8888 像素缓冲编码为合法 PNG 字节。
///
/// 实现只覆盖该场景所需的子集:
/// - 固定 8 位色深、RGBA 四通道、单张静态图;
/// - 单一 IDAT chunk,用 [ZLibCodec](zlib,等同 image 包内部 zlib 压缩)压缩;
/// - 每行前置 filter type 0(None),逐行写入;
/// - CRC32 自带实现(不依赖 dart:io 的内部)。
///
/// 不实现 interlace / palette / 非 RGBA 色彩类型 —— screenshot 路径用不到。
class PngEncoder {
  const PngEncoder();

  /// 压缩等级,默认 6(zlib 默认,与 image 包 encodePng 一致)。
  final int level = 6;

  /// 将 [width]×[height] 的 RGBA8888 像素([pixels] 长度须 = width*height*4)
  /// 编码为 PNG 字节序列。
  Uint8List encodeRgba(Uint8List pixels, int width, int height) {
    if (pixels.length < width * height * 4) {
      throw ArgumentError(
        'pixels length ${pixels.length} < width*height*4 (${width * height * 4})',
      );
    }

    // 1) 行扫描数据:每行前加 1 字节 filter type 0(None)。
    final rowBytes = width * 4;
    final raw = Uint8List((rowBytes + 1) * height);
    for (var y = 0; y < height; y++) {
      final dstRowStart = y * (rowBytes + 1);
      raw[dstRowStart] = 0; // filter: None
      final srcRowStart = y * rowBytes;
      raw.setRange(dstRowStart + 1, dstRowStart + 1 + rowBytes, pixels, srcRowStart);
    }

    // 2) zlib 压缩(等同 image 包内部 zlib)。
    final compressed = Uint8List.fromList(ZLibCodec(level: level).encode(raw));

    // 3) 拼装 PNG。
    //    固定部分:IHDR(13) + 压缩后 IDAT + IEND(0)。
    final png = BytesBuilder();

    // PNG signature
    png.add(_signature);

    // IHDR
    final ihdr = Uint8List(13);
    _writeUint32(ihdr, 0, width);
    _writeUint32(ihdr, 4, height);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // color type: 6 = true color with alpha
    ihdr[10] = 0; // compression method: deflate
    ihdr[11] = 0; // filter method: standard
    ihdr[12] = 0; // interlace method: none
    png.add(_chunk('IHDR', ihdr));

    // IDAT
    png.add(_chunk('IDAT', compressed));

    // IEND
    png.add(_chunk('IEND', Uint8List(0)));

    return png.takeBytes();
  }

  /// 写入 PNG chunk:[length(4)] [type(4)] [data] [crc(4)]。
  Uint8List _chunk(String type, Uint8List data) {
    final out = Uint8List(8 + data.length + 4);
    _writeUint32(out, 0, data.length);
    final typeBytes = ascii.encode(type);
    out[4] = typeBytes[0];
    out[5] = typeBytes[1];
    out[6] = typeBytes[2];
    out[7] = typeBytes[3];
    out.setRange(8, 8 + data.length, data);
    // CRC 覆盖 type + data
    final crc = _crc32(out, 4, 8 + data.length);
    _writeUint32(out, 8 + data.length, crc);
    return out;
  }

  void _writeUint32(Uint8List buf, int offset, int value) {
    buf[offset] = (value >> 24) & 0xff;
    buf[offset + 1] = (value >> 16) & 0xff;
    buf[offset + 2] = (value >> 8) & 0xff;
    buf[offset + 3] = value & 0xff;
  }

  /// CRC-32(PNG 规范:多项式 0xEDB88320,标准表驱动实现)。
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

  static final Uint8List _signature =
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
}
