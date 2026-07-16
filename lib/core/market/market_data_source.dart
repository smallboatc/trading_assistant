import '../models/kline.dart';
import 'market_overview.dart';

/// 行情数据源抽象接口。详见产品设计文档 3.3 数据采集 / 第八章待讨论问题 2。
///
/// 具体实现（如对接第三方 A 股行情接口）留待后续讨论确定数据源后补充。
/// V1 使用 [MockMarketDataSource] 提供可运行的数据，便于联调 UI 与监控引擎。
abstract class MarketDataSource {
  /// 获取股票最新价。非交易时段返回上一交易日收盘价。
  Future<double?> fetchCurrentPrice(String code);

  /// 获取股票名称（用于录入时按代码自动回填）。失败返回 null。
  Future<String?> fetchName(String code);

  /// 获取最近 N 个交易日的日 K 线（按时间升序），用于计算 ATR。
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30});

  /// 获取最近 N 个月的月 K 线（按时间升序）。用于 AI 上下文注入。
  Future<List<Kline>> fetchMonthlyKlines(String code, {int count = 12});

  /// 获取股票所属板块名称。失败返回 null。
  Future<String?> fetchSector(String code);

  /// 获取大盘指数 + 板块涨跌概览。用于 AI 通用聊天上下文。
  Future<MarketOverview> fetchMarketOverview();
}
