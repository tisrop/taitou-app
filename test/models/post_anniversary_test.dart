import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/models/topic.dart';

void main() {
  String date(int year, int month, int day) =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  Post postFromJson({String? cakedate, String? birthdate}) {
    return Post.fromJson({
      'id': 1,
      'user_cakedate': ?cakedate,
      'user_birthdate': ?birthdate,
    });
  }

  test('Post.fromJson 解析生日与社区加入日期', () {
    final post = postFromJson(cakedate: '2020-05-06', birthdate: '1904-07-08');

    expect(post.userCakedate, '2020-05-06');
    expect(post.userBirthdate, '1904-07-08');
  });

  test('生日只比较今天的月日', () {
    final now = DateTime.now();
    final post = postFromJson(birthdate: date(1904, now.month, now.day));

    expect(post.isTodayBirthday, isTrue);
  });

  test('加入日期在往年同月同日才算社区纪念日', () {
    final now = DateTime.now();
    final anniversary = postFromJson(
      cakedate: date(now.year - 1, now.month, now.day),
    );
    final joinedToday = postFromJson(
      cakedate: date(now.year, now.month, now.day),
    );

    expect(anniversary.isTodayCakeday, isTrue);
    expect(joinedToday.isTodayCakeday, isFalse);
  });

  test('不同月日、空值或非法日期不会显示纪念图标', () {
    final now = DateTime.now();
    final otherMonth = now.month == 12 ? 1 : now.month + 1;
    final otherDay = postFromJson(
      cakedate: date(now.year - 1, otherMonth, now.day),
      birthdate: date(1904, otherMonth, now.day),
    );
    final missing = postFromJson();
    final invalid = postFromJson(
      cakedate: 'invalid!!!',
      birthdate: 'invalid!!!',
    );

    expect(otherDay.isTodayCakeday, isFalse);
    expect(otherDay.isTodayBirthday, isFalse);
    expect(missing.isTodayCakeday, isFalse);
    expect(missing.isTodayBirthday, isFalse);
    expect(invalid.isTodayCakeday, isFalse);
    expect(invalid.isTodayBirthday, isFalse);
  });

  test('copyWith 保留并可替换生日与社区加入日期', () {
    final original = postFromJson(
      cakedate: '2020-05-06',
      birthdate: '1904-07-08',
    );

    final retained = original.copyWith(username: 'updated');
    final replaced = original.copyWith(
      userCakedate: '2021-06-07',
      userBirthdate: '1904-08-09',
    );

    expect(retained.userCakedate, '2020-05-06');
    expect(retained.userBirthdate, '1904-07-08');
    expect(replaced.userCakedate, '2021-06-07');
    expect(replaced.userBirthdate, '1904-08-09');
  });
}
