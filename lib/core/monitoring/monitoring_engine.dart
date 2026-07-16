import '../market/market_data_source.dart';
import '../market/trading_sessions.dart';
import '../models/alert.dart';
import '../models/kline.dart';
import '../models/position.dart';
import '../strategy/strategy_evaluator.dart';

/// 实时监控引擎。详见产品设计文档 3.3 实时监控引擎。
///
/// 周期性拉取行情、更新持仓动态状态、检测触发条件并产生提醒。
/// V1 为前台主动轮询的同步实现；后台保活 / 服务端推送见第八章待讨论问题 4/5。
class MonitoringEngine {
  MonitoringEngine({required this.dataSource});

  final MarketDataSource dataSource;

  /// 缓存各股票最近一次拉取的日 K，避免每个周期都请求全量 K 线。
  final Map<String, List<KlineCached>> _klineCache = {};

  /// 单次监控周期：拉行情、更新持仓状态并返回（可能为空的）触发提醒。
  Future<Alert?> tick(Position position) async {
    final trading = TradingSessions.isTradingTime(DateTime.now());
    position.marketClosed = !trading;

    final price = await dataSource.fetchCurrentPrice(position.code);
    if (price == null) {
      // 两源全挂：保留上一个已知价（天然缓存），标记延迟，不产生新触发。
      if (position.currentPrice != null) position.priceStale = true;
      return null;
    }
    position.currentPrice = price;
    position.priceStale = false;

    // 盘后仍算止损止盈线（让 UI 有数据），但不触发提醒。
    // 详见 3.3「盘后停止监控，盘前自动恢复」。
    if (!trading) {
      await _evaluate(position, price,
          '${position.id}_closed_${DateTime.now().millisecondsSinceEpoch}',
          immediate: false, detect: false);
      return null;
    }
    return _evaluate(position, price,
        '${position.id}_${DateTime.now().millisecondsSinceEpoch}',
        immediate: false);
  }

  /// 用给定价格（如人工输入）评估持仓：复用已缓存日 K，更新止损止盈线
  /// 并检测触发，不拉取行情。详见兜底层4（行情中断时人工输入）。
  Future<Alert?> evaluateWith(Position position, double price) async {
    position.currentPrice = price;
    position.priceStale = false;
    return _evaluate(position, price,
        '${position.id}_manual_${DateTime.now().millisecondsSinceEpoch}',
        immediate: true);
  }

  Future<Alert?> _evaluate(Position position, double price, String alertId,
      {required bool immediate, bool detect = true}) async {
    final klines = await _ensureKlines(position.code);
    if (klines.isEmpty) return null;
    final evaluator = StrategyEvaluator(position);
    final result = evaluator.evaluate(
      klines: klines.map((c) => c.toKline()).toList(),
      currentPrice: price,
      alertId: alertId,
      immediate: immediate,
      detect: detect,
    );
    position.stopPrice = result.stopPrice;
    position.takeProfitPrice = result.takeProfitPrice;
    return result.alert;
  }

  Future<List<KlineCached>> _ensureKlines(String code) async {
    final cached = _klineCache[code];
    // 简单缓存策略：同一进程内只拉一次。真实场景需按交易日刷新。
    if (cached != null && cached.isNotEmpty) return cached;
    final raw = await dataSource.fetchDailyKlines(code, count: 30);
    final list = raw.map(KlineCached.fromKline).toList();
    _klineCache[code] = list;
    return list;
  }
}

/// 内部 K 线缓存包装（与领域模型 [Kline] 解耦）。
class KlineCached {
  KlineCached({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory KlineCached.fromKline(Kline k) => KlineCached(
        date: k.date,
        open: k.open,
        high: k.high,
        low: k.low,
        close: k.close,
        volume: k.volume,
      );

  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  Kline toKline() => Kline(
        date: date,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      );
}
