/// cooked 内容形态判定。
///
/// 目前只有聊天气泡在用：纯图片 / 纯 emoji 消息不套文字气泡，所以需要在渲染
/// 前先知道这条消息属于哪种形态。
library;

import 'package:fluxdo_render/fluxdo_render.dart';

/// 消息正文该用哪种外框。
enum CookedBubbleStyle {
  /// 含可见文字（或引用 / 代码块等任何别的内容）—— 正常文字气泡。
  bubble,

  /// 只有图片 —— 裸出图片并切圆角，不要底色和内边距。
  image,

  /// 只有 emoji —— 裸出即可。**不能切圆角**：服务端会给整段独立 emoji 打上
  /// `only-emoji`，渲染器按 32dp 出图，圆角会把它啃掉一圈。
  emoji,
}

/// 判定一段 cooked 解析出来的节点树该用哪种外框。
///
/// 判定规则：
/// - [ImageRun] / [ImageGridNode] 记为图片，[EmojiRun] 记为 emoji；
/// - 纯空白的 [TextRun]、[LineBreakRun]、[BlankLineNode] 忽略（Discourse
///   cook 出来的 `<p><img></p>` 前后常带换行文本节点）；
/// - 出现其它任何内容（文字、链接、提及、引用、代码块…）即为
///   [CookedBubbleStyle.bubble]；
/// - 图片与 emoji 混排时按图片处理（图片主导，切圆角无副作用）；
/// - 空内容也走 [CookedBubbleStyle.bubble]。
CookedBubbleStyle cookedBubbleStyleOf(List<BlockNode> nodes) {
  var sawImage = false;
  var sawEmoji = false;

  for (final node in nodes) {
    if (node is BlankLineNode) continue;
    if (node is ImageGridNode) {
      sawImage = true;
      continue;
    }
    if (node is! ParagraphNode) return CookedBubbleStyle.bubble;
    for (final run in node.inlines) {
      if (run is ImageRun) {
        sawImage = true;
      } else if (run is EmojiRun) {
        sawEmoji = true;
      } else if (run is LineBreakRun) {
        continue;
      } else if (run is TextRun && run.text.trim().isEmpty) {
        continue;
      } else {
        return CookedBubbleStyle.bubble;
      }
    }
  }

  if (sawImage) return CookedBubbleStyle.image;
  if (sawEmoji) return CookedBubbleStyle.emoji;
  return CookedBubbleStyle.bubble;
}
