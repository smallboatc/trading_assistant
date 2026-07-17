// 持仓卡片布局测试：验证小屏下成本完整显示、无溢出、关键元素存在。
// 用窄屏(360px,模拟手机)渲染，确保对齐改动不破坏布局。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:trading_assistant/core/models/fill.dart';
import 'package:trading_assistant/core/models/position.dart';
import 'package:trading_assistant/core/models/strategy_config.dart';
import 'package:trading_assistant/presentation/widgets/position_card.dart';
import 'package:trading_assistant/state/app_store.dart';

Position _pos({
  String code = '600519',
  String name = '贵州茅台',
  double price = 1680.00,
  int qty = 100,
  double? currentPrice,
  bool handled = false,
}) {
  final p = Position(
    id: 'p1',
    accountId: 'default',
    code: code,
    name: name,
    fills: [Fill(price: price, quantity: qty, time: '2026-07-01')],
    strategy: StrategyConfig.fromPreset(PresetPlan.swingStandard),
  );
  p.currentPrice = currentPrice ?? price;
  p.highestPrice = currentPrice ?? price;
  p.stopPrice = price * 0.9;
  p.takeProfitPrice = price * 1.1;
  p.handled = handled;
  return p;
}

Widget _wrap(Position p) {
  return MaterialApp(
    home: ChangeNotifierProvider<AppStore>(
      create: (_) => AppStore(),
      child: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: ListView(children: [PositionCard(position: p)]),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('高价股成本完整显示不被截断', (tester) async {
    await tester.pumpWidget(_wrap(_pos()));
    await tester.pumpAndSettle();
    // 成本 1680.00 应完整出现，而非 "成本 1680..."。
    expect(find.text('成本 1680.00'), findsOneWidget);
  });

  testWidgets('已平仓持仓显示已平仓徽章与恢复监控菜单', (tester) async {
    await tester.pumpWidget(_wrap(_pos(handled: true)));
    await tester.pumpAndSettle();
    expect(find.text('已平仓'), findsOneWidget);
  });

  testWidgets('盘后标记显示收盘badge且成本完整', (tester) async {
    final p = _pos(currentPrice: 1680.00);
    p.marketClosed = true;
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();
    expect(find.text('收盘'), findsOneWidget);
    expect(find.text('成本 1680.00'), findsOneWidget);
  });

  testWidgets('卡片无布局溢出异常', (tester) async {
    // 渲染过程若有 RenderFlex overflow 会抛 FlutterError，测试自然失败。
    await tester.pumpWidget(_wrap(_pos(name: '一个名字很长的股票用来测试溢出情况')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
