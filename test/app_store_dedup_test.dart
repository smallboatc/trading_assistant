// 锁定 BUG 修复：
// 1. 止损触发后每轮重复告警刷屏 → 现按 pending alert 去重。
// 2. 「待确认」状态在确认/忽略后卡死 → 现清空 lastAlertId 回归正常。
//
// 用 evaluateWith（人工输入价）走评估路径，避免依赖交易时段与真实网络。

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_assistant/core/market/mock_market_data_source.dart';
import 'package:trading_assistant/core/models/alert.dart';
import 'package:trading_assistant/core/models/position.dart';
import 'package:trading_assistant/core/models/strategy_config.dart';
import 'package:trading_assistant/state/app_store.dart';

void main() {
  // SharedPreferences 需要 Flutter binding 初始化。
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStore store;

  setUp(() {
    store = AppStore(dataSource: MockMarketDataSource());
  });

  Position addPosition() {
    return store.addPosition(
      code: '600519',
      name: '测试',
      price: 100,
      quantity: 100,
      strategy: StrategyConfig.fromPreset(PresetPlan.swingStandard),
    );
  }

  test('持续触发止损不应重复产生 pending 告警', () async {
    final pos = addPosition();
    // 100 元成本，swingStandard 硬止损 5% = 95。8 元远低于止损线。
    await store.setManualPrice(pos.id, 8);
    expect(store.alerts.length, 1);
    expect(store.alerts.first.action, AlertAction.pending);
    expect(pos.lastAlertId, isNotNull);

    // 再次输入同低价：已有 pending 告警，应去重。
    await store.setManualPrice(pos.id, 8);
    expect(store.alerts.length, 1);
  });

  test('确认止损告警后了结仓位，不再重复告警；撤销确认后恢复监控', () async {
    final pos = addPosition();
    await store.setManualPrice(pos.id, 8);
    final alertId = store.alerts.first.id;
    expect(pos.lastAlertId, isNotNull);

    store.confirmAlert(alertId);
    expect(pos.lastAlertId, isNull);
    expect(pos.handled, isTrue);
    expect(pos.isClosed, isTrue);

    // 已了结仓位再次评估：不应产生新告警。
    await store.setManualPrice(pos.id, 8);
    expect(store.alerts.length, 1);

    // 撤销确认恢复监控后，应能再次触发。
    store.reopenPosition(pos.id);
    expect(pos.handled, isFalse);
    await store.setManualPrice(pos.id, 8);
    expect(store.alerts.length, 2);
    expect(store.alerts.first.action, AlertAction.pending);
  });

  test('忽略告警后清空 lastAlertId', () async {
    final pos = addPosition();
    await store.setManualPrice(pos.id, 8);
    final alertId = store.alerts.first.id;

    store.ignoreAlert(alertId);
    expect(pos.lastAlertId, isNull);
    expect(store.alerts.first.action, AlertAction.ignored);
  });

  test('价格回升但仍有未处理告警时，不应清空 lastAlertId（提醒须保留可见）', () async {
    final pos = addPosition();
    await store.setManualPrice(pos.id, 8);
    expect(pos.lastAlertId, isNotNull);
    expect(store.attentionCount, 1);

    // 价格回升到成本上方（101，未达保本/止盈阈值，避免干扰）：用户尚未处理
    // 那条止损提醒，标记应保留，卡片继续显示「待确认」直至用户确认/忽略。
    await store.setManualPrice(pos.id, 101);
    expect(pos.lastAlertId, isNotNull);
    expect(store.attentionCount, 1);
  });

  test('确认不存在的告警 id 不抛异常', () {
    store.addPosition(
      code: '600519',
      name: '测试',
      price: 100,
      quantity: 100,
      strategy: StrategyConfig.fromPreset(PresetPlan.swingStandard),
    );
    // 不应抛 StateError。
    store.confirmAlert('nonexistent');
    store.ignoreAlert('nonexistent');
    expect(store.alerts.length, 0);
  });

  test('加仓后成本价按加权重算', () {
    final pos = addPosition(); // 100 股 @ 100 元
    expect(pos.costPrice, 100);

    store.addFill(pos.id, price: 120, quantity: 100);
    // (100*100 + 120*100) / 200 = 110
    expect(pos.totalQuantity, 200);
    expect(pos.costPrice, 110);
  });

  test('编辑持仓覆盖成本/数量/策略', () {
    final pos = addPosition(); // 100 股 @ 100 元，swingStandard
    store.updatePosition(pos.id,
        price: 88, quantity: 200, strategy: StrategyConfig.fromPreset(PresetPlan.trendAggressive));
    expect(pos.totalQuantity, 200);
    expect(pos.costPrice, 88);
    expect(pos.strategy.preset, PresetPlan.trendAggressive);
  });

  test('清除已处理提醒仅移除非 pending 项', () async {
    final pos = addPosition();
    await store.setManualPrice(pos.id, 8);
    // 再加一只触发第二条。
    final pos2 = store.addPosition(
      code: '000001',
      name: '测试2',
      price: 100,
      quantity: 100,
      strategy: StrategyConfig.fromPreset(PresetPlan.swingStandard),
    );
    await store.setManualPrice(pos2.id, 8);
    expect(store.alerts.length, 2);

    // 确认第一条，保留第二条 pending。
    store.confirmAlert(store.alerts.last.id);
    expect(store.alerts.where((a) => a.action == AlertAction.pending).length, 1);

    store.clearHandledAlerts();
    expect(store.alerts.length, 1);
    expect(store.alerts.first.action, AlertAction.pending);
  });

  test('已了结仓位的浮动盈亏应为 0', () async {
    final pos = addPosition();
    await store.setManualPrice(pos.id, 8);
    store.confirmAlert(store.alerts.first.id);
    expect(pos.handled, isTrue);
    expect(pos.floatingPnl, 0);
  });

  // ---- confirmAlert 差异化：分批止盈确认累加 closedQuantity，不平仓 ----
  test('确认分批止盈提醒：按档比例累加已平仓数量，持仓不平仓', () async {
    final pos = addPosition();
    // 换成「关闭保本」的分批止盈策略，避免保本告知抢在分批止盈之前。
    store.updatePosition(
      pos.id,
      price: 100,
      quantity: 500,
      strategy: const StrategyConfig(
        hardStopPercent: 0.10,
        atrPeriod: 14,
        atrMultiple: 2.5,
        breakevenEnabled: false,
        takeProfitStrategy: TakeProfitStrategy.batchAndTrailing,
        atrAdaptive: false,
        stopConfirmMinutes: 0,
      ),
    );
    // 先拉一次记录 initialStop（baseStop=90），riskPerShare=10，第1档目标=120。
    await store.setManualPrice(pos.id, 100);
    // 到第1档目标价 → 分批止盈提醒（500股>300，走分批）。
    await store.setManualPrice(pos.id, 120);
    final tpAlert = store.alerts.firstWhere(
        (a) => a.type == AlertType.takeProfitTarget);
    expect(pos.closedQuantity, 0);
    expect(pos.handled, isFalse);

    // 确认分批止盈：按第1档 sellRatio(0.4) 累加 closedQuantity=200，不平仓。
    store.confirmAlert(tpAlert.id);
    expect(pos.closedQuantity, 200);
    expect(pos.handled, isFalse); // 仍有剩余仓位
    expect(pos.remainingQuantity, 300);
  });

  // ---- confirmAlert 差异化：保本告知确认不平仓 ----
  test('确认保本告知提醒：不改变仓位与 handled', () async {
    final pos = addPosition();
    // swingStandard 默认 breakevenEnabled，价格涨到保本阈值触发告知。
    await store.setManualPrice(pos.id, 100); // 记录 initialStop
    await store.setManualPrice(pos.id, 120); // 浮盈20→保本阶段提升→告知
    final beAlert = store.alerts
        .firstWhere((a) => a.type == AlertType.breakevenStop);
    expect(pos.handled, isFalse);
    store.confirmAlert(beAlert.id);
    expect(pos.handled, isFalse); // 保本不平仓
    expect(pos.closedQuantity, 0);
  });
}
