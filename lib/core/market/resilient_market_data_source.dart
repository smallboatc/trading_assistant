import '../models/kline.dart';
import 'eastmoney_data_source.dart';
import 'tencent_data_source.dart';
import 'market_data_source.dart';
import 'market_overview.dart';

/// 组合行情数据源：按数据类型分源，规避东财高频限流。
///
/// 实测东财实时价接口限流极严（连续3-4次封IP），腾讯实时价宽松；
/// 但东财数据更全（板块只有东财有）、格式友好（UTF-8 JSON）。
/// 故按数据类型分源：
/// - 实时价：腾讯主力（15秒高频，腾讯宽松）→ 东财降级
/// - 日K/月K：东财主力（低频，东财全）→ 腾讯降级
/// - 板块/所属板块：东财（腾讯无）
/// - 名称：东财（UTF-8，腾讯GBK易乱码）
class ResilientMarketDataSource implements MarketDataSource {
  ResilientMarketDataSource({
    EastMoneyDataSource? eastmoney,
    TencentDataSource? tencent,
  })  : _eastmoney = eastmoney ?? EastMoneyDataSource(),
        _tencent = tencent ?? TencentDataSource();

  final EastMoneyDataSource _eastmoney;
  final TencentDataSource _tencent;

  /// 日K/月K 缓存：按 (code, 交易日) 缓存，同交易日不重复拉（减少东财限流）。
  /// key = code，value = (K线最后日期, K线列表)。交易日变化时刷新。
  final Map<String, (String, List<Kline>)> _dailyKlineCache = {};
  final Map<String, (String, List<Kline>)> _monthlyKlineCache = {};

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  @override
  Future<double?> fetchCurrentPrice(String code) async {
    // 腾讯主力（高频宽松），东财降级。
    final p = await _tencent.fetchCurrentPrice(code);
    if (p != null) return p;
    return _eastmoney.fetchCurrentPrice(code);
  }

  @override
  Future<String?> fetchName(String code) async {
    // 东财主力（UTF-8 名称），腾讯降级（GBK 名称易乱码，实际返回 null）。
    final p = await _eastmoney.fetchName(code);
    if (p != null) return p;
    return _tencent.fetchName(code);
  }

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async {
    // 同交易日命中缓存，避免重复请求东财触发限流。
    final today = _todayKey();
    final cached = _dailyKlineCache[code];
    if (cached != null && cached.$1 == today && cached.$2.length >= count) {
      return cached.$2.sublist(cached.$2.length - count);
    }
    // 东财主力（低频，数据全），腾讯降级。
    final p = await _eastmoney.fetchDailyKlines(code, count: count);
    final result = p.isNotEmpty ? p : await _tencent.fetchDailyKlines(code, count: count);
    if (result.isNotEmpty) {
      _dailyKlineCache[code] = (today, result);
    }
    return result;
  }

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async {
    final today = _todayKey();
    final cached = _monthlyKlineCache[code];
    if (cached != null && cached.$1 == today && cached.$2.length >= count) {
      return cached.$2.sublist(cached.$2.length - count);
    }
    final p = await _eastmoney.fetchMonthlyKlines(code, count: count);
    final result = p.isNotEmpty ? p : await _tencent.fetchMonthlyKlines(code, count: count);
    if (result.isNotEmpty) {
      _monthlyKlineCache[code] = (today, result);
    }
    return result;
  }

  @override
  Future<String?> fetchSector(String code) async {
    // 板块只有东财有，腾讯返回 null。
    return _eastmoney.fetchSector(code);
  }

  @override
  Future<MarketOverview> fetchMarketOverview() async {
    // TODO: AI 上下文大盘/板块数据偶发拉不到（东财限流 + 腾讯降级仍可能空），
    //   导致问大盘时 AI 无数据。需接入更稳定的行情源（官方接口/服务端中转）彻底解决。
    final p = await _eastmoney.fetchMarketOverview();
    // 东财指数缺失（限流）但板块有：用腾讯补指数，避免大盘数据全空。
    if (p.indices.isEmpty && p.topSectors.isNotEmpty) {
      final t = await _tencent.fetchMarketOverview();
      if (t.indices.isNotEmpty) {
        return MarketOverview(
          indices: t.indices,
          topSectors: p.topSectors,
          bottomSectors: p.bottomSectors,
        );
      }
    }
    if (!p.isEmpty) return p;
    return _tencent.fetchMarketOverview();
  }
}
