import 'package:flutter/material.dart';

import '../../core/ai/ai_api.dart';
import '../../core/ai/ai_config_store.dart';
import '../../core/ai/chat_models.dart';
import '../theme/app_theme.dart';

/// AI 设置页：配置 API 协议、Key、Base URL、Model。
///
/// 样式参考 photography_assistant 的 settings_screen：分组标题 + 白色圆角卡片
/// + Material TextField（prefixIcon）+ SegmentedButton 选协议 + API Key 显隐。
/// 用 secure_storage 持久化，保存后广播到所有 ChatStore 立即生效。
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
  bool _saving = false;
  bool _testing = false;
  bool _obscureApiKey = true;
  // null=未测试，true=通过，false=失败
  bool? _connectionTestPassed;

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
      _connectionTestPassed = null;
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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = AiConfig(
        apiKey: _apiKey.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        protocol: _protocol,
      );
      await _configStore.save(config);
      if (mounted) _showToast('已保存');
    } catch (e) {
      if (mounted) _showToast('保存失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_apiKey.text.trim().isEmpty) {
      _showToast('请先填写 API Key', isError: true);
      return;
    }
    setState(() {
      _testing = true;
      _connectionTestPassed = null;
    });
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
      if (mounted) setState(() => _connectionTestPassed = true);
    } catch (e) {
      if (mounted) setState(() => _connectionTestPassed = false);
      if (mounted) _showToast('连接失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return;
    }
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const _SectionHeader(title: 'AI 配置'),
          const SizedBox(height: 8),
          _buildApiKeyCard(),
          const SizedBox(height: 24),
          const _SectionHeader(title: '说明'),
          const SizedBox(height: 8),
          _buildHelpCard(),
          const SizedBox(height: 24),
          const _SectionHeader(title: '后台保活'),
          const SizedBox(height: 8),
          _buildBackgroundCard(),
        ],
      ),
    );
  }

  Widget _buildApiKeyCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.systemBlue.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.smart_toy_outlined,
                    color: AppTheme.systemBlue),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI API 配置',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text(
                      '支持 OpenAI、Anthropic 等各大 AI 厂商',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // API 格式
          const _FieldLabel(label: 'API 格式'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'openai',
                label: Text('OpenAI'),
                icon: Icon(Icons.hub_outlined, size: 16),
              ),
              ButtonSegment(
                value: 'anthropic',
                label: Text('Anthropic'),
                icon: Icon(Icons.bolt_rounded, size: 16),
              ),
            ],
            selected: {_protocol},
            onSelectionChanged: (v) => _onProtocolChanged(v.first),
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(height: 16),

          // Base URL
          const _FieldLabel(label: 'Base URL'),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrl,
            decoration: InputDecoration(
              hintText: _defaults[_protocol]!.$1,
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Model
          const _FieldLabel(label: '模型'),
          const SizedBox(height: 8),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              hintText: _defaults[_protocol]!.$2,
              prefixIcon: const Icon(Icons.auto_awesome),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // API Key
          const _FieldLabel(label: 'API 密钥'),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKey,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              hintText: '请输入您的 AI API 密钥',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscureApiKey
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // 保存 + 测试按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_saving || _testing) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_saving ? '保存中...' : '保存配置'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_saving || _testing) ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_find),
                  label: Text(_testing ? '测试中...' : '测试连接'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 状态指示
          if (_connectionTestPassed != null || _apiKey.text.isNotEmpty)
            _buildStatusRow(),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    final IconData icon;
    final Color color;
    final String label;
    if (_testing) {
      icon = Icons.hourglass_empty;
      color = Colors.grey;
      label = '测试中';
    } else if (_connectionTestPassed == true) {
      icon = Icons.check_circle;
      color = AppTheme.normal;
      label = '连接正常';
    } else if (_connectionTestPassed == false) {
      icon = Icons.error_outline;
      color = AppTheme.nearStop;
      label = '连接失败';
    } else {
      icon = Icons.info_outline;
      color = Colors.grey;
      label = '尚未测试';
    }
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w500, fontSize: 12)),
      ],
    );
  }

  /// 后台保活引导：检测电池优化状态，未授权则提示并跳转设置。
  /// 后台保活说明：纯文字引导用户去手机设置开启后台运行（国产ROM各家入口
  /// 不同，且检测/跳转不准，故只做说明，由用户自行检查开启）。
  Widget _buildBackgroundCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.systemBlue.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.battery_saver, color: AppTheme.systemBlue),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('后台保活',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text(
                      '退后台仍能监控止损止盈并推送系统通知',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '为保证 App 退到后台后仍能实时监控并推送通知，需在手机系统设置里'
            '允许「交易助手」后台运行。各品牌路径略有不同，一般位于：',
            style: TextStyle(fontSize: 13, color: AppTheme.labelSecondary, height: 1.6),
          ),
          const SizedBox(height: 10),
          _bullet('设置 → 应用管理 → 交易助手 → 电池/耗电管理 → 允许后台运行'),
          _bullet('或：设置 → 电池 → 后台耗电管理 → 交易助手 → 允许'),
          const SizedBox(height: 10),
          Text(
            'vivo/OPPO/小米等品牌需同时关闭「省电模式」或将本应用加入'
            '「自启动白名单」。未开启时退后台可能被系统冻结，无法及时收到提醒。',
            style: TextStyle(fontSize: 12, color: AppTheme.nearStop, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('·  ', style: TextStyle(color: AppTheme.systemBlue, fontSize: 13)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.systemGray2.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.help_outline,
                    color: AppTheme.systemGray),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text('使用说明',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '支持 OpenAI 兼容协议（deepseek、kimi、智谱等）和 Anthropic 协议。\n\n'
            '· API 密钥加密存储在设备本地，不上传服务器。\n'
            '· Base URL 填服务地址，模型填对应模型名。\n'
            '· 保存后所有 AI 对话立即生效，无需重启。',
            style: TextStyle(
                fontSize: 13, color: AppTheme.labelSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: AppTheme.labelSecondary.withAlpha(180),
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppTheme.labelSecondary.withAlpha(200),
      ),
    );
  }
}
