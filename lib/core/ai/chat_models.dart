/// 聊天消息角色。
enum ChatRole { user, assistant }

/// 聊天上下文模式。详见产品设计文档 AI 辅助决策。
enum ChatContextType {
  /// 通用聊天：注入大盘 + 板块信息。
  general,

  /// 持仓分析：注入指定持仓的完整数据。
  position,
}

/// 一条聊天消息。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  final ChatRole role;
  final String content;
  final DateTime timestamp;

  /// 是否正在流式接收中（用于 UI 打字动画）。
  final bool isStreaming;

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
  }) =>
      ChatMessage(
        role: role,
        content: content ?? this.content,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );

  /// 转为 API 请求格式（role + content）。
  Map<String, dynamic> toApiJson() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': content,
      };
}

/// AI 服务配置。
class AiConfig {
  const AiConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.protocol,
  });

  /// 'anthropic' 或 'openai'。
  final String protocol;
  final String apiKey;
  final String baseUrl;
  final String model;

  bool get isAnthropic => protocol == 'anthropic';

  bool get isValid =>
      apiKey.isNotEmpty && baseUrl.isNotEmpty && model.isNotEmpty;
}
