import 'chat_models.dart';

/// 一个 AI 聊天会话（仅通用模式）。
///
/// 含 id、标题、消息列表、创建/更新时间。标题由首条 AI 回复后自动生成摘要。
/// 持久化到 sqflite，messages 存 JSON 列。
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required List<ChatMessage> messages,
    required this.createdAt,
    required this.updatedAt,
  }) : messages = List<ChatMessage>.of(messages);

  final String id;

  /// 会话标题（首条 AI 回复后由 AI 生成摘要；之前为「新聊天」）。
  String title;

  /// 消息列表（可变，流式输出时追加/更新）。
  final List<ChatMessage> messages;

  final DateTime createdAt;
  DateTime updatedAt;

  /// 是否为空会话（无消息）。
  bool get isEmpty => messages.isEmpty;
}
