/// 聊天消息附件（多模态输入），目前只支持图片。
///
/// 三个内容来源互斥优先级：[remoteUrl] > [localPath] > [base64Data]
/// - 已上传到 Discourse / 图床的，存 [remoteUrl]，体积友好
/// - 用户本地选择尚未上传的，存 [localPath]，发送时由调用方读取并 base64 编码
/// - 兜底（小图、剪贴板贴图等）才用 [base64Data] 直接持久化
class AiChatAttachment {
  final String mimeType;
  final String? base64Data;
  final String? localPath;
  final String? remoteUrl;

  /// 渐进式生成的 partial 帧索引（OpenAI gpt-image stream 的草图）。
  /// `null` 表示终态完整图；`>= 0` 表示第 N 张渐进帧。
  /// 终态图到达时上层应清掉所有 partial 帧。
  final int? partialImageIndex;

  const AiChatAttachment({
    required this.mimeType,
    this.base64Data,
    this.localPath,
    this.remoteUrl,
    this.partialImageIndex,
  });

  bool get isPartial => partialImageIndex != null;

  AiChatAttachment copyWith({
    String? mimeType,
    String? base64Data,
    String? localPath,
    String? remoteUrl,
    int? partialImageIndex,
  }) {
    return AiChatAttachment(
      mimeType: mimeType ?? this.mimeType,
      base64Data: base64Data ?? this.base64Data,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      partialImageIndex: partialImageIndex ?? this.partialImageIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mimeType': mimeType,
      if (base64Data != null) 'base64Data': base64Data,
      if (localPath != null) 'localPath': localPath,
      if (remoteUrl != null) 'remoteUrl': remoteUrl,
      // partialImageIndex 不持久化：partial 帧在生成结束时已被丢弃，
      // 反序列化的总是终态图
    };
  }

  factory AiChatAttachment.fromJson(Map<String, dynamic> json) {
    return AiChatAttachment(
      mimeType: json['mimeType'] as String,
      base64Data: json['base64Data'] as String?,
      localPath: json['localPath'] as String?,
      remoteUrl: json['remoteUrl'] as String?,
    );
  }
}
