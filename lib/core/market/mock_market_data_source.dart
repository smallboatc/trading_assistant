import '../models/kline.dart';
import 'market_data_source.dart';
import 'market_overview.dart';

/// 行情数据源的内存 Mock 实现。
///
/// 仅用于 V1 联调：为给定代码生成一段稳定的伪日 K，并在每次取最新价时
/// 在「基准价」附近做小幅随机波动。**真实行情接入见第八章待讨论问题 2。**
class MockMarketDataSource implements MarketDataSource {
  MockMarketDataSource({this.seed = 42});

  final int seed;

  /// 代码 -> 基准价（用于生成可识别的伪行情）。
  static const Map<String, double> _basePrices = {
    '600519': 1680.0,
    '000001': 13.5,
    '300750': 210.0,
  };

  double _baseFor(String code) =>
      _basePrices[code] ?? 10.0 + (code.hashCode.abs() % 500) / 10.0;

  @override
  Future<double?> fetchCurrentPrice(String code) async {
    // 用代码哈希作为确定性的「波动」，避免依赖 dart:math 的 Random。
    final base = _baseFor(code);
    final wobble = ((code.hashCode.abs() % 100) - 50) / 1000.0; // ±5%
    return base * (1 + wobble);
  }

  @override
  Future<String?> fetchName(String code) async {
    const map = {'600519': '贵州茅台', '000001': '平安银行', '300750': '宁德时代'};
    return map[code] ?? '示例股票';
  }

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async {
    final base = _baseFor(code);
    final klines = <Kline>[];
    var price = base * 0.95;
    // 确定性的伪走势，向上漂移叠加锯齿。
    for (var i = 0; i < count; i++) {
      final step = ((code.hashCode.abs() + i * 7) % 17 - 8) / 1000.0;
      final open = price;
      final close = price * (1 + step);
      final high = (open > close ? open : close) * 1.005;
      final low = (open < close ? open : close) * 0.995;
      final day = DateTime.now().subtract(Duration(days: count - i));
      klines.add(Kline(
        date: _ymd(day),
        open: _round(open),
        high: _round(high),
        low: _round(low),
        close: _round(close),
        volume: 100000 + (i * 1234 % 50000),
      ));
      price = close;
    }
    return klines;
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  // ---- AI 上下文所需扩展（Mock 实现）----

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async {
    final base = _baseFor(code);
    final klines = <Kline>[];
    var price = base * 0.85;
    for (var i = 0; i < count; i++) {
      final step = ((code.hashCode.abs() + i * 13) % 11 - 5) / 100.0;
      final open = price;
      final close = price * (1 + step);
      klines.add(Kline(
        date: '2025-${(i + 1).toString().padLeft(2, '0')}',
        open: _round(open),
        high: _round(open > close ? open * 1.03 : close * 1.03),
        low: _round(open < close ? open * 0.97 : close * 0.97),
        close: _round(close),
        volume: 1000000 + i * 100000,
      ));
      price = close;
    }
    return klines;
  }

  @override
  Future<String?> fetchSector(String code) async {
    const map = {'600519': '白酒', '000001': '银行', '300750': '电池'};
    return map[code] ?? '综合';
  }

  @override
  Future<MarketOverview> fetchMarketOverview() async {
    return const MarketOverview(
      indices: [
        IndexQuote(name: '上证指数', code: '000001', price: 3105.22, changePercent: -0.0045),
        IndexQuote(name: '深证成指', code: '399001', price: 9876.54, changePercent: 0.0012),
        IndexQuote(name: '创业板指', code: '399006', price: 1987.65, changePercent: 0.0089),
      ],
      topSectors: [
        SectorQuote(name: '白酒', changePercent: 0.021),
        SectorQuote(name: '新能源', changePercent: 0.018),
        SectorQuote(name: '半导体', changePercent: 0.015),
      ],
      bottomSectors: [
        SectorQuote(name: '房地产', changePercent: -0.015),
        SectorQuote(name: '银行', changePercent: -0.008),
      ],
    );
  }
}
