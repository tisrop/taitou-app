/// Discourse 引用格式构建器
///
/// 生成 Discourse BBCode 风格的引用标记，用于回复时引用选中内容。
class QuoteBuilder {
  static final RegExp _quotationMarks = RegExp('["\'«»“”‘’„‚‹›]');

  /// 构建 Discourse 引用格式
  ///
  /// [markdown] 选中内容转换后的 Markdown 文本
  /// [displayName] 被引用帖子的作者显示名
  /// [username] 被引用帖子的作者用户名
  /// [postNumber] 被引用帖子的楼层号
  /// [topicId] 话题 ID
  ///
  /// 返回格式：
  /// ```
  /// [quote="displayName, post:N, topic:T, username:username"]
  /// markdown
  /// [/quote]
  ///
  /// ```
  static String build({
    required String markdown,
    String? displayName,
    required String username,
    required int postNumber,
    required int topicId,
  }) {
    final content = markdown.trim();
    final name = (displayName ?? '').replaceAll(_quotationMarks, '').trim();
    final header = name.isNotEmpty
        ? '$name, post:$postNumber, topic:$topicId, username:$username'
        : '$username, post:$postNumber, topic:$topicId';
    return '[quote="$header"]\n$content\n[/quote]\n\n';
  }
}
