import 'fill.dart';
import 'strategy_config.dart';

/// 持仓状态标记。详见产品设计文档 3.5 监控面板「状态标记」。
enum PositionStatus {
  /// 正常持有。
  normal,

  /// 接近止损线。
  nearStop,

  /// 接近止盈线。
  nearTakeProfit,

  /// 已触发待确认。
  triggered,
}

/// 一个在管持仓的完整状态对象。详见产品设计文档 3.1 持仓状态管理。
///
/// 包含静态录入信息（代码、买入记录、策略）与动态监控状态（当前价、
/// 最高价、止盈止损线、浮盈等）。监控引擎负责更新动态字段。
class Position {
  Position({
    required this.id,
    required this.accountId,
    required this.code,
    required this.name,
    required List<Fill> fills,
    required this.strategy,
    DateTime? createdAt,
  })  : fills = List<Fill>.of(fills),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String accountId;

  /// 股票代码（如 600519）。
  final String code;

  /// 股票名称（如 贵州茅台）。
  final String name;

  /// 买入成交记录（支持分批建仓）。加仓时追加。
  final List<Fill> fills;

  /// 止盈止损策略。编辑持仓时可替换。
  StrategyConfig strategy;

  /// 建仓时间（取首笔买入或显式传入）。
  final DateTime createdAt;

  // ---- 动态监控状态 ----

  /// 当前价。尚未拉取行情时为 null。
  double? currentPrice;

  /// 行情是否延迟（两源全挂时为 true，保留上一个已知价）。
  bool priceStale = false;

  /// 持仓期间最高价（用于钱德勒止损 / 移动止盈）。建仓时初始化为成本价。
  double highestPrice = 0;

  /// 当前止损线（动态值，由策略评估器更新）。
  double? stopPrice;

  /// 当前止盈线（动态值）。
  double? takeProfitPrice;

  /// 已平仓数量（分批止盈 / 手动减仓后累加）。
  int closedQuantity = 0;

  /// 最近一次触发的提醒。
  String? lastAlertId;

  /// 进场初始止损价（首次评估时记录的 max(硬止损, ATR止损)）。
  /// 用于保本止损风险额度计算，避免用动态止损导致保本阶段漂移。
  /// 加仓/编辑成本后重置为 null，下次评估重新记录。
  double? initialStopPrice;

  /// 已达到的最高保本阶段（0=未达，1=保本，2=锁半，3=锁70%）。只升不降。
  /// 用此值算保本止损线，防止浮盈回落后保本线下移。
  int breakevenStageReached = 0;

  /// 止损首次破位时间戳。用于「维持N分钟确认」：价格跌破止损线时记录，
  /// 连续在下方达确认时长才真触发告警；回升则清空。null=未破位。
  DateTime? stopBreachSince;

  /// 分批止盈已触发的档数（0=未触发，1=已触发第1档，...）。
  /// 到档提醒后递增；确认时据此次档累加 closedQuantity。
  int triggeredTpCount = 0;

  /// 用户确认止损/止盈提醒后置位：表示已在券商端了结，监控跳过此仓位。
  /// 可经「撤销确认」恢复监控。
  bool handled = false;

  /// 当前是否处于非交易时段（盘后/周末）。UI 据此提示「显示最近收盘价」。
  bool marketClosed = false;

  // ---- 衍生计算 ----

  /// 加权成本价。
  double get costPrice => StrategyConfig.weightedCost(fills);

  /// 总买入数量。
  int get totalQuantity => fills.fold<int>(0, (s, f) => s + f.quantity);

  /// 剩余仓位。
  int get remainingQuantity => totalQuantity - closedQuantity;

  /// 当前浮动盈亏（金额）。未持仓、已了结或无行情时为 0。
  double get floatingPnl {
    if (handled || currentPrice == null || remainingQuantity <= 0) return 0;
    return (currentPrice! - costPrice) * remainingQuantity;
  }

  /// 当前浮动盈亏（百分比）。无成本价或无行情时为 0。
  double get floatingPnlPercent {
    if (currentPrice == null || costPrice == 0) return 0;
    return (currentPrice! - costPrice) / costPrice;
  }

  /// 距离止损线的空间（百分比，正数表示还有空间）。无止损线时返回 null。
  double? get distanceToStop {
    if (stopPrice == null || currentPrice == null || currentPrice == 0) {
      return null;
    }
    return (currentPrice! - stopPrice!) / currentPrice!;
  }

  /// 距离止盈线的空间（百分比）。无止盈线时返回 null。
  double? get distanceToTakeProfit {
    if (takeProfitPrice == null || currentPrice == null || currentPrice == 0) {
      return null;
    }
    return (takeProfitPrice! - currentPrice!) / currentPrice!;
  }

  /// 持仓时长（天）。
  int get holdingDays => DateTime.now().difference(createdAt).inDays;

  /// 是否已全部平仓（含用户确认提醒后的了结）。
  bool get isClosed => remainingQuantity <= 0 || handled;

  @override
  String toString() =>
      'Position($code $name cost=$costPrice cur=$currentPrice '
      'stop=$stopPrice tp=$takeProfitPrice pnl=$floatingPnl)';
}
