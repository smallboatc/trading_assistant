/// 一笔买入成交记录。
///
/// 支持分批建仓：一个持仓可由多笔 [Fill] 组成，加权成本价由持仓自动计算。
/// 详见产品设计文档 3.1 持仓管理「分批建仓支持」。
class Fill {
  const Fill({
    required this.price,
    required this.quantity,
    required this.time,
  });

  /// 买入价（元）。
  final double price;

  /// 买入数量（股）。A 股最小单位为 100 股（一手）。
  final int quantity;

  /// 买入时间，ISO 字符串。
  final String time;

  @override
  String toString() => 'Fill(price=$price, qty=$quantity, time=$time)';
}
