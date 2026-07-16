// 冒烟测试：App 能正常启动并展示空持仓状态。
// 详见产品设计文档 3.5 监控面板（空状态）。
//
// 注入 _FakeDataSource 避免测试打真实网络（东财/腾讯）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trading_assistant/core/market/market_data_source.dart';
import 'package:trading_assistant/core/market/market_overview.dart';
import 'package:trading_assistant/core/models/kline.dart';
import 'package:trading_assistant/main.dart';

class _FakeDataSource implements MarketDataSource {
  @override
  Future<double?> fetchCurrentPrice(String code) async => 10.0;

  @override
  Future<String?> fetchName(String code) async => '测试股票';

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async {
    return List.generate(
      count,
      (i) => Kline(
        date: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
        open: 10.0 + i * 0.1,
        high: 10.5 + i * 0.1,
        low: 9.5 + i * 0.1,
        close: 10.0 + i * 0.1,
        volume: 10000,
      ),
    );
  }

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async =>
      List.generate(
        count,
        (i) => Kline(
          date: '2025-${(i + 1).toString().padLeft(2, '0')}',
          open: 9.0 + i * 0.2,
          high: 10.0 + i * 0.2,
          low: 8.5 + i * 0.2,
          close: 9.5 + i * 0.2,
        ),
      );

  @override
  Future<String?> fetchSector(String code) async => '测试板块';

  @override
  Future<MarketOverview> fetchMarketOverview() async =>
      const MarketOverview();
}

void main() {
  testWidgets('App 启动后展示空持仓提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      TradingAssistantApp(dataSource: _FakeDataSource()),
    );
    await tester.pump();

    expect(find.text('交易助手'), findsOneWidget);
    expect(find.text('还没有在管持仓'), findsOneWidget);
    expect(find.text('录入第一笔持仓'), findsOneWidget);
  });
}
