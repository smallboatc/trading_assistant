/// 单根 K 线数据（用于 ATR 等技术指标计算）。
///
/// 日期 [date] 用 ISO 字符串保存（YYYY-MM-DD），避免引入平台时区问题。
/// 详见产品设计文档第三章 3.3 数据采集 / 第四章 ATR 计算说明。
class Kline {
  const Kline({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  @override
  String toString() =>
      'Kline($date O=$open H=$high L=$low C=$close V=$volume)';
}
