import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../core/ai/chat_models.dart';
import '../../core/market/market_data_source.dart';
import '../../core/models/position.dart';
import '../../state/app_store.dart';
import '../../state/chat_store.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

/// AI 聊天界面。iOS 风格，支持流式输出 + Markdown 渲染。
///
/// 两种入口：
/// - 通用模式（底部导航直接进入）：用全局 ChatStore，注入大盘 + 板块
/// - 持仓模式（从持仓卡片进入）：创建独立 ChatStore，注入该持仓完整数据
/// 详见产品设计文档 AI 辅助决策。
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.position});

  /// 非 null 时为持仓分析模式，创建独立 ChatStore。
  final Position? position;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// 持仓模式下自建的独立 store；通用模式下为 null（用全局 provider）。
  ChatStore? _localStore;

  /// 当前实际使用的 store。
  ChatStore get _store =>
      _localStore ?? context.read<ChatStore>();

  @override
  void initState() {
    super.initState();
    if (widget.position != null) {
      // Bug 7 修复：持仓模式创建独立 ChatStore，不复用全局单例。
      _localStore = ChatStore(
        dataSource: context.read<MarketDataSource>(),
        appStore: context.read<AppStore>(),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _initChat());
  }

  Future<void> _initChat() async {
    await _store.init(position: widget.position);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _localStore?.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 持仓模式用本地 store 监听；通用模式用全局 provider。
    final storeListenable = _localStore ?? context.read<ChatStore>();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: storeListenable,
          builder: (context, child) => Text(_store.contextTitle),
        ),
        actions: [
          if (_store.messages.isNotEmpty)
            IconButton(
              icon: const Icon(CupertinoIcons.delete, size: 20),
              tooltip: '清空对话',
              onPressed: () => _showClearConfirm(context),
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.refresh, size: 20),
            tooltip: '刷新数据',
            onPressed: () => _store.refreshContext(),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.gear, size: 20),
            tooltip: 'AI 设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: storeListenable,
        builder: (context, child) {
          if (!_store.isConfigured) {
            return _unconfigured(context);
          }
          _scrollToBottom();
          return Column(
            children: [
              Expanded(child: _messageList()),
              _inputBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _messageList() {
    if (_store.messages.isEmpty) {
      return _empty();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _store.messages.length,
      itemBuilder: (context, i) => _messageBubble(_store.messages[i]),
    );
  }

  Widget _messageBubble(ChatMessage msg) {
    final isUser = msg.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.systemBlue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: isUser
            ? Text(msg.content,
                style: const TextStyle(color: Colors.white, fontSize: 15))
            : _aiContent(msg),
      ),
    );
  }

  Widget _aiContent(ChatMessage msg) {
    if (msg.isStreaming && msg.content.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.systemGray,
            ),
          ),
          const SizedBox(width: 8),
          Text('思考中…', style: TextStyle(color: AppTheme.systemGray, fontSize: 14)),
        ],
      );
    }
    return MarkdownBody(
      data: msg.content,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 15),
        h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        code: TextStyle(
          backgroundColor: AppTheme.groupedBackground,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.separator, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                placeholder: '输入消息…',
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.groupedBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                onSubmitted: (_) => _send(),
                enabled: !_store.isStreaming,
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _store.isStreaming ? _store.stopStreaming : _send,
              child: Icon(
                _store.isStreaming
                    ? CupertinoIcons.stop_circle_fill
                    : CupertinoIcons.arrow_up_circle_fill,
                size: 30,
                color: _store.isStreaming
                    ? AppTheme.nearStop
                    : AppTheme.systemBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _store.isStreaming) return;
    _controller.clear();
    _store.send(text);
  }

  void _showClearConfirm(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清空对话？'),
        content: const Text('所有消息将被清除，此操作无法撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              _store.clear();
              Navigator.of(ctx).pop();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final hints = _store.contextType == ChatContextType.position
        ? [
            '这只票现在该止盈还是继续持有？',
            '止损线设得合理吗？',
            '分析一下近期的走势',
          ]
        : [
            '今天大盘怎么样？',
            '哪些板块在轮动？',
            '帮我分析下我的整体持仓',
          ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.chat_bubble_2,
                size: 64, color: AppTheme.systemGray3),
            const SizedBox(height: 16),
            const Text('和 AI 聊聊交易', style: AppTextStyles.cardTitle),
            const SizedBox(height: 8),
            Text(
              _store.contextType == ChatContextType.position
                  ? '已注入 ${_store.contextTitle} 的数据'
                  : '已注入大盘与板块数据',
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: hints.map((h) => _hintChip(h)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      backgroundColor: AppTheme.groupedBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () => _store.send(text),
    );
  }

  Widget _unconfigured(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.gear_alt,
                size: 64, color: AppTheme.systemGray3),
            const SizedBox(height: 16),
            const Text('未配置 AI 服务', style: AppTextStyles.cardTitle),
            const SizedBox(height: 8),
            const Text('请先设置 API Key 和模型',
                style: AppTextStyles.subtitle),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              child: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }
}
