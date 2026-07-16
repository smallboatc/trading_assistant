/// 提醒类型。详见产品设计文档 3.4 提醒系统 / 第四、五章策略。
enum AlertType {
  hardStop,
  atrStop,
  chandelierStop,
  breakevenStop,
  structuralStop,
  takeProfitTarget,
  trailingTakeProfit,
  timeStop,
}

/// 用户对提醒的操作。详见 3.4 用户操作。
enum AlertAction {
  /// 尚未处理。
  pending,

  /// 用户确认已在券商端操作。
  confirmed,

  /// 用户判断暂不执行，继续监控。
  ignored,
}

/// 一次止盈/止损触发提醒。详见产品设计文档 3.4。
class Alert {
  Alert({
    required this.id,
    required this.positionId,
    required this.type,
    required this.triggeredAt,
    required this.stockCode,
    required this.stockName,
    required this.currentPrice,
    required this.floatingPnl,
    required this.message,
    required this.suggestion,
    this.action = AlertAction.pending,
  });

  final String id;
  final String positionId;
  final AlertType type;
  final DateTime triggeredAt;

  final String stockCode;
  final String stockName;
  final double currentPrice;
  final double floatingPnl;

  /// 触发条件的人类可读描述，如「移动止盈触发：最高价15.2元，当前价14.74元，回撤3%」。
  final String message;

  /// 建议操作，如「建议卖出全部仓位」。
  final String suggestion;

  AlertAction action;
}
