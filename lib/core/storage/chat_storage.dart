import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../ai/chat_models.dart';
import '../ai/chat_session.dart';
import 'position_storage.dart';

/// 聊天会话持久化（复用 [PositionStorage] 的数据库连接）。
///
/// chat_sessions 表：id/title/messages_json/created_at/updated_at。
/// messages 存 JSON 列（含 role/content/timestamp）。
class ChatStorage {
  static Future<List<ChatSession>> loadSessions() async {
    try {
      final db = await PositionStorage.database;
      final rows = await db.query('chat_sessions', orderBy: 'updated_at DESC');
      return rows.map(_fromRow).toList();
    } catch (_) {
      // 表不存在或数据库未就绪时返回空，不阻断聊天。
      return [];
    }
  }

  static Future<void> saveSession(ChatSession s) async {
    final db = await PositionStorage.database;
    await db.insert('chat_sessions', _toRow(s),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteSession(String id) async {
    final db = await PositionStorage.database;
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, dynamic> _toRow(ChatSession s) => {
        'id': s.id,
        'title': s.title,
        'messages_json': jsonEncode(s.messages.map((m) => m.toJson()).toList()),
        'created_at': s.createdAt.toIso8601String(),
        'updated_at': s.updatedAt.toIso8601String(),
      };

  static ChatSession _fromRow(Map<String, dynamic> r) {
    final messages = (jsonDecode(r['messages_json'] as String) as List<dynamic>)
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList();
    return ChatSession(
      id: r['id'] as String,
      title: r['title'] as String? ?? '新聊天',
      messages: messages,
      createdAt: DateTime.parse(r['created_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
    );
  }
}
