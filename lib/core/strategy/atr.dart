import '../models/kline.dart';

/// 技术指标计算。目前仅实现 ATR；其余指标（均线等）按需补充。
///
/// 详见产品设计文档第四章 ATR 相关说明。

/// Wilder 平滑法计算 ATR（平均真实波幅）。
///
/// 标准实现：TR = max(H-L, |H-前收|, |L-前收|)，首周期取 TR 简单平均，
/// 之后用 Wilder 平滑：ATR = (前ATR×(n-1) + TR) / n。
///
/// [klines] 应按时间升序排列，长度需 >= [period] + 1 才有意义。
/// 返回最近一根 K 线对应的 ATR；数据不足时返回 null。
double? calculateAtr(List<Kline> klines, {int period = 14}) {
  if (klines.length < 2 || period < 1) return null;

  final trs = <double>[];
  for (var i = 1; i < klines.length; i++) {
    final k = klines[i];
    final prevClose = klines[i - 1].close;
    final tr = [
      k.high - k.low,
      (k.high - prevClose).abs(),
      (k.low - prevClose).abs(),
    ].reduce((a, b) => a > b ? a : b);
    trs.add(tr);
  }

  if (trs.length < period) {
    // 数据不足一个完整周期，返回已有 TR 的简单平均作为近似。
    return trs.reduce((a, b) => a + b) / trs.length;
  }

  // 首个 ATR = 前 period 个 TR 的简单平均。
  double atr = 0;
  for (var i = 0; i < period; i++) {
    atr += trs[i];
  }
  atr /= period;

  // Wilder 平滑。
  for (var i = period; i < trs.length; i++) {
    atr = (atr * (period - 1) + trs[i]) / period;
  }
  return atr;
}
