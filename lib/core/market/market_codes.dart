/// A 股代码与市场前缀工具，用于拼接各数据源的行情请求。
///
/// V1 聚焦沪深主板与创业板：6 开头（含科创板 688）为沪市，0/3 开头（含
/// 创业板 300）为深市。北交所（8/4 开头）暂未处理，见 TODO。
class MarketCodes {
  MarketCodes._();

  /// 是否为沪市股票。
  static bool isShanghai(String code) => code.startsWith('6');

  // TODO(V3): 北交所 8/4 开头代码的前缀处理。

  /// 东方财富 secid：沪市 `1.`，深市 `0.`。
  static String eastmoneySecid(String code) =>
      isShanghai(code) ? '1.$code' : '0.$code';

  /// 腾讯行情代码：沪市 `sh`，深市 `sz`。
  static String tencentCode(String code) =>
      isShanghai(code) ? 'sh$code' : 'sz$code';
}
