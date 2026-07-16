import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/kline.dart';
import 'market_codes.dart';
import 'market_data_source.dart';
import 'market_overview.dart';

/// 东方财富行情数据源（主力）。详见产品设计文档 3.3 / 第八章待讨论问题 2。
///
/// 接口均为 HTTPS + UTF-8 JSON，对 Flutter 友好。已实测可达：
/// - 实时价：`push2.eastmoney.com/api/qt/stock/get`
/// - 日 K 线：`push2his.eastmoney.com/api/qt/stock/kline/get`
class EastMoneyDataSource implements MarketDataSource {
  EastMoneyDataSource({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  static const _quoteHost = 'https://push2.eastmoney.com';
  static const _klineHost = 'https://push2his.eastmoney.com';

  @override
  Future<double?> fetchCurrentPrice(String code) async {
    final secid = MarketCodes.eastmoneySecid(code);
    final url = Uri.parse(
      '$_quoteHost/api/qt/stock/get?secid=$secid'
      '&fields=f43,f57,f58&fltt=0',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final raw = data['f43'];
      if (raw == null) return null;
      // f43 为扩大 100 倍的整数价格（fltt=0），需 /100。
      return (raw as num).toDouble() / 100;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> fetchName(String code) async {
    final secid = MarketCodes.eastmoneySecid(code);
    final url = Uri.parse(
      '$_quoteHost/api/qt/stock/get?secid=$secid&fields=f58',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final name = data['f58'];
      if (name == null) return null;
      return name.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async {
    final secid = MarketCodes.eastmoneySecid(code);
    final beg = _ymd(DateTime.now().subtract(const Duration(days: 90)));
    final end = _ymd(DateTime.now());
    final url = Uri.parse(
      '$_klineHost/api/qt/stock/kline/get?secid=$secid'
      '&klt=101&fqt=1&beg=$beg&end=$end'
      '&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56,f57',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return [];
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return [];
      final klines = data['klines'] as List<dynamic>?;
      if (klines == null) return [];
      final result = <Kline>[];
      for (final line in klines) {
        final parts = (line as String).split(',');
        if (parts.length < 6) continue;
        // f51..f57: 日期,开,收,高,低,量,额
        result.add(Kline(
          date: parts[0],
          open: double.tryParse(parts[1]) ?? 0,
          close: double.tryParse(parts[2]) ?? 0,
          high: double.tryParse(parts[3]) ?? 0,
          low: double.tryParse(parts[4]) ?? 0,
          volume: double.tryParse(parts[5]) ?? 0,
        ));
      }
      return _tail(result, count);
    } catch (_) {
      return [];
    }
  }

  String _ymd(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  List<Kline> _tail(List<Kline> all, int count) =>
      all.length > count ? all.sublist(all.length - count) : all;

  // ---- AI 上下文所需扩展 ----

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async {
    // 东财无直接月K接口，取较长的日K后按月聚合。
    final daily = await fetchDailyKlines(code, count: count * 25);
    if (daily.isEmpty) return [];
    return _aggregateMonthly(daily, count);
  }

  /// 将日K按 YYYY-MM 聚合为月K：开盘=月首日开，收盘=月末日收，
  /// 最高=月内最高，最低=月内最低。
  static List<Kline> _aggregateMonthly(List<Kline> daily, int count) {
    final byMonth = <String, List<Kline>>{};
    for (final k in daily) {
      // date 形如 "2026-07-15"，取前 7 位 "2026-07"。
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
    final secid = MarketCodes.eastmoneySecid(code);
    final url = Uri.parse(
      '$_quoteHost/api/qt/stock/get?secid=$secid&fields=f127',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final sector = data['f127'];
      if (sector == null) return null;
      return sector.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<MarketOverview> fetchMarketOverview() async {
    final indices = await _fetchIndices();
    final sectors = await _fetchSectorRanking();
    if (indices.isEmpty && sectors.isEmpty) return const MarketOverview();
    sectors.sort((a, b) => b.changePercent.compareTo(a.changePercent));
    final top = sectors.length > 5 ? sectors.sublist(0, 5) : sectors;
    final bottom = sectors.length > 10
        ? sectors.sublist(sectors.length - 5).reversed.toList()
        : (sectors.length > 5 ? sectors.sublist(5).reversed.toList() : <SectorQuote>[]);
    return MarketOverview(
      indices: indices,
      topSectors: top,
      bottomSectors: bottom,
    );
  }

  /// 大盘指数：用日K接口取最新收盘价 + 涨跌幅。
  /// ulist.np 接口不返回价格字段，改用 push2his 日K取最近两根算涨跌幅。
  Future<List<IndexQuote>> _fetchIndices() async {
    const secids = ['1.000001', '0.399001', '0.399006'];
    const names = ['上证指数', '深证成指', '创业板指'];
    final result = <IndexQuote>[];
    for (var i = 0; i < secids.length; i++) {
      final quote = await _fetchIndexQuote(secids[i], names[i]);
      if (quote != null) result.add(quote);
    }
    return result;
  }

  /// 用日K接口取指数最新收盘价，用最近两根 K 线算涨跌幅。
  Future<IndexQuote?> _fetchIndexQuote(String secid, String name) async {
    final url = Uri.parse(
      '$_klineHost/api/qt/stock/kline/get?secid=$secid'
      '&klt=101&fqt=1&beg=0&end=20500101'
      '&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final klines = data['klines'] as List<dynamic>?;
      if (klines == null || klines.length < 2) return null;
      // 最近两根：倒数第二根 = 昨收，最后一根 = 今日。
      final lastParts = (klines.last as String).split(',');
      final prevParts = (klines[klines.length - 2] as String).split(',');
      if (lastParts.length < 3 || prevParts.length < 3) return null;
      final close = double.tryParse(lastParts[2]) ?? 0;
      final prevClose = double.tryParse(prevParts[2]) ?? 0;
      if (close == 0 || prevClose == 0) return null;
      final pct = (close - prevClose) / prevClose;
      return IndexQuote(
        name: name,
        code: secid.split('.').last,
        price: close,
        changePercent: pct,
      );
    } catch (_) {
      return null;
    }
  }

  /// 板块涨跌排行（东财行业板块）。实测 clist + fltt=1 返回 f2/f3。
  Future<List<SectorQuote>> _fetchSectorRanking() async {
    final url = Uri.parse(
      '$_quoteHost/api/qt/clist/get'
      '?pn=1&pz=20&po=1&np=1&fltt=1&fs=m:90+t:2'
      '&fields=f2,f3,f14',
    );
    try {
      final res = await http.get(url).timeout(timeout);
      if (res.statusCode != 200) return [];
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data']?['diff'] as List<dynamic>?;
      if (data == null) return [];
      return data.map((e) {
        final item = e as Map<String, dynamic>;
        final pct = (item['f3'] as num?)?.toDouble() ?? 0;
        return SectorQuote(
          name: item['f14']?.toString() ?? '未知板块',
          changePercent: pct / 100,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
