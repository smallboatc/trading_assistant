import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/ai/ai_api.dart';
import '../../core/ai/ai_config_store.dart';
import '../../core/ai/chat_models.dart';
import '../theme/app_theme.dart';

/// AI 设置页：配置 API 协议、Key、Base URL、Model。
///
/// 参考 photography_assistant 的 settings_screen，用 secure_storage 持久化。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 用全局单例：保存后广播到所有已初始化的 ChatStore，使其立即生效。
  final _configStore = AiConfigStore.instance;
  final _apiKey = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  String _protocol = 'openai';
  bool _loading = true;
  bool _testing = false;

  static const _defaults = {
    'openai': ('https://api.openai.com/v1', 'gpt-4o'),
    'anthropic': ('https://api.anthropic.com/v1', 'claude-sonnet-5-20250929'),
  };

  /// 切换协议时联动 Base URL / Model 默认值：仅当当前值是另一协议的默认值
  /// 或为空时才覆盖，用户自定义值保留。
  void _onProtocolChanged(String v) {
    final oldDef = _defaults[_protocol]!;
    final newDef = _defaults[v]!;
    setState(() {
      if (_baseUrl.text.trim().isEmpty || _baseUrl.text.trim() == oldDef.$1) {
        _baseUrl.text = newDef.$1;
      }
      if (_model.text.trim().isEmpty || _model.text.trim() == oldDef.$2) {
        _model.text = newDef.$2;
      }
      _protocol = v;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await _configStore.load();
    if (config != null) {
      _apiKey.text = config.apiKey;
      _baseUrl.text = config.baseUrl;
      _model.text = config.model;
      _protocol = config.protocol;
    } else {
      _baseUrl.text = _defaults['openai']!.$1;
      _model.text = _defaults['openai']!.$2;
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final config = AiConfig(
      apiKey: _apiKey.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      protocol: _protocol,
    );
    await _configStore.save(config);
    if (mounted) {
      _showToast('已保存');
    }
  }

  Future<void> _testConnection() async {
    if (_apiKey.text.trim().isEmpty) {
      _showToast('请先填写 API Key', isError: true);
      return;
    }
    setState(() => _testing = true);
    try {
      final api = AiApi(
        config: AiConfig(
          apiKey: _apiKey.text.trim(),
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
          protocol: _protocol,
        ),
      );
      await api.testConnection();
      api.dispose();
      if (mounted) _showToast('连接成功 ✓');
    } catch (e) {
      if (mounted) _showToast('连接失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      // 错误用弹窗，需用户明确确认。
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          content: Text(msg),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return;
    }
    // 成功用轻提示一闪而过。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CupertinoActivityIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        children: [
          _sectionLabel('协议'),
          _protocolSelector(),
          _sectionLabel('配置'),
          _field('API Key', _apiKey, obscure: true,
              hint: 'sk-... 或 sk-ant-...'),
          _field('Base URL', _baseUrl,
              hint: 'https://api.openai.com/v1'),
          _field('Model', _model, hint: 'gpt-4o / claude-sonnet-5-20250929'),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoButton.filled(
                    onPressed: _testing ? null : _testConnection,
                    child: _testing
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoButton(
                    color: AppTheme.systemGray,
                    onPressed: _save,
                    child: const Text('保存',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '支持 OpenAI 兼容协议（deepseek、kimi、智谱等）和 Anthropic 协议。'
              'API Key 加密存储在设备本地，不上传服务器。',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.labelSecondary,
        ),
      ),
    );
  }

  Widget _protocolSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: CupertinoSegmentedControl<String>(
        groupValue: _protocol,
        onValueChanged: _onProtocolChanged,
        children: const {
          'openai': Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('OpenAI'),
          ),
          'anthropic': Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Anthropic'),
          ),
        },
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {bool obscure = false, String? hint}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(label, style: AppTextStyles.caption),
          ),
          CupertinoTextField(
            controller: controller,
            obscureText: obscure,
            placeholder: hint,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}
