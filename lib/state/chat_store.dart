import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ai/ai_api.dart';
import '../core/ai/ai_config_store.dart';
import '../core/ai/chat_models.dart';
import '../core/ai/chat_session.dart';
import '../core/ai/context_builder.dart';
import '../core/market/market_data_source.dart';
import '../core/models/position.dart';
import '../core/storage/chat_storage.dart';
import 'app_store.dart';

/// 聊天状态。ChangeNotifier 管理，与 AppStore 同级。
///
/// 通用模式（底部 AI tab）支持多会话：新建/历史列表/切换/删除，持久化到 sqflite，
/// 标题由首条 AI 回复后自动生成摘要。持仓模式（卡片「问 AI」）为临时单会话，不持久化。
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

  /// 所有会话（仅通用模式持久化；持仓模式为单临时会话）。
  final List<ChatSession> _sessions = [];
  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  /// 当前会话。
  ChatSession? _current;
  ChatSession? get current => _current;

  /// 当前消息列表（当前会话的）。
  List<ChatMessage> get messages =>
      List.unmodifiable(_current?.messages ?? const []);

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

  /// 缓存的 system prompt（进入聊天/切换会话时构建，多轮复用）。
  String? _systemPrompt;

  AiApi? _api;
  AiConfig? _config;
  bool _disposed = false;
  bool _initialized = false;

  /// 流式输出的取消订阅（用于 dispose/clear 时中断）。
  StreamSubscription<String>? _streamSub;

  /// 当前流式生成的完成器（用于 stopStreaming 主动结束 await）。
  Completer<void>? _streamCompleter;

  /// 是否为通用模式（多会话持久化）。持仓模式为临时单会话。
  bool get _isGeneral => _contextType == ChatContextType.general;

  /// 初始化：加载配置，构建上下文。
  /// [position] 非 null 时为持仓分析模式（临时单会话），否则为通用模式（多会话）。
  Future<void> init({Position? position}) async {
    try {
      _position = position;
      _contextType =
          position != null ? ChatContextType.position : ChatContextType.general;
      _config = await _configStore.load();
      _api?.dispose();
      if (_config != null && _config!.isValid) {
        _api = AiApi(config: _config!);
      } else {
        _api = null;
      }

      if (_isGeneral) {
        // 通用模式：加载历史会话，选最近一个或新建空会话。
        _sessions.clear();
        _sessions.addAll(await ChatStorage.loadSessions());
        if (_sessions.isNotEmpty) {
          _current = _sessions.first;
        } else {
          newSession(persist: false);
        }
      } else {
        // 持仓模式：单个临时会话，不持久化。
        _current = ChatSession(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          title: '${position!.name} 持仓分析',
          messages: const [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      await _rebuildContext();
    } finally {
      _initialized = true;
      _safeNotify();
    }
  }

  /// 新建会话。通用模式持久化（若 persist=true）；持仓模式不用此方法。
  void newSession({bool persist = true}) {
    if (_isStreaming) return;
    final s = ChatSession(
      id: 'chat_${DateTime.now().millisecondsSinceEpoch}',
      title: '新聊天',
      messages: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _sessions.insert(0, s);
    _current = s;
    if (persist && _isGeneral) {
      ChatStorage.saveSession(s);
    }
    _error = null;
    _safeNotify();
  }

  /// 切换到指定会话。
  Future<void> switchTo(String sessionId) async {
    if (_isStreaming) return;
    final target = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => _current!,
    );
    if (target == _current) return;
    _current = target;
    _error = null;
    await _rebuildContext();
    _safeNotify();
  }

  /// 删除会话。删除当前会话时切到第一个或新建空会话。
  Future<void> deleteSession(String sessionId) async {
    if (_isStreaming) return;
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_isGeneral) await ChatStorage.deleteSession(sessionId);
    if (_current?.id == sessionId) {
      _current = _sessions.isNotEmpty ? _sessions.first : null;
      if (_current == null) newSession(persist: false);
      await _rebuildContext();
    }
    _safeNotify();
  }

  /// 配置存储变更回调：重载配置（不重建行情上下文，避免无谓网络请求）。
  void _onConfigChanged() {
    if (_disposed || _isStreaming) return;
    _reloadConfig();
  }

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
        final monthlyK = await dataSource.fetchMonthlyKlines(_position!.code);
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
      _systemPrompt = '你是一位专业的 A 股交易顾问，请用 Markdown 格式回复。';
    }
  }

  /// 发送消息。
  Future<void> send(String text) async {
    if (text.trim().isEmpty || _isStreaming) return;
    // 当前会话为空时（如 init 竞态）自动建一个，避免静默无反应。
    if (_current == null) {
      if (_isGeneral) {
        newSession();
      } else {
        return;
      }
    }

    if (_api == null) {
      _error = '请先在设置中配置 AI 服务';
      _safeNotify();
      return;
    }

    _error = null;
    final msgs = _current!.messages;
    final isFirstReply = msgs.isEmpty;
    msgs.add(ChatMessage(role: ChatRole.user, content: text));
    final aiMsg = ChatMessage(role: ChatRole.assistant, content: '', isStreaming: true);
    msgs.add(aiMsg);
    _current!.updatedAt = DateTime.now();
    _isStreaming = true;
    _persistCurrent();
    _safeNotify();

    final buffer = StringBuffer();
    final apiMessages =
        msgs.where((m) => !m.isStreaming || m.content.isNotEmpty).toList();

    try {
      final stream = _api!.chatStream(
        messages: apiMessages,
        systemPrompt: _systemPrompt,
      );

      // per-chunk 超时，防止连接中途 stall 永久挂起。
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
          if (msgs.isEmpty) return;
          final lastIdx = msgs.length - 1;
          msgs[lastIdx] = aiMsg.copyWith(
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
          if (msgs.isNotEmpty) {
            final lastIdx = msgs.length - 1;
            msgs[lastIdx] = msgs[lastIdx].copyWith(isStreaming: false);
          }
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;

      // 首条 AI 回复完成后，生成摘要标题（仅通用模式、且标题仍是「新聊天」）。
      if (_isGeneral &&
          isFirstReply &&
          buffer.toString().trim().isNotEmpty &&
          _current!.title == '新聊天') {
        await _generateTitle(text);
      }
      _current!.updatedAt = DateTime.now();
      _persistCurrent();
    } catch (e) {
      if (msgs.isNotEmpty) {
        final lastIdx = msgs.length - 1;
        msgs[lastIdx] = ChatMessage(
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
      _persistCurrent();
      _safeNotify();
    }
  }

  /// 用 AI 生成会话摘要标题。失败则回退为首条消息截取。
  Future<void> _generateTitle(String firstUserMsg) async {
    if (_api == null || _current == null) return;
    try {
      final title = await _api!.generateTitle(firstUserMsg);
      if (title != null && title.trim().isNotEmpty && !_disposed) {
        _current!.title = title.trim().replaceAll(RegExp(r'["\n]'), '');
        if (title.trim().length > 30) {
          _current!.title = '${_current!.title.substring(0, 30)}…';
        }
        _persistCurrent();
        _safeNotify();
      }
    } catch (_) {
      // 回退：首条消息截取。
      if (_current != null) {
        _current!.title = firstUserMsg.length > 20
            ? '${firstUserMsg.substring(0, 20)}…'
            : firstUserMsg;
        _persistCurrent();
        _safeNotify();
      }
    }
  }

  /// 持久化当前会话（仅通用模式）。
  void _persistCurrent() {
    if (_isGeneral && _current != null && _initialized) {
      ChatStorage.saveSession(_current!);
    }
  }

  /// 清空当前对话。流式中先中断。
  void clear() {
    _streamSub?.cancel();
    _streamSub = null;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    _streamCompleter = null;
    _isStreaming = false;
    if (_current != null) {
      _current!.messages.clear();
      _current!.title = '新聊天';
      _persistCurrent();
    }
    _error = null;
    _safeNotify();
  }

  /// 中断当前流式生成，保留已接收到的部分内容。
  void stopStreaming() {
    _streamSub?.cancel();
    _streamSub = null;
    if (_isStreaming && _current != null && _current!.messages.isNotEmpty) {
      final msgs = _current!.messages;
      final lastIdx = msgs.length - 1;
      msgs[lastIdx] = msgs[lastIdx].copyWith(isStreaming: false);
    }
    _isStreaming = false;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    _persistCurrent();
    _safeNotify();
  }

  /// 顶部显示的标题。持仓模式显示「{股票名} 持仓分析」，通用模式固定「AI 助手」。
  String get contextTitle {
    if (_contextType == ChatContextType.position && _position != null) {
      return '${_position!.name} 持仓分析';
    }
    return 'AI 助手';
  }

  /// 是否已配置 AI。
  bool get isConfigured => _config != null && _config!.isValid;

  /// 是否已完成初始化（配置加载 + 上下文构建）。
  /// 未完成时 UI 应显示 loading，而非「去配置」——避免 init 异步未完成时误判。
  bool get isInitialized => _initialized;

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
