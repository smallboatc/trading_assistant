import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ai/ai_api.dart';
import '../core/ai/ai_config_store.dart';
import '../core/ai/chat_models.dart';
import '../core/ai/context_builder.dart';
import '../core/market/market_data_source.dart';
import '../core/models/position.dart';
import 'app_store.dart';

/// 聊天状态。ChangeNotifier 管理，与 AppStore 同级。
///
/// 负责管理消息列表、流式接收、上下文构建与注入。
/// 详见产品设计文档 AI 辅助决策。
class ChatStore extends ChangeNotifier {
  ChatStore({
    required this.dataSource,
    required this.appStore,
    AiConfigStore? configStore,
  }) : _configStore = configStore ?? AiConfigStore.instance {
    // 监听配置变更：设置页保存后自动重载配置生效，无需重启 App。
    _configStore.addListener(_onConfigChanged);
  }

  final MarketDataSource dataSource;
  final AppStore appStore;
  final AiConfigStore _configStore;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  String? _error;
  String? get error => _error;

  /// 当前上下文模式。
  ChatContextType _contextType = ChatContextType.general;
  ChatContextType get contextType => _contextType;

  /// 当前关联的持仓（持仓分析模式时）。
  Position? _position;
  Position? get position => _position;

  /// 缓存的 system prompt（进入聊天时构建一次，多轮复用）。
  String? _systemPrompt;

  AiApi? _api;
  AiConfig? _config;
  bool _disposed = false;

  /// 流式输出的取消订阅（用于 dispose/clear 时中断）。
  StreamSubscription<String>? _streamSub;

  /// 当前流式生成的完成器（用于 stopStreaming 主动结束 await）。
  Completer<void>? _streamCompleter;

  /// 初始化：加载配置，构建上下文。
  /// [position] 非 null 时为持仓分析模式，否则为通用模式。
  Future<void> init({Position? position}) async {
    _position = position;
    _contextType =
        position != null ? ChatContextType.position : ChatContextType.general;
    _config = await _configStore.load();
    // Bug 3 修复：重新 init 时先释放旧的 AiApi（http.Client）。
    _api?.dispose();
    if (_config != null && _config!.isValid) {
      _api = AiApi(config: _config!);
    } else {
      _api = null;
    }
    await _rebuildContext();
  }

  /// 配置存储变更回调：重载配置（不重建行情上下文，避免无谓网络请求）。
  /// 流式输出进行中则跳过，待其结束后下次发送自然生效。
  void _onConfigChanged() {
    if (_disposed || _isStreaming) return;
    _reloadConfig();
  }

  /// 仅重载 AI 配置与 API 客户端，保留已有消息与上下文模式。
  Future<void> _reloadConfig() async {
    _config = await _configStore.load();
    _api?.dispose();
    if (_config != null && _config!.isValid) {
      _api = AiApi(config: _config!);
    } else {
      _api = null;
    }
    _safeNotify();
  }

  /// 刷新上下文数据（重新拉行情）。
  Future<void> refreshContext() async {
    await _rebuildContext();
    _safeNotify();
  }

  Future<void> _rebuildContext() async {
    try {
      final overview = await dataSource.fetchMarketOverview();
      if (_contextType == ChatContextType.position && _position != null) {
        final dailyK = await dataSource.fetchDailyKlines(_position!.code);
        final monthlyK =
            await dataSource.fetchMonthlyKlines(_position!.code);
        final sector = await dataSource.fetchSector(_position!.code);
        _systemPrompt = ContextBuilder.buildPositionContext(
          position: _position!,
          dailyKlines: dailyK,
          monthlyKlines: monthlyK,
          sector: sector,
          overview: overview,
        );
      } else {
        _systemPrompt = ContextBuilder.buildGeneralContext(
          overview: overview,
          store: appStore,
        );
      }
    } catch (e) {
      // 上下文构建失败不阻断聊天，使用最简 prompt。
      _systemPrompt = '你是一位专业的 A 股交易顾问，请用 Markdown 格式回复。';
    }
  }

  /// 发送消息。
  Future<void> send(String text) async {
    if (text.trim().isEmpty || _isStreaming) return;

    if (_api == null) {
      _error = '请先在设置中配置 AI 服务';
      _safeNotify();
      return;
    }

    _error = null;
    _messages.add(ChatMessage(role: ChatRole.user, content: text));
    // 占位的 AI 消息，流式填充。
    final aiMsg = ChatMessage(
      role: ChatRole.assistant,
      content: '',
      isStreaming: true,
    );
    _messages.add(aiMsg);
    _isStreaming = true;
    _safeNotify();

    final buffer = StringBuffer();
    final apiMessages = _messages
        .where((m) => !m.isStreaming || m.content.isNotEmpty)
        .toList();

    try {
      final stream = _api!.chatStream(
        messages: apiMessages,
        systemPrompt: _systemPrompt,
      );

      // Bug 4 修复：per-chunk 超时，防止连接中途 stall 导致永久挂起。
      Timer? watchdog;
      void resetWatchdog() {
        watchdog?.cancel();
        watchdog = Timer(const Duration(seconds: 60), () {
          _streamSub?.cancel();
        });
      }
      resetWatchdog();

      final completer = Completer<void>();
      _streamCompleter = completer;
      _streamSub = stream.listen(
        (chunk) {
          resetWatchdog();
          buffer.write(chunk);
          // Bug 1 修复：列表可能被 clear 清空，检查越界。
          if (_messages.isEmpty) return;
          final lastIdx = _messages.length - 1;
          _messages[lastIdx] = aiMsg.copyWith(
            content: buffer.toString(),
            isStreaming: true,
          );
          _safeNotify();
        },
        onError: (e) {
          watchdog?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          watchdog?.cancel();
          // Bug 1 修复：流结束时列表可能已被 clear。
          if (_messages.isNotEmpty) {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] =
                _messages[lastIdx].copyWith(isStreaming: false);
          }
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      if (_messages.isNotEmpty) {
        final lastIdx = _messages.length - 1;
        _messages[lastIdx] = ChatMessage(
          role: ChatRole.assistant,
          content: '⚠️ 请求失败：$e',
          isStreaming: false,
        );
      }
      _error = e.toString();
    } finally {
      _isStreaming = false;
      _streamSub = null;
      _streamCompleter = null;
      _safeNotify();
    }
  }

  /// 清空对话。流式输出中时仅清空消息、中断流，不触发 RangeError。
  void clear() {
    // Bug 1 修复：先中断正在进行的流。
    _streamSub?.cancel();
    _streamSub = null;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    _streamCompleter = null;
    _isStreaming = false;
    _messages.clear();
    _error = null;
    _safeNotify();
  }

  /// 中断当前流式生成，保留已接收到的部分内容。
  void stopStreaming() {
    _streamSub?.cancel();
    _streamSub = null;
    if (_isStreaming && _messages.isNotEmpty) {
      final lastIdx = _messages.length - 1;
      _messages[lastIdx] = _messages[lastIdx].copyWith(isStreaming: false);
    }
    _isStreaming = false;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    _safeNotify();
  }

  /// 顶部显示的上下文标题。
  String get contextTitle {
    if (_contextType == ChatContextType.position && _position != null) {
      return '${_position!.name} 持仓分析';
    }
    return '市场概览';
  }

  /// 是否已配置 AI。
  bool get isConfigured => _config != null && _config!.isValid;

  // Bug 2 修复：dispose 后不再调 notifyListeners。
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _configStore.removeListener(_onConfigChanged);
    _streamSub?.cancel();
    _api?.dispose();
    super.dispose();
  }
}
