/// 「文本即链接」的裸链接修改文字时，href 也应同步更新。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/src/editor/model/editable_text_content.dart';

const _url = 'https://linux.do/t/topic/2659942/18?u=is_hp';

EditableTextContent _bareLink() => EditableTextContent(
  text: _url,
  marks: const [
    MarkSpan(start: 0, end: _url.length, kind: MarkKind.link, attr: _url),
  ],
);

void main() {
  test('删掉查询参数时 href 跟随可见文本', () {
    final result = _bareLink().delete(_url.indexOf('?'), _url.length);

    expect(result.text, 'https://linux.do/t/topic/2659942/18');
    expect(result.marks.single.attr, result.text);
  });

  test('在裸链接内部续打字符时 href 跟随可见文本', () {
    final result = _bareLink().insert(_url.length - 1, 'X');

    expect(result.marks.single.attr, result.text);
  });

  test('自定义文案链接不联动 href', () {
    const label = '点我';
    final content = EditableTextContent(
      text: label,
      marks: const [
        MarkSpan(start: 0, end: label.length, kind: MarkKind.link, attr: _url),
      ],
    );

    final result = content.insert(1, '击');

    expect(result.text, '点击我');
    expect(result.marks.single.attr, _url);
  });

  test('替换尾部查询参数后保持单段链接并更新 href', () {
    final result = _bareLink().replace(_url.indexOf('?'), _url.length, 'x');

    expect(result.text, 'https://linux.do/t/topic/2659942/18x');
    expect(result.marks, hasLength(1));
    expect(result.marks.single.start, 0);
    expect(result.marks.single.end, result.text.length);
    expect(result.marks.single.attr, result.text);
  });

  test('替换裸链接中段后保持单段链接并更新 href', () {
    final start = _url.indexOf('topic');
    final result = _bareLink().replace(start, start + 5, 'x');

    expect(result.text, 'https://linux.do/t/x/2659942/18?u=is_hp');
    expect(result.marks, hasLength(1));
    expect(result.marks.single.attr, result.text);
  });

  test('替换自定义文案链接时保留原 href', () {
    const label = '点我看看';
    final content = EditableTextContent(
      text: label,
      marks: const [
        MarkSpan(start: 0, end: label.length, kind: MarkKind.link, attr: _url),
      ],
    );

    final result = content.replace(2, 4, '瞧瞧');

    expect(result.text, '点我瞧瞧');
    expect(result.marks.single.attr, _url);
  });
}
