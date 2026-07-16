/// 大盘指数行情。
class IndexQuote {
  const IndexQuote({
    required this.name,
    required this.code,
    required this.price,
    required this.changePercent,
  });

  /// 指数名称（上证指数 / 深证成指 / 创业板指）。
  final String name;

  /// 指数代码。
  final String code;

  /// 最新点位。
  final double price;

  /// 涨跌幅（小数，如 0.0123 = +1.23%）。
  final double changePercent;
}

/// 板块行情。
class SectorQuote {
  const SectorQuote({
    required this.name,
    required this.changePercent,
    this.leadingStock,
  });

  final String name;
  final double changePercent;

  /// 领涨股名称（可选）。
  final String? leadingStock;
}

/// 市场概览：大盘指数 + 板块涨跌。用于 AI 通用聊天上下文注入。
class MarketOverview {
  const MarketOverview({
    this.indices = const [],
    this.topSectors = const [],
    this.bottomSectors = const [],
  });

  /// 主要指数（上证、深证、创业板）。
  final List<IndexQuote> indices;

  /// 涨幅前 N 板块。
  final List<SectorQuote> topSectors;

  /// 跌幅前 N 板块。
  final List<SectorQuote> bottomSectors;

  bool get isEmpty => indices.isEmpty && topSectors.isEmpty;
}
