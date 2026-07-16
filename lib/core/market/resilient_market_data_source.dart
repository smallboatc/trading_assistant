import '../models/kline.dart';
import 'eastmoney_data_source.dart';
import 'tencent_data_source.dart';
import 'market_data_source.dart';
import 'market_overview.dart';

/// 组合行情数据源：东财主力 + 腾讯降级。详见产品设计文档兜底方案。
///
/// 每个方法先请求东财；返回 null/空（含内部已捕获的异常/超时）则降级到
/// 腾讯；都失败返回 null/空。单源内部已 try/catch，这里只按返回值判断。
class ResilientMarketDataSource implements MarketDataSource {
  ResilientMarketDataSource({
    EastMoneyDataSource? primary,
    TencentDataSource? fallback,
  })  : _primary = primary ?? EastMoneyDataSource(),
        _fallback = fallback ?? TencentDataSource();

  final EastMoneyDataSource _primary;
  final TencentDataSource _fallback;

  @override
  Future<double?> fetchCurrentPrice(String code) async {
    final p = await _primary.fetchCurrentPrice(code);
    if (p != null) return p;
    return _fallback.fetchCurrentPrice(code);
  }

  @override
  Future<String?> fetchName(String code) async {
    final p = await _primary.fetchName(code);
    if (p != null) return p;
    return _fallback.fetchName(code);
  }

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async {
    final p = await _primary.fetchDailyKlines(code, count: count);
    if (p.isNotEmpty) return p;
    return _fallback.fetchDailyKlines(code, count: count);
  }

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async {
    final p = await _primary.fetchMonthlyKlines(code, count: count);
    if (p.isNotEmpty) return p;
    return _fallback.fetchMonthlyKlines(code, count: count);
  }

  @override
  Future<String?> fetchSector(String code) async {
    final p = await _primary.fetchSector(code);
    if (p != null) return p;
    return _fallback.fetchSector(code);
  }

  @override
  Future<MarketOverview> fetchMarketOverview() async {
    final p = await _primary.fetchMarketOverview();
    // 东财指数缺失（限流）但板块有：用腾讯补指数，避免大盘数据全空。
    if (p.indices.isEmpty && p.topSectors.isNotEmpty) {
      final t = await _fallback.fetchMarketOverview();
      if (t.indices.isNotEmpty) {
        return MarketOverview(
          indices: t.indices,
          topSectors: p.topSectors,
          bottomSectors: p.bottomSectors,
        );
      }
    }
    if (!p.isEmpty) return p;
    return _fallback.fetchMarketOverview();
  }
}
