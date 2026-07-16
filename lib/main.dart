import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'presentation/screens/alerts_screen.dart';
import 'presentation/screens/chat_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/history_screen.dart';
import 'core/market/market_data_source.dart';
import 'core/market/market_overview.dart';
import 'core/market/resilient_market_data_source.dart';
import 'core/models/kline.dart';
import 'core/models/strategy_config.dart';
import 'presentation/theme/app_theme.dart';
import 'state/app_store.dart';
import 'state/chat_store.dart';

void main() {
  // 预览模式：注入假数据源 + 预置持仓，用于截图验证 UI（--dart-define=PREVIEW=true）。
  const preview = bool.fromEnvironment('PREVIEW', defaultValue: false);
  runApp(TradingAssistantApp(preview: preview));
}

class TradingAssistantApp extends StatelessWidget {
  const TradingAssistantApp({super.key, this.dataSource, this.preview = false});

  /// 行情数据源。生产默认东财+腾讯组合源；测试可注入 fake 避免打真实网络。
  final MarketDataSource? dataSource;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final src = preview
        ? _PreviewDataSource()
        : (dataSource ?? ResilientMarketDataSource());
    return MultiProvider(
      providers: [
        Provider<MarketDataSource>.value(value: src),
        ChangeNotifierProvider(
          create: (_) {
            final store = AppStore(dataSource: src);
            if (preview) {
              _seedPreview(store);
            } else {
              // 先加载本地持久化数据，再启动监控（监控依赖已加载的持仓）。
              store.init().then((_) => store.startMonitoring());
            }
            return store;
          },
        ),
        ChangeNotifierProxyProvider<AppStore, ChatStore>(
          create: (ctx) => ChatStore(
            dataSource: src,
            appStore: ctx.read<AppStore>(),
          ),
          update: (_, appStore, prev) => prev ?? ChatStore(
            dataSource: src,
            appStore: appStore,
          ),
        ),
      ],
      child: MaterialApp(
        title: '交易助手',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _HomeShell(),
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    DashboardScreen(),
    AlertsScreen(),
    ChatScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final attention = context.select<AppStore, int>((s) => s.attentionCount);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(CupertinoIcons.chart_bar_alt_fill),
            selectedIcon: Icon(CupertinoIcons.chart_bar_alt_fill),
            label: '监控',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: attention > 0,
              label: Text('$attention'),
              child: const Icon(CupertinoIcons.bell),
            ),
            selectedIcon: Badge(
              isLabelVisible: attention > 0,
              label: Text('$attention'),
              child: const Icon(CupertinoIcons.bell_fill),
            ),
            label: '提醒',
          ),
          const NavigationDestination(
            icon: Icon(CupertinoIcons.chat_bubble),
            selectedIcon: Icon(CupertinoIcons.chat_bubble_fill),
            label: 'AI',
          ),
          const NavigationDestination(
            icon: Icon(CupertinoIcons.clock),
            label: '历史',
          ),
        ],
      ),
    );
  }
}

// ---- 仅用于截图预览的临时辅助，验证后删除 ----

void _seedPreview(AppStore store) {
  store.addPosition(
    code: '600519',
    name: '贵州茅台',
    price: 1214.88,
    quantity: 100,
    strategy: StrategyConfig.fromPreset(PresetPlan.swingStandard),
  );
  store.addPosition(
    code: '300750',
    name: '宁德时代',
    price: 210.50,
    quantity: 200,
    strategy: StrategyConfig.fromPreset(PresetPlan.trendConservative),
  );
}

class _PreviewDataSource implements MarketDataSource {
  @override
  Future<double?> fetchCurrentPrice(String code) async =>
      code == '600519' ? 1251.06 : 198.30;

  @override
  Future<String?> fetchName(String code) async =>
      code == '600519' ? '贵州茅台' : '宁德时代';

  @override
  Future<List<Kline>> fetchDailyKlines(String code, {int count = 30}) async =>
      List.generate(
        count,
        (i) => Kline(
          date: '2026-06-${(i + 1).toString().padLeft(2, '0')}',
          open: (1200 + i).toDouble(),
          high: (1210 + i).toDouble(),
          low: (1195 + i).toDouble(),
          close: (1205 + i).toDouble(),
        ),
      );

  @override
  Future<List<Kline>> fetchMonthlyKlines(String code,
      {int count = 12}) async =>
      List.generate(
        count,
        (i) => Kline(
          date: '2025-${(i + 1).toString().padLeft(2, '0')}',
          open: (1100 + i * 5).toDouble(),
          high: (1150 + i * 5).toDouble(),
          low: (1080 + i * 5).toDouble(),
          close: (1120 + i * 5).toDouble(),
        ),
      );

  @override
  Future<String?> fetchSector(String code) async =>
      code == '600519' ? '白酒' : '电池';

  @override
  Future<MarketOverview> fetchMarketOverview() async => const MarketOverview(
        indices: [
          IndexQuote(name: '上证指数', code: '000001', price: 3105.22, changePercent: -0.0045),
          IndexQuote(name: '深证成指', code: '399001', price: 9876.54, changePercent: 0.0012),
          IndexQuote(name: '创业板指', code: '399006', price: 1987.65, changePercent: 0.0089),
        ],
        topSectors: [
          SectorQuote(name: '白酒', changePercent: 0.021),
          SectorQuote(name: '新能源', changePercent: 0.018),
        ],
        bottomSectors: [
          SectorQuote(name: '房地产', changePercent: -0.015),
        ],
      );
}
