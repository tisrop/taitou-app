/// URL 工具:把用户配的 baseUrl 规范化成实际请求要用的 URL。
///
/// 设计借鉴 Cherry Studio `formatApiHost`,核心目标是让用户**忘加 `/v1`
/// 也能 work**,同时支持高级用户用奇葩自定义路径。
///
/// **规则**:
/// 1. 末尾以 `#` 结尾 → 严格用,**只**去掉 `#` 不补任何后缀
/// 2. 路径里已经有版本号(`/v1` / `/v2beta` 等) → 不重复补
/// 3. 否则 → 补 `/<apiVersion>`(默认 `v1`,Gemini 用 `v1beta`)
///
/// 所有规则前先去掉末尾的 `/`。
///
/// ```dart
/// formatApiHost('https://api.example.com')           // → 'https://api.example.com/v1'
/// formatApiHost('https://api.example.com/')          // → 'https://api.example.com/v1'
/// formatApiHost('https://api.example.com/v1')        // → 'https://api.example.com/v1'
/// formatApiHost('https://api.example.com/v2')        // → 'https://api.example.com/v2'
/// formatApiHost('https://api.example.com/custom#')   // → 'https://api.example.com/custom'
/// formatApiHost('https://api.example.com', apiVersion: 'v1beta')
///                                                    // → 'https://api.example.com/v1beta'
/// ```
class ApiHostFormatter {
  ApiHostFormatter._();

  /// 检测路径里是否已经有 `/v<数字>` `/v<数字>alpha` `/v<数字>beta` 段。
  ///
  /// 匹配位置不限末尾:`/v1/abc` 也算有,避免对 `https://foo.com/v1/path` 类
  /// 自定义路径重复补 v1。
  static final RegExp _versionRegex = RegExp(
    r'/v\d+(?:alpha|beta)?(?:/|$)',
    caseSensitive: false,
  );

  /// 规范化 baseUrl。
  ///
  /// - [host]:用户原始输入。空/null 返回空串(由调用方决定是否兜底默认值)
  /// - [apiVersion]:要补的版本段,默认 `v1`。Gemini 走 `v1beta`
  /// - [supportApiVersion]:false 时永不补版本(用于一些不需要版本前缀的端点)
  static String format(
    String? host, {
    String apiVersion = 'v1',
    bool supportApiVersion = true,
  }) {
    final trimmed = host?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    final noTrailingSlash = _stripTrailingSlash(trimmed);

    if (noTrailingSlash.endsWith('#')) {
      return noTrailingSlash.substring(0, noTrailingSlash.length - 1);
    }
    if (!supportApiVersion) return noTrailingSlash;
    if (_hasApiVersion(noTrailingSlash)) return noTrailingSlash;
    return '$noTrailingSlash/$apiVersion';
  }

  static String _stripTrailingSlash(String s) {
    var end = s.length;
    while (end > 0 && s[end - 1] == '/') {
      end--;
    }
    return s.substring(0, end);
  }

  static bool _hasApiVersion(String url) {
    try {
      final uri = Uri.parse(url);
      return _versionRegex.hasMatch(uri.path);
    } catch (_) {
      // 当传入的不是合法 URL(比如纯路径),退化成对整串匹配
      return _versionRegex.hasMatch(url);
    }
  }
}
