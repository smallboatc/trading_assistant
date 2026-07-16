import 'dart:async';

import '../core/market/market_data_source.dart';
import '../core/market/mock_market_data_source.dart';
import '../core/monitoring/monitoring_engine.dart';
import '../core/models/account.dart';
import '../core/models/alert.dart';
import '../core/models/fill.dart';
import '../core/models/position.dart';
import '../core/models/strategy_config.dart';
import 'package:flutter/foundation.dart';

/// 应用内存态 store。V1 用 ChangeNotifier 做最简状态管理；
/// 后续若引入持久化（第八章待讨论问题 12）或多账户隔离，在此扩展。
///
/// 持有：在管持仓列表、提醒列表、监控引擎。监控循环在前台运行。
class AppStore extends ChangeNotifier {
  AppStore({MarketDataSource? dataSource})
      : _engine = MonitoringEngine(dataSource: dataSource ?? MockMarketDataSource());

  final MonitoringEngine _engine;

  final List<Position> _positions = [];
  final List<Alert> _alerts = [];

  /// 当前账户。V1 固定为默认账户；多账户见 V3。
  Account activeAccount = Account.defaultAccount;

  List<Position> get positions => List.unmodifiable(_positions);
  List<Alert> get alerts => List.unmodifiable(_alerts);

  /// 所有持仓的整体浮动盈亏。
  double get totalFloatingPnl =>
      _positions.fold(0.0, (s, p) => s + p.floatingPnl);

  /// 需要关注（已触发待确认）的持仓数量。
  int get attentionCount =>
      _alerts.where((a) => a.action == AlertAction.pending).length;

  Timer? _timer;

  /// 持仓 id 自增计数器，避免同一毫秒内多次建仓导致 id 碰撞。
  int _positionSeq = 0;

  /// 新建持仓。返回新建的持仓对象。
  Position addPosition({
    required String code,
    required String name,
    required double price,
    required int quantity,
    required StrategyConfig strategy,
  }) {
    final pos = Position(
      id: 'pos_${DateTime.now().millisecondsSinceEpoch}_${_positionSeq++}',
      accountId: activeAccount.id,
      code: code,
      name: name,
      fills: [Fill(price: price, quantity: quantity, time: _nowIso())],
      strategy: strategy,
    );
    pos.highestPrice = price;
    _positions.insert(0, pos);
    notifyListeners();
    return pos;
  }

  /// 手动平仓 / 删除持仓。
  void removePosition(String id) {
    _positions.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// 加仓：对已有持仓追加一笔买入，成本价自动按加权重算。
  /// 成本变化后保本/分批进度需重置（基准已变）。
  void addFill(String positionId, {required double price, required int quantity}) {
    final idx = _positions.indexWhere((p) => p.id == positionId);
    if (idx < 0) return;
    final pos = _positions[idx];
    pos.fills.add(Fill(price: price, quantity: quantity, time: _nowIso()));
    _resetStrategyState(pos);
    notifyListeners();
  }

  /// 编辑持仓：覆盖成本/数量/策略。成本与数量通过重置首笔 Fill 实现。
  /// V1 仅支持单笔建仓的修正；多笔分批建仓后的编辑见 V2。
  void updatePosition(String positionId, {required double price, required int quantity, required StrategyConfig strategy}) {
    final idx = _positions.indexWhere((p) => p.id == positionId);
    if (idx < 0) return;
    final pos = _positions[idx];
    if (pos.fills.isNotEmpty) {
      pos.fills[0] = Fill(price: price, quantity: quantity, time: pos.fills[0].time);
    } else {
      pos.fills.add(Fill(price: price, quantity: quantity, time: _nowIso()));
    }
    pos.strategy = strategy;
    pos.highestPrice = price; // 成本变了，持仓期间最高价重置为新成本
    _resetStrategyState(pos);
    notifyListeners();
  }

  /// 成本/策略变化后重置保本与分批进度（基准已变，旧进度失效）。
  void _resetStrategyState(Position pos) {
    pos.initialStopPrice = null;
    pos.breakevenStageReached = 0;
    pos.triggeredTpCount = 0;
    pos.stopBreachSince = null;
  }

  /// 清除所有已处理（已确认/已忽略）的提醒。
  void clearHandledAlerts() {
    _alerts.removeWhere((a) => a.action != AlertAction.pending);
    notifyListeners();
  }

  /// 用户确认提醒（已在券商端操作）。纯提醒模型：按提醒类型差异化处理。
  /// - 止损类(hardStop/atrStop/breakevenStop?否)、移动止盈(trailingTakeProfit)：全平 → handled。
  /// - 分批止盈(takeProfitTarget)：按本档 sellRatio 累加 closedQuantity，不平仓，剩余继续监控。
  /// - 保本告知(breakevenStop)：仅标记已读，不平仓（handled 保持 false）。
  void confirmAlert(String alertId) {
    final idx = _alerts.indexWhere((a) => a.id == alertId);
    if (idx < 0) return;
    final a = _alerts[idx];
    a.action = AlertAction.confirmed;
    final posIdx = _positions.indexWhere((p) => p.id == a.positionId);
    if (posIdx >= 0) {
      final pos = _positions[posIdx];
      pos.lastAlertId = null;
      switch (a.type) {
        case AlertType.hardStop:
        case AlertType.atrStop:
        case AlertType.trailingTakeProfit:
          pos.handled = true; // 止损/移动止盈：全平
          break;
        case AlertType.takeProfitTarget:
          // 分批止盈：按本档比例累加已平仓数量。triggeredTpCount 在评估器到档时已 +1，
          // 故本档索引 = triggeredTpCount - 1。
          final targets = pos.strategy.takeProfitTargets;
          final targetIdx = (pos.triggeredTpCount - 1).clamp(0, targets.length - 1);
          final sellQty =
              (pos.totalQuantity * targets[targetIdx].sellRatio).round();
          pos.closedQuantity += sellQty;
          if (pos.remainingQuantity <= 0) pos.handled = true;
          break;
        case AlertType.breakevenStop:
          // 保本告知：仅已读，不平仓。
          break;
        default:
          break;
      }
    }
    notifyListeners();
  }

  /// 撤销确认：恢复已了结持仓的监控（用户改主意或误确认时）。
  void reopenPosition(String positionId) {
    final idx = _positions.indexWhere((p) => p.id == positionId);
    if (idx < 0) return;
    _positions[idx].handled = false;
    notifyListeners();
  }

  /// 用户忽略提醒（继续监控）。
  void ignoreAlert(String alertId) {
    final idx = _alerts.indexWhere((a) => a.id == alertId);
    if (idx < 0) return;
    final a = _alerts[idx];
    a.action = AlertAction.ignored;
    notifyListeners();
    _clearAlertState(a.positionId);
  }

  /// 处理提醒后清空持仓的 lastAlertId，使卡片状态回归正常、允许重新触发。
  void _clearAlertState(String positionId) {
    final idx = _positions.indexWhere((p) => p.id == positionId);
    if (idx >= 0) {
      _positions[idx].lastAlertId = null;
      notifyListeners();
    }
  }

  /// 该持仓是否还有指定类型的未处理提醒（用于去重，避免每轮重复告警刷屏）。
  /// 按 (positionId, alertType) 细化，使分批止盈与止损能各自独立去重、共存。
  bool _hasPendingAlert(String positionId, AlertType type) =>
      _alerts.any((a) =>
          a.positionId == positionId &&
          a.type == type &&
          a.action == AlertAction.pending);

  /// 人工输入当前价（兜底层4）：用该价立即评估，更新止损止盈线并检测触发。
  /// 行情恢复后下一轮 tick 自动覆盖。详见产品设计文档兜底方案。
  Future<void> setManualPrice(String positionId, double price) async {
    final pos = _positions.firstWhere((p) => p.id == positionId);
    final alert = await _engine.evaluateWith(pos, price);
    _applyAlert(pos, alert);
  }

  /// 统一处理一轮评估的告警：按类型去重插入，或无触发且无任何待处理时清空标记
  /// （使卡片状态回归正常、允许下次重新触发）。
  void _applyAlert(Position pos, Alert? alert) {
    if (alert != null) {
      // 已了结（确认卖出）的仓位不再产生新告警，除非用户撤销确认恢复监控。
      // 分批止盈(takeProfitTarget)天然不重复（档位单调递增），不走去重，每档到价即提醒；
      // 止损/移动止盈/保本同类型已有 pending 则去重，避免持续触发刷屏。
      final dedup = alert.type != AlertType.takeProfitTarget;
      if (!pos.handled && (!dedup || !_hasPendingAlert(pos.id, alert.type))) {
        _alerts.insert(0, alert);
        pos.lastAlertId = alert.id;
      }
    } else if (pos.lastAlertId != null && !_hasAnyPendingAlert(pos.id)) {
      // 价格回升脱离触发区间且无任何待处理提醒：清空标记。
      pos.lastAlertId = null;
    }
    notifyListeners();
  }

  /// 该持仓是否还有任意类型的未处理提醒（用于清空 lastAlertId 判定）。
  bool _hasAnyPendingAlert(String positionId) =>
      _alerts.any((a) =>
          a.positionId == positionId && a.action == AlertAction.pending);

  /// 启动前台监控循环（默认每 15 秒一轮）。详见 3.3。
  void startMonitoring({Duration interval = const Duration(seconds: 15)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _runOnce());
    // 立即跑一轮，避免首次等待。
    _runOnce();
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _runOnce() async {
    var changed = false;
    for (final pos in _positions) {
      if (pos.isClosed) continue;
      final alert = await _engine.tick(pos);
      // tick 总会更新 currentPrice/止损止盈线/marketClosed，需刷新 UI。
      changed = true;
      if (alert != null) {
        // 分批止盈不走去重（档位单调递增天然不重复）；其余同类型 pending 则去重。
        final dedup = alert.type != AlertType.takeProfitTarget;
        if (!pos.handled && (!dedup || !_hasPendingAlert(pos.id, alert.type))) {
          _alerts.insert(0, alert);
          pos.lastAlertId = alert.id;
        }
      } else if (!pos.priceStale &&
          pos.lastAlertId != null &&
          !_hasAnyPendingAlert(pos.id)) {
        // 拿到有效行情且无触发：清空标记回归正常（盘后亦然）。
        pos.lastAlertId = null;
      }
    }
    if (changed) notifyListeners();
  }

  String _nowIso() => DateTime.now().toIso8601String();

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
