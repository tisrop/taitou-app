import 'package:ai_model_manager/utils/api_host_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiHostFormatter.format', () {
    test('空 / null 输入返回空串', () {
      expect(ApiHostFormatter.format(null), '');
      expect(ApiHostFormatter.format(''), '');
      expect(ApiHostFormatter.format('   '), '');
    });

    test('普通 host 自动补 /v1', () {
      expect(
        ApiHostFormatter.format('https://api.example.com'),
        'https://api.example.com/v1',
      );
    });

    test('尾斜杠去掉后补 /v1', () {
      expect(
        ApiHostFormatter.format('https://api.example.com/'),
        'https://api.example.com/v1',
      );
      expect(
        ApiHostFormatter.format('https://api.example.com///'),
        'https://api.example.com/v1',
      );
    });

    test('前后空白去掉', () {
      expect(
        ApiHostFormatter.format('  https://api.example.com  '),
        'https://api.example.com/v1',
      );
    });

    test('已含 /v1 不重复补', () {
      expect(
        ApiHostFormatter.format('https://api.example.com/v1'),
        'https://api.example.com/v1',
      );
      expect(
        ApiHostFormatter.format('https://api.example.com/v1/'),
        'https://api.example.com/v1',
      );
    });

    test('已含 /v2 等其它版本不重复补', () {
      expect(
        ApiHostFormatter.format('https://api.example.com/v2'),
        'https://api.example.com/v2',
      );
      expect(
        ApiHostFormatter.format('https://api.example.com/v3beta'),
        'https://api.example.com/v3beta',
      );
      expect(
        ApiHostFormatter.format('https://api.example.com/v1alpha'),
        'https://api.example.com/v1alpha',
      );
    });

    test('路径中段含版本号也认', () {
      // 用户配 https://proxy.com/v1/openai —— 已经显式指了 v1,不该补成 /v1/openai/v1
      expect(
        ApiHostFormatter.format('https://proxy.com/v1/openai'),
        'https://proxy.com/v1/openai',
      );
    });

    test('# 结尾严格用,不补也不动', () {
      expect(
        ApiHostFormatter.format('https://api.example.com#'),
        'https://api.example.com',
      );
      expect(
        ApiHostFormatter.format('https://api.example.com/custom-path#'),
        'https://api.example.com/custom-path',
      );
      // 即使路径里没有版本号,有 # 也不补
      expect(
        ApiHostFormatter.format('https://api.example.com/raw#'),
        'https://api.example.com/raw',
      );
    });

    test('Gemini 用 v1beta', () {
      expect(
        ApiHostFormatter.format(
          'https://generativelanguage.googleapis.com',
          apiVersion: 'v1beta',
        ),
        'https://generativelanguage.googleapis.com/v1beta',
      );
      // 已经有 v1beta 不重复补
      expect(
        ApiHostFormatter.format(
          'https://generativelanguage.googleapis.com/v1beta',
          apiVersion: 'v1beta',
        ),
        'https://generativelanguage.googleapis.com/v1beta',
      );
    });

    test('supportApiVersion=false 永不补版本', () {
      expect(
        ApiHostFormatter.format(
          'https://api.example.com',
          supportApiVersion: false,
        ),
        'https://api.example.com',
      );
      // 但 # 转义和尾斜杠依然处理
      expect(
        ApiHostFormatter.format(
          'https://api.example.com/',
          supportApiVersion: false,
        ),
        'https://api.example.com',
      );
      expect(
        ApiHostFormatter.format(
          'https://api.example.com/raw#',
          supportApiVersion: false,
        ),
        'https://api.example.com/raw',
      );
    });

    test('用户实际复现案例: muyuan.do 自动补 /v1', () {
      // 这是 muyuan 那个用户的实际配置,Anthropic SDK 拼 /messages 失败
      expect(
        ApiHostFormatter.format('https://muyuan.do'),
        'https://muyuan.do/v1',
      );
    });
  });
}
