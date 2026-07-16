// 交易时段判断应以北京时间为准，不受传入时区影响。
// 锁定 BUG 修复：此前直接用本地时间，设备在非东八区会误判。

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_assistant/core/market/trading_sessions.dart';

void main() {
  // 2026-07-15 是周三。北京时间 10:00 = UTC 02:00，属早盘（9:30-11:30）。
  test('UTC 时间能正确折算为北京时间早盘', () {
    final utc = DateTime.utc(2026, 7, 15, 2, 0);
    expect(TradingSessions.isTradingTime(utc), true);
  });

  test('北京时间 14:00（午盘）按 UTC 传入应判为交易时段', () {
    final utc = DateTime.utc(2026, 7, 15, 6, 0); // 北京 14:00
    expect(TradingSessions.isTradingTime(utc), true);
  });

  test('北京时间周末应休市（按 UTC 传入）', () {
    final utc = DateTime.utc(2026, 7, 18, 2, 0); // 北京 周六 10:00
    expect(TradingSessions.isTradingTime(utc), false);
  });

  test('北京时间盘前（8:00）应非交易时段', () {
    final utc = DateTime.utc(2026, 7, 15, 0, 0); // 北京 8:00
    expect(TradingSessions.isTradingTime(utc), false);
  });
}
