// 止损线应取硬止损与 ATR 止损中更紧者（更高的止损价）。
// 锁定 BUG 修复：此前误取 MIN（更松），忽略硬止损兜底层导致亏损放大。

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_assistant/core/models/alert.dart';
import 'package:trading_assistant/core/models/fill.dart';
import 'package:trading_assistant/core/models/kline.dart';
import 'package:trading_assistant/core/models/position.dart';
import 'package:trading_assistant/core/models/strategy_config.dart';
import 'package:trading_assistant/core/strategy/strategy_evaluator.dart';

/// 生成 N 根 TR 恒为 [tr] 的日 K（无缺口，使 ATR 收敛到 [tr]）。
List<Kline> _flatKlines(int n, double tr) {
  return List.generate(n, (i) {
    return Kline(
      date: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
      open: 10,
      close: 10,
      high: 10 + tr / 2,
      low: 10 - tr / 2,
    );
  });
}

Position _pos(double hardStopPercent) =>
    _posWith(hardStopPercent, TakeProfitStrategy.trailingOnly);

/// 可指定止盈策略的持仓工厂。
/// 关闭 ATR 自适应与止损确认，聚焦「取更紧者 / 类型判定」基础逻辑；
/// 新特性（自适应/保本/分批/确认）由独立测试覆盖。
Position _posWith(double hardStopPercent, TakeProfitStrategy tp) {
  final p = Position(
    id: 'p',
    accountId: 'default',
    code: '600519',
    name: '测试',
    fills: [Fill(price: 10, quantity: 100, time: '2026-07-15')],
    strategy: StrategyConfig(
      hardStopPercent: hardStopPercent,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: false,
      takeProfitStrategy: tp,
      atrAdaptive: false,
      stopConfirmMinutes: 0,
    ),
  );
  p.highestPrice = 10;
  return p;
}

void main() {
  test('ATR 止损更松时，止损线应取硬止损（更紧/更高）', () {
    // 成本 10，硬止损 5% = 9.5；ATR=0.5 → atrStop = 10-0.5*2.5 = 8.75（更松）。
    final pos = _pos(0.05);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.stopPrice, 9.5);
  });

  test('ATR 止损更紧时，止损线应取 ATR 止损（更高）', () {
    // 成本 10，硬止损 5% = 9.5；ATR=0.1 → atrStop = 10-0.1*2.5 = 9.75（更紧）。
    final pos = _pos(0.05);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.1),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.stopPrice, closeTo(9.75, 1e-9));
  });

  // 锁定 BUG 修复：batchAndTrailing（默认预设 swingStandard）此前无止盈线，
  // batchAndTrailing 现实现真分批止盈：第1档目标价 = cost + riskRewardRatio × 风险额度。
  test('batchAndTrailing 第1档止盈线应为盈亏比目标价', () {
    // 成本 10，硬止损 5% → 9.5；ATR=0.5，关自适应倍数 2.5 → atrStop=8.75；baseStop=9.5。
    // initialStop 首次记录=9.5，riskPerShare=0.5；第1档盈亏比 2.0 → 目标=10+2.0*0.5=11.0。
    final pos = _posWith(0.05, TakeProfitStrategy.batchAndTrailing);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.takeProfitPrice, closeTo(11.0, 1e-9));
    // currentPrice=10 未到 11.0，不触发止盈 alert。
    expect(result.alert, isNull);
  });

  // 锁定 BUG 修复：止损触发类型此前固定 atrStop，应按起作用的止损线判定。
  test('硬止损更紧触发时，告警类型应为 hardStop', () {
    // 成本 10，硬止损 5% = 9.5；ATR=0.5 → atrStop = 8.75（更松），取硬止损 9.5。
    // 当前价 9.4 <= 9.5 触发，起作用的是硬止损。
    final pos = _pos(0.05);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 9.4,
      alertId: 'a',
    );
    expect(result.alert, isNotNull);
    expect(result.alert!.type, AlertType.hardStop);
  });

  test('ATR 止损更紧触发时，告警类型应为 atrStop', () {
    // 成本 10，硬止损 5% = 9.5；ATR=0.1 → atrStop = 9.75（更紧），取 9.75。
    // 当前价 9.7 <= 9.75 触发，起作用的是 ATR 止损。
    final pos = _pos(0.05);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.1),
      currentPrice: 9.7,
      alertId: 'a',
    );
    expect(result.alert, isNotNull);
    expect(result.alert!.type, AlertType.atrStop);
  });

  // ---- ATR 自适应：按波动率分档覆盖倍数 ----
  // hardStop 0.99（≈0.1）让 ATR 止损始终更紧，以便观察自适应倍数。
  Position adaptivePos(double tr) {
    final p = Position(
      id: 'p',
      accountId: 'default',
      code: '600519',
      name: '测试',
      fills: [Fill(price: 10, quantity: 100, time: '2026-07-15')],
      strategy: StrategyConfig(
        hardStopPercent: 0.99,
        atrPeriod: 14,
        atrMultiple: 2.5,
        breakevenEnabled: false,
        takeProfitStrategy: TakeProfitStrategy.trailingOnly,
        atrAdaptive: true,
        stopConfirmMinutes: 0,
      ),
    );
    p.highestPrice = 10;
    return p;
  }

  test('ATR 自适应：低波动(<2%)用 2.0 倍', () {
    // cost=10, atr=0.1, vol=1% → 2.0 倍 → atrStop=10-0.2=9.8。
    final pos = adaptivePos(0.1);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.1),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.stopPrice, closeTo(9.8, 1e-9));
  });

  test('ATR 自适应：中波动(2-5%)用 2.5 倍', () {
    // cost=10, atr=0.3, vol=3% → 2.5 倍 → atrStop=10-0.75=9.25。
    final pos = adaptivePos(0.3);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.3),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.stopPrice, closeTo(9.25, 1e-9));
  });

  test('ATR 自适应：高波动(>5%)用 3.5 倍', () {
    // cost=10, atr=0.6, vol=6% → 3.5 倍 → atrStop=10-2.1=7.9。
    final pos = adaptivePos(0.6);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.6),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.stopPrice, closeTo(7.9, 1e-9));
  });

  // ---- 保本止损：浮盈达标后止损线上移 ----
  test('保本止损：浮盈达1倍风险额度，止损线上移到成本价', () {
    // cost=10, hardStop 5%→9.5, 关自适应 atr 2.5倍 atrStop=8.75, baseStop=9.5。
    // 第一次 evaluate(currentPrice=10) 记录 initialStop=9.5, riskPerShare=0.5。
    // 第二次 evaluate(currentPrice=10.5) 浮盈0.5=1倍风险 → 保本, 止损线=max(9.5,10)=10。
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    pos.strategy = StrategyConfig(
      hardStopPercent: 0.05,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: true,
      takeProfitStrategy: TakeProfitStrategy.trailingOnly,
      atrAdaptive: false,
      stopConfirmMinutes: 0,
    );
    StrategyEvaluator(pos).evaluate(
        klines: _flatKlines(30, 0.5), currentPrice: 10, alertId: 'a');
    expect(pos.initialStopPrice, 9.5);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 10.5,
      alertId: 'b',
    );
    expect(pos.breakevenStageReached, 1);
    expect(result.stopPrice, closeTo(10.0, 1e-9)); // 保本线=cost=10 > baseStop=9.5
    // 保本阶段提升应产生告知提醒。
    expect(result.alert, isNotNull);
    expect(result.alert!.type, AlertType.breakevenStop);
  });

  test('保本止损：阶段只升不降，浮盈回落后保本线不下移', () {
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    pos.strategy = StrategyConfig(
      hardStopPercent: 0.05,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: true,
      takeProfitStrategy: TakeProfitStrategy.trailingOnly,
      atrAdaptive: false,
      stopConfirmMinutes: 0,
    );
    // 涨到 11.0（浮盈1.0=2倍风险→锁半阶段2），再回落到 10.3（浮盈0.3<1倍）。
    StrategyEvaluator(pos).evaluate(
        klines: _flatKlines(30, 0.5), currentPrice: 10, alertId: 'a');
    StrategyEvaluator(pos).evaluate(
        klines: _flatKlines(30, 0.5), currentPrice: 11.0, alertId: 'b');
    expect(pos.breakevenStageReached, 2);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 10.3,
      alertId: 'c',
    );
    // 阶段仍为2，保本线=cost+0.5*0.5=10.25，不下移。
    expect(pos.breakevenStageReached, 2);
    expect(result.stopPrice, closeTo(10.25, 1e-9));
  });

  // ---- 分批止盈：到档提醒 + triggeredTpCount 递增 ----
  test('分批止盈：第1档到价触发提醒并递增档数', () {
    // cost=10, hardStop 5%→9.5, 关自适应 atrStop=8.75, baseStop=9.5, initialStop=9.5。
    // riskPerShare=0.5；第1档盈亏比2.0 → 目标价=10+2*0.5=11.0。
    final pos = _posWith(0.05, TakeProfitStrategy.batchAndTrailing);
    pos.strategy = StrategyConfig(
      hardStopPercent: 0.05,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: false,
      takeProfitStrategy: TakeProfitStrategy.batchAndTrailing,
      atrAdaptive: false,
      stopConfirmMinutes: 0,
    );
    StrategyEvaluator(pos).evaluate(
        klines: _flatKlines(30, 0.5), currentPrice: 10, alertId: 'a');
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 11.0,
      alertId: 'b',
    );
    expect(result.alert, isNotNull);
    expect(result.alert!.type, AlertType.takeProfitTarget);
    expect(pos.triggeredTpCount, 1);
  });

  // ---- 止损确认：维持N分钟才触发 ----
  test('止损确认：首次破位不触发，达确认时长才触发', () {
    // stopConfirmMinutes=1。currentPrice=9.4 跌破止损9.5。
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    pos.strategy = StrategyConfig(
      hardStopPercent: 0.05,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: false,
      takeProfitStrategy: TakeProfitStrategy.trailingOnly,
      atrAdaptive: false,
      stopConfirmMinutes: 1,
    );
    // 首次破位：stopBreachSince 设为当前，未达1分钟，不触发。
    var result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 9.4,
      alertId: 'a',
    );
    expect(result.alert, isNull);
    expect(pos.stopBreachSince, isNotNull);
    // 模拟确认时长已过：手动把 stopBreachSince 往前拨2分钟。
    pos.stopBreachSince = DateTime.now().subtract(const Duration(minutes: 2));
    result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 9.4,
      alertId: 'b',
    );
    expect(result.alert, isNotNull);
    expect(result.alert!.type, AlertType.hardStop);
  });

  test('止损确认：immediate=true 绕过确认立即触发', () {
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    pos.strategy = StrategyConfig(
      hardStopPercent: 0.05,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: false,
      takeProfitStrategy: TakeProfitStrategy.trailingOnly,
      atrAdaptive: false,
      stopConfirmMinutes: 10, // 即使设很长
    );
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 9.4,
      alertId: 'a',
      immediate: true,
    );
    expect(result.alert, isNotNull);
  });

  test('止损确认：价格回升清空破位计时', () {
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    pos.strategy = StrategyConfig(
      hardStopPercent: 0.05,
      atrPeriod: 14,
      atrMultiple: 2.5,
      breakevenEnabled: false,
      takeProfitStrategy: TakeProfitStrategy.trailingOnly,
      atrAdaptive: false,
      stopConfirmMinutes: 1,
    );
    // 破位
    StrategyEvaluator(pos).evaluate(
        klines: _flatKlines(30, 0.5), currentPrice: 9.4, alertId: 'a');
    expect(pos.stopBreachSince, isNotNull);
    // 回升
    StrategyEvaluator(pos).evaluate(
        klines: _flatKlines(30, 0.5), currentPrice: 10, alertId: 'b');
    expect(pos.stopBreachSince, isNull);
  });

  // ---- 移动止盈：未盈利不设止盈；已盈利锁定利润、永远高于止损 ----
  test('移动止盈：未盈利时不设止盈线（避免建仓即误触发）', () {
    // cost=10, highestPrice=cost=10（未盈利）→ 移动止盈返回 null。
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 10,
      alertId: 'a',
    );
    expect(result.takeProfitPrice, isNull);
  });

  test('移动止盈：已盈利时锁定利润，止盈高于止损且不低于成本', () {
    // cost=10, hardStop 5%→9.5, 关自适应 atr=0.5 倍数2.5 → atrStop=8.75, baseStop=9.5。
    // 涨到 highestPrice=13（已实现浮盈3），裸移动止盈=13-0.5*3=11.5；
    // 锁定利润=max(3*0.6, 10*0.08)=max(1.8,0.8)=1.8；下限=max(9.5+0.25, 10+1.8)=max(9.75,11.8)=11.8；
    // 11.5 < 11.8 → 取 11.8（锁定1.8利润，高于止损9.5、高于成本10）。
    final pos = _posWith(0.05, TakeProfitStrategy.trailingOnly);
    pos.highestPrice = 13; // 模拟持仓期间涨到13
    final result = StrategyEvaluator(pos).evaluate(
      klines: _flatKlines(30, 0.5),
      currentPrice: 12,
      alertId: 'a',
    );
    expect(result.stopPrice, 9.5);
    expect(result.takeProfitPrice, closeTo(11.8, 1e-9));
    expect(result.takeProfitPrice! > result.stopPrice!, isTrue); // 高于止损
    expect(result.takeProfitPrice! > 10, isTrue); // 高于成本（锁定利润）
  });
}
