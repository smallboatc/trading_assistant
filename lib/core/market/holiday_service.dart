import 'dart:convert';

import 'package:http/http.dart' as http;

/// 中国节假日数据服务。
///
/// 数据源 NateScarlet/holiday-cn（GitHub 开源，GitHub Actions 每日自动抓取国务院公告，
/// 数据变化时自动发布）。免费、免 API key、免每年手动维护。
/// 通过 jsDelivr CDN 拉取当年 JSON：https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/{year}.json
///
/// 节假日判断：A股周末不交易（含调休补班的周末也不交易），故交易日 = 周一到周五 且 不是节假日。
class HolidayService {
  HolidayService._();

  /// 缓存：年份 -> 该年节假日日期集合（isOffDay=true 的 date）。
  static final Map<int, Set<String>> _holidays = {};

  /// 已加载的年份（避免重复拉取）。
  static final Set<int> _loadedYears = {};

  static const _cdnBase = 'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master';

  /// 加载指定年份的节假日。成功返回 true。
  static Future<bool> loadYear(int year) async {
    if (_loadedYears.contains(year)) return _holidays[year] != null;
    final url = Uri.parse('$_cdnBase/$year.json');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        _loadedYears.add(year);
        return false;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final days = json['days'] as List<dynamic>? ?? [];
      _holidays[year] = days
          .where((d) => (d as Map<String, dynamic>)['isOffDay'] == true)
          .map((d) => d['date'] as String)
          .toSet();
      _loadedYears.add(year);
      return true;
    } catch (_) {
      _loadedYears.add(year);
      return false;
    }
  }

  /// 加载当年（用于 App 启动）。
  static Future<bool> loadCurrentYear() {
    return loadYear(DateTime.now().year);
  }

  /// 指定日期是否为节假日（放假）。调休补班（isOffDay=false）不算节假日
  /// （但调休补班多为周末，周末本就休市，无需特殊处理）。
  /// 数据未加载时返回 false（降级为固定规则）。
  static bool isHoliday(DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _holidays[date.year]?.contains(dateStr) ?? false;
  }

  /// 是否已加载某年数据。
  static bool isLoaded(int year) => _holidays.containsKey(year);
}
