import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/poll_builder_dialog.dart';

void main() {
  group('PollSpec.toBBCode', () {
    test('同帖第二个投票自动生成唯一名称', () {
      const spec = PollSpec(
        type: kPollTypeRegular,
        results: 'always',
        public: true,
        chartType: 'bar',
        title: '午饭吃什么',
        options: ['米饭', '面条'],
      );

      expect(spec.toBBCode(), isNot(contains(' name=')));
      expect(spec.toBBCode(existingPollCount: 1), contains(' name=poll2'));
      expect(spec.toBBCode(existingPollCount: 1), contains('# 午饭吃什么'));
      expect(spec.toBBCode(existingPollCount: 1), contains('* 米饭'));
    });

    test('多选投票输出选择范围和图表类型', () {
      const spec = PollSpec(
        type: kPollTypeMultiple,
        results: 'on_vote',
        public: false,
        chartType: 'pie',
        title: '',
        options: ['A', 'B', 'C'],
        min: 1,
        max: 2,
      );

      final raw = spec.toBBCode();
      expect(raw, contains('type=multiple'));
      expect(raw, contains('results=on_vote'));
      expect(raw, contains('min=1 max=2'));
      expect(raw, contains('public=false'));
      expect(raw, contains('chartType=pie'));
    });

    test('数字评分输出步长且忽略选项和图表', () {
      const spec = PollSpec(
        type: kPollTypeNumber,
        results: 'on_close',
        public: true,
        chartType: 'pie',
        title: '评分',
        options: ['不会输出'],
        min: 1,
        max: 10,
        step: 2,
      );

      final raw = spec.toBBCode();
      expect(raw, contains('type=number'));
      expect(raw, contains('min=1 max=10 step=2'));
      expect(raw, isNot(contains('chartType=')));
      expect(raw, isNot(contains('不会输出')));
    });
  });

  group('PollSpec.tryParse', () {
    test('反解析后保留未建模属性并可无损写回', () {
      final spec = PollSpec.tryParse('''
[poll name=team results=on_vote type=multiple min=1 max=2 public=true chartType=pie groups="staff users"]
# 选择成员
* Alice
* Bob
[/poll]
''');

      expect(spec, isNotNull);
      expect(spec!.type, kPollTypeMultiple);
      expect(spec.title, '选择成员');
      expect(spec.options, ['Alice', 'Bob']);
      expect(spec.extraAttrs, {'name': 'team', 'groups': 'staff users'});
      final raw = spec.toBBCode();
      expect(raw, contains('name=team'));
      expect(raw, contains('groups="staff users"'));
    });

    test('不支持的类型或无法归类的正文拒绝表单解析', () {
      expect(
        PollSpec.tryParse('[poll type=ranked_choice]\n* A\n* B\n[/poll]'),
        isNull,
      );
      expect(PollSpec.tryParse('[poll]\n普通正文\n* A\n[/poll]'), isNull);
    });
  });
}
