import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_models.dart';

/// AI API 异常。
class AiApiException implements Exception {
  final String message;
  final int? statusCode;

  AiApiException(this.message, {this.statusCode});

  @override
  String toString() => 'AiApiException: $message (status: $statusCode)';
}

/// AI 聊天 API，支持 Anthropic + OpenAI 双协议。
///
/// 参考 photography_assistant 的 AiApi，适配为多轮聊天 + SSE 流式。
/// 详见产品设计文档 AI 辅助决策。
class AiApi {
  AiApi({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  final AiConfig config;
  final http.Client _client;

  bool get _isAnthropic => config.isAnthropic;

  /// 发送多轮聊天，流式返回文本片段。
  Stream<String> chatStream({
    required List<ChatMessage> messages,
    String? systemPrompt,
  }) {
    final controller = StreamController<String>();
    _doStream(controller, messages, systemPrompt);
    return controller.stream;
  }

  Future<void> _doStream(
    StreamController<String> controller,
    List<ChatMessage> messages,
    String? systemPrompt,
  ) async {
    try {
      if (_isAnthropic) {
        await _streamAnthropic(controller, messages, systemPrompt);
      } else {
        await _streamOpenAi(controller, messages, systemPrompt);
      }
    } catch (e) {
      controller.addError(e);
    } finally {
      await controller.close();
    }
  }

  // ---- Anthropic ----

  Future<void> _streamAnthropic(
    StreamController<String> controller,
    List<ChatMessage> messages,
    String? systemPrompt,
  ) async {
    final url = Uri.parse('${config.baseUrl}/messages');
    final body = <String, dynamic>{
      'model': config.model,
      'max_tokens': 4096,
      'stream': true,
      'messages': messages
          .where((m) => m.content.isNotEmpty)
          .map((m) => m.toApiJson())
          .toList(),
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['x-api-key'] = config.apiKey
      ..headers['anthropic-version'] = '2023-06-01'
      ..headers['anthropic-dangerous-direct-browser-access'] = 'true'
      ..body = jsonEncode(body);

    final response = await _client.send(request).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw AiApiException('API error: $err', statusCode: response.statusCode);
    }

    await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!chunk.startsWith('data: ')) continue;
      final data = chunk.substring(6).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        if (type == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta != null && delta['type'] == 'text_delta') {
            final text = delta['text'] as String?;
            if (text != null && text.isNotEmpty) {
              controller.add(text);
            }
          }
        }
      } catch (_) {
        // 跳过无法解析的行。
      }
    }
  }

  // ---- OpenAI ----

  Future<void> _streamOpenAi(
    StreamController<String> controller,
    List<ChatMessage> messages,
    String? systemPrompt,
  ) async {
    final url = Uri.parse('${config.baseUrl}/chat/completions');
    final apiMessages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    apiMessages.addAll(
      messages.where((m) => m.content.isNotEmpty).map((m) => m.toApiJson()),
    );

    final body = <String, dynamic>{
      'model': config.model,
      'stream': true,
      'messages': apiMessages,
    };

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${config.apiKey}'
      ..body = jsonEncode(body);

    final response = await _client.send(request).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw AiApiException('API error: $err', statusCode: response.statusCode);
    }

    await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!chunk.startsWith('data: ')) continue;
      final data = chunk.substring(6).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            controller.add(content);
          }
        }
      } catch (_) {
        // 跳过无法解析的行。
      }
    }
  }

  /// 验证 API 连通性和认证。成功返回 true，失败抛异常。
  Future<bool> testConnection() async {
    final url = Uri.parse(
      _isAnthropic
          ? '${config.baseUrl}/messages'
          : '${config.baseUrl}/chat/completions',
    );
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_isAnthropic) {
      headers['x-api-key'] = config.apiKey;
      headers['anthropic-version'] = '2023-06-01';
      headers['anthropic-dangerous-direct-browser-access'] = 'true';
    } else {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final body = jsonEncode({
      'model': config.model,
      'max_tokens': 10,
      'messages': [
        {'role': 'user', 'content': 'Hi'},
      ],
    });

    final response = await _client
        .post(url, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw AiApiException(response.body, statusCode: response.statusCode);
    }
    return true;
  }

  void dispose() => _client.close();
}
