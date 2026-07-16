import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_models.dart';

/// AI 配置安全存储。用 flutter_secure_storage 存 API key 等敏感信息。
///
/// 参考 photography_assistant 的 secureStorageProvider 模式。
///
/// 继承 [ChangeNotifier]：保存/清除后广播，使已构建的 [ChatStore] 能
/// 重新加载配置并生效（避免保存后需重启 App）。生产环境用 [instance]
/// 单例保证跨页面共享同一存储实例与事件源。
class AiConfigStore extends ChangeNotifier {
  AiConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// 全局单例。设置页与 ChatStore 应共用此实例，保存后才能广播到所有
  /// 已初始化的 ChatStore。
  static final AiConfigStore instance = AiConfigStore();

  final FlutterSecureStorage _storage;

  static const _keyApiKey = 'ai_api_key';
  static const _keyBaseUrl = 'ai_base_url';
  static const _keyModel = 'ai_model';
  static const _keyProtocol = 'ai_protocol';

  /// 读取已保存的配置。未配置返回 null。
  Future<AiConfig?> load() async {
    final apiKey = await _storage.read(key: _keyApiKey);
    final baseUrl = await _storage.read(key: _keyBaseUrl);
    final model = await _storage.read(key: _keyModel);
    final protocol = await _storage.read(key: _keyProtocol);

    if (apiKey == null || apiKey.isEmpty) return null;

    return AiConfig(
      apiKey: apiKey,
      baseUrl: baseUrl ?? _defaultBaseUrl(protocol ?? 'openai'),
      model: model ?? _defaultModel(protocol ?? 'openai'),
      protocol: protocol ?? 'openai',
    );
  }

  Future<void> save(AiConfig config) async {
    await _storage.write(key: _keyApiKey, value: config.apiKey);
    await _storage.write(key: _keyBaseUrl, value: config.baseUrl);
    await _storage.write(key: _keyModel, value: config.model);
    await _storage.write(key: _keyProtocol, value: config.protocol);
    notifyListeners();
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyBaseUrl);
    await _storage.delete(key: _keyModel);
    await _storage.delete(key: _keyProtocol);
    notifyListeners();
  }

  String _defaultBaseUrl(String protocol) => protocol == 'anthropic'
      ? 'https://api.anthropic.com/v1'
      : 'https://api.openai.com/v1';

  String _defaultModel(String protocol) =>
      protocol == 'anthropic' ? 'claude-sonnet-5-20250929' : 'gpt-4o';
}
