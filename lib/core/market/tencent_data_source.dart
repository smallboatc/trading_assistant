import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/kline.dart';
import 'market_codes.dart';
import 'market_data_source.dart';
import 'market_overview.dart';

/// 腾讯行情数据源（降级）。详见产品设计文档 3.3 / 第八章待讨论问题 2。
///
/// 实时价接口返回 GBK 文本，用 latin1 解码后按 `~` 分隔取价格字段，规避
/// GBK 解码依赖（价格均为 ASCII，名称乱码不影响取价）。日 K 线接口返回
/// UTF-8 JSON。
class TencentDataSource implements MarketDataSource {
  TencentDataSource({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  static const _quoteHost = 'https://qt.gtimg.cn';
  static const _klineHost = 'https://web.ifzq.gtimg.cn';

  @override
  Future<double?> fetchCurrentPrice(String code) async {
    final tc = MarketCodes.tencentCode(code);
    final url = Uri.parse('$_quoteHost/q=$tc');
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      // GBK 文本：latin1 解码不报错，价格字段为 ASCII。
      final body = latin1.decode(res.bodyBytes);
      // 形如 v_sh600519="1~名称~代码~1251.06~1214.88~...";
      final eq = body.indexOf('=');
      if (eq < 0) return null;
      final payload = body
          .substring(eq + 1)
          .replaceAll('"', '')
          .replaceAll(';', '')
          .trim();
      // 锚定 "~<代码>~"（ASCII，不会落在 GBK 名称字节内），取其后的字段为当前价。
      // 避免按 "~" 全切——GBK 尾字节可能为 0x7E('~')，会在名称中间误切导致索引错位。
      final anchor = '~$code~';
      final idx = payload.indexOf(anchor);
      if (idx < 0) return null;
      final priceStr = payload.substring(idx + anchor.length).split('~').first;
      return double.tryParse(priceStr);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> fetchName(String code) async {
    // 腾讯实时报价为 GBK 文本，名称字段 latin1 解码会乱码，不可用。
    // 返回 null，由 ResilientMarketDataSource 降级东财取 UTF-8 名称。
    return null;
  }

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async {
    final tc = MarketCodes.tencentCode(code);
    final beg = _ymd(DateTime.now().subtract(const Duration(days: 120)));
    final end = _ymd(DateTime.now());
    final url = Uri.parse(
      '$_klineHost/appstock/app/fqkline/get'
      '?param=$tc,day,$beg,$end,$count,qfq',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return [];
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return [];
      final perStock = data[tc] as Map<String, dynamic>?;
      if (perStock == null) return [];
      final day = perStock['qfqday'] ?? perStock['day'];
      if (day is! List) return [];
      final result = <Kline>[];
      for (final item in day) {
        if (item is! List || item.length < 6) continue;
        // [日期,开,收,高,低,量]
        result.add(Kline(
          date: item[0].toString(),
          open: double.tryParse(item[1].toString()) ?? 0,
          close: double.tryParse(item[2].toString()) ?? 0,
          high: double.tryParse(item[3].toString()) ?? 0,
          low: double.tryParse(item[4].toString()) ?? 0,
          volume: double.tryParse(item[5].toString()) ?? 0,
        ));
      }
      return _tail(result, count);
    } catch (_) {
      return [];
    }
  }

  // 腾讯 param 日期需带横线 YYYY-MM-DD，否则返回 param error。
  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<Kline> _tail(List<Kline> all, int count) =>
      all.length > count ? all.sublist(all.length - count) : all;

  // ---- AI 上下文所需扩展（降级实现）----

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async {
    final daily = await fetchDailyKlines(code, count: count * 25);
    if (daily.isEmpty) return [];
    return _aggregateMonthly(daily, count);
  }

  static List<Kline> _aggregateMonthly(List<Kline> daily, int count) {
    final byMonth = <String, List<Kline>>{};
    for (final k in daily) {
      final month = k.date.length >= 7 ? k.date.substring(0, 7) : k.date;
      byMonth.putIfAbsent(month, () => []).add(k);
    }
    final months = byMonth.keys.toList()..sort();
    final recent = months.length > count
        ? months.sublist(months.length - count)
        : months;
    return recent.map((m) {
      final ks = byMonth[m]!;
      return Kline(
        date: m,
        open: ks.first.open,
        close: ks.last.close,
        high: ks.map((k) => k.high).reduce((a, b) => a > b ? a : b),
        low: ks.map((k) => k.low).reduce((a, b) => a < b ? a : b),
        volume: ks.fold<double>(0, (s, k) => s + k.volume),
      );
    }).toList();
  }

  @override
  Future<String?> fetchSector(String code) async {
    // 腾讯接口无直接板块字段，降级返回 null（由 resilient 切东财）。
    return null;
  }

  @override
  Future<MarketOverview> fetchMarketOverview() async {
    // 腾讯可取指数，板块排行无简单接口，降级只返回指数。
    final indices = await _fetchIndices();
    return MarketOverview(indices: indices);
  }

  /// 腾讯大盘指数：sh000001、sz399001、sz399006。
  ///
  /// 改用日 K 接口取最近两根收盘价算涨跌幅，规避实时报价 GBK 文本按 `~`
  /// 全切可能误切（GBK 第二字节为 0x7E）的问题，与实时价取价的锚定法保持一致。
  Future<List<IndexQuote>> _fetchIndices() async {
    const codes = ['sh000001', 'sz399001', 'sz399006'];
    const names = ['上证指数', '深证成指', '创业板指'];
    final result = <IndexQuote>[];
    for (var i = 0; i < codes.length; i++) {
      final quote = await _fetchIndexQuote(codes[i], names[i]);
      if (quote != null) result.add(quote);
    }
    return result;
  }

  /// 用日 K 接口取指数最新收盘价，用最近两根 K 线算涨跌幅。
  /// 指数代码已含 sh/sz 前缀，直接拼 param，不走 [tencentCode]（后者按股票前缀）。
  Future<IndexQuote?> _fetchIndexQuote(String tc, String name) async {
    final beg = _ymd(DateTime.now().subtract(const Duration(days: 10)));
    final end = _ymd(DateTime.now());
    final url = Uri.parse(
      '$_klineHost/appstock/app/fqkline/get'
      '?param=$tc,day,$beg,$end,10,qfq',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final perStock = data[tc] as Map<String, dynamic>?;
      if (perStock == null) return null;
      final day = perStock['qfqday'] ?? perStock['day'];
      if (day is! List || day.length < 2) return null;
      final last = day.last as List;
      final prev = day[day.length - 2] as List;
      if (last.length < 3 || prev.length < 3) return null;
      final close = double.tryParse(last[2].toString()) ?? 0;
      final prevClose = double.tryParse(prev[2].toString()) ?? 0;
      if (close == 0 || prevClose == 0) return null;
      return IndexQuote(
        name: name,
        code: tc,
        price: close,
        changePercent: (close - prevClose) / prevClose,
      );
    } catch (_) {
      return null;
    }
  }
}
