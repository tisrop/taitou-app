import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/media/playback_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = PlaybackPositionStore.instance;
  const longDuration = Duration(minutes: 10);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存后可恢复,签名 query 与 fragment 不参与视频身份', () async {
    const url = 'https://cdn.example.com/uploads/resume.mp4?sig=abc#first';
    const refreshedUrl =
        'https://cdn.example.com/uploads/resume.mp4?sig=xyz#second';

    await store.save(url, const Duration(minutes: 3), longDuration);

    expect(await store.restore(refreshedUrl), const Duration(minutes: 3));
    await store.remove(url);
  });

  test('短视频不保存续播位置', () async {
    const url = 'https://cdn.example.com/uploads/short.mp4';

    await store.save(
      url,
      const Duration(seconds: 20),
      const Duration(seconds: 50),
    );

    expect(await store.restore(url), isNull);
  });

  test('片头和片尾豁免区会清除已有位置', () async {
    const url = 'https://cdn.example.com/uploads/boundary.mp4';

    await store.save(url, const Duration(minutes: 3), longDuration);
    expect(await store.restore(url), isNotNull);

    await store.save(
      url,
      longDuration - const Duration(seconds: 5),
      longDuration,
    );
    expect(await store.restore(url), isNull);

    await store.save(url, const Duration(minutes: 3), longDuration);
    await store.save(url, const Duration(seconds: 2), longDuration);
    expect(await store.restore(url), isNull);
  });

  test('flush 将位置写入 SharedPreferences', () async {
    const url = 'https://cdn.example.com/uploads/persist.mp4';

    await store.save(url, const Duration(minutes: 7), longDuration);
    await store.flush();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('media_playback_positions');
    expect(raw, isNotNull);
    expect(raw, contains('"p":420000'));
    await store.remove(url);
  });

  test('remove 删除视频的续播位置', () async {
    const url = 'https://cdn.example.com/uploads/remove.mp4';

    await store.save(url, const Duration(minutes: 3), longDuration);
    await store.remove(url);

    expect(await store.restore(url), isNull);
  });
}
