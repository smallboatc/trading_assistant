// 验证聊天会话持久化：存→重新加载，数据应在。
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_assistant/core/ai/chat_models.dart';
import 'package:trading_assistant/core/ai/chat_session.dart';
import 'package:trading_assistant/core/storage/chat_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('聊天会话保存后重新加载应存在', () async {
    final s = ChatSession(
      id: 'test_chat_1',
      title: '测试会话',
      messages: [
        ChatMessage(role: ChatRole.user, content: '你好'),
        ChatMessage(role: ChatRole.assistant, content: '你好，有什么可以帮你？'),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await ChatStorage.saveSession(s);

    final loaded = await ChatStorage.loadSessions();
    final found = loaded.where((x) => x.id == 'test_chat_1').toList();
    expect(found, isNotEmpty, reason: '保存的会话应能加载到');
    expect(found.first.title, '测试会话');
    expect(found.first.messages.length, 2);
    expect(found.first.messages[0].content, '你好');

    await ChatStorage.deleteSession('test_chat_1');
  });
}
