/// A 股交易时段判断工具。详见产品设计文档 3.3（盘后停止监控，盘前自动恢复）。
///
/// V1 使用固定规则：周一至周五 09:30-11:30 / 13:00-15:00（北京时间）。
/// 节假日、涨跌停、停牌等特殊情况见文档第八章待讨论问题 10/11，暂未处理。
class TradingSessions {
  TradingSessions._();

  /// A 股是否处于交易时段。[now] 任意时区均可，内部统一折算为北京时间。
  static bool isTradingTime(DateTime now) {
    // 统一用北京时间（UTC+8），不受设备时区影响（如用户出差/在海外）。
    final bj = now.toUtc().add(const Duration(hours: 8));
    // 周六周日休市。
    if (bj.weekday == DateTime.saturday || bj.weekday == DateTime.sunday) {
      return false;
    }
    final t = bj.hour * 60 + bj.minute;
    // 09:30 - 11:30
    if (t >= 570 && t <= 690) return true;
    // 13:00 - 15:00
    if (t >= 780 && t <= 900) return true;
    return false;
  }
}
