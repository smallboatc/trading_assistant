import '../market/market_overview.dart';
import '../models/kline.dart';
import '../models/position.dart';
import '../../state/app_store.dart';

/// AI 上下文构建器：按入口注入不同的市场数据作为 system prompt。
///
/// 这是 AI 辅助决策的核心——确保 AI 能看到用户的真实持仓和市场环境，
/// 而不是空对空地聊天。详见产品设计文档 AI 辅助决策。
class ContextBuilder {
  ContextBuilder._();

  /// 构建持仓分析上下文。从持仓卡片"问AI"进入时使用。
  ///
  /// 注入：持仓详情（成本/现价/浮盈/止损止盈/最高价/天数）+
  /// 日K + 月K + 所属板块 + 大盘环境。
  static String buildPositionContext({
    required Position position,
    required List<Kline> dailyKlines,
    required List<Kline> monthlyKlines,
    required String? sector,
    required MarketOverview overview,
  }) {
    final pnl = position.floatingPnl;
    final pnlPct = position.floatingPnlPercent * 100;
    final stop = position.stopPrice;
    final tp = position.takeProfitPrice;
    final cur = position.currentPrice;

    final sb = StringBuffer();
    sb.writeln('你是一位专业的 A 股交易顾问。以下是用户当前持仓的实时数据，'
        '请基于这些数据给出分析建议。');
    sb.writeln();

    // ---- 持仓详情 ----
    sb.writeln('## 当前持仓');
    sb.writeln('- 股票：${position.name}（${position.code}）');
    sb.writeln('- 成本价：${_fmt(position.costPrice)} 元');
    sb.writeln('- 当前价：${cur == null ? "未知" : "${_fmt(cur)} 元"}');
    sb.writeln('- 持仓数量：${position.remainingQuantity} 股');
    sb.writeln('- 浮动盈亏：${pnl >= 0 ? "+" : ""}${pnl.toStringAsFixed(0)} 元'
        '（${pnlPct >= 0 ? "+" : ""}${pnlPct.toStringAsFixed(2)}%）');
    if (stop != null && cur != null && cur != 0) {
      final dist = (cur - stop) / cur * 100;
      sb.writeln('- 止损线：${_fmt(stop)} 元（距当前价 ${dist.toStringAsFixed(1)}%）');
    } else if (stop != null) {
      sb.writeln('- 止损线：${_fmt(stop)} 元');
    }
    if (tp != null) {
      sb.writeln('- 止盈线：${_fmt(tp)} 元');
    }
    sb.writeln('- 持仓期间最高价：${_fmt(position.highestPrice)} 元');
    sb.writeln('- 持仓天数：${position.holdingDays} 天');
    sb.writeln();

    // ---- 近期走势 ----
    sb.writeln('## 近期走势');
    sb.writeln(_klineSummary('日K线（最近${dailyKlines.length}日）', dailyKlines));
    sb.writeln(_klineSummary('月K线（最近${monthlyKlines.length}月）', monthlyKlines));
    sb.writeln();

    // ---- 所属板块 ----
    sb.writeln('## 所属板块');
    if (sector != null && sector.isNotEmpty) {
      sb.writeln('- 板块：$sector');
    } else {
      sb.writeln('- 板块：数据获取失败');
    }
    sb.writeln();

    // ---- 大盘环境 ----
    sb.writeln(_overviewSection(overview));

    sb.writeln('请结合以上数据，分析该持仓的风险与机会，给出操作建议。'
        '用 Markdown 格式回复，简洁有力。');
    return sb.toString();
  }

  /// 构建通用聊天上下文。从底部导航直接进入时使用。
  ///
  /// 注入：大盘指数 + 板块涨跌 + 用户持仓概况。
  static String buildGeneralContext({
    required MarketOverview overview,
    required AppStore store,
  }) {
    final sb = StringBuffer();
    sb.writeln('你是一位专业的 A 股交易顾问。以下是当前市场概况，'
        '请基于这些数据与用户对话。');
    sb.writeln('注意：行情数据来自非官方接口，可能因限流暂时缺失。'
        '若某项数据标注「数据获取失败」，请说明该部分暂未取到，'
        '并基于已有数据尽量分析，不要笼统说「无法获取实时数据」而拒绝回答。');
    sb.writeln();

    sb.writeln(_overviewSection(overview));

    // ---- 用户持仓概况 ----
    sb.writeln('## 用户持仓概况');
    sb.writeln('- 在管持仓：${store.positions.length} 只');
    sb.writeln('- 整体浮动盈亏：${store.totalFloatingPnl >= 0 ? "+" : ""}'
        '${store.totalFloatingPnl.toStringAsFixed(0)} 元');
    if (store.positions.isNotEmpty) {
      sb.writeln('- 持仓列表：');
      for (final p in store.positions) {
        sb.writeln('  - ${p.name}（${p.code}）浮盈 '
            '${p.floatingPnl >= 0 ? "+" : ""}${p.floatingPnl.toStringAsFixed(0)} 元');
      }
    }
    sb.writeln();

    sb.writeln('请帮助用户分析市场趋势、板块轮动，或回答用户的交易问题。'
        '用 Markdown 格式回复，简洁有力。');
    return sb.toString();
  }

  // ---- 辅助格式化 ----

  static String _fmt(double v) => v.toStringAsFixed(2);

  static String _klineSummary(String label, List<Kline> klines) {
    if (klines.isEmpty) return '- $label：数据获取失败';
    final sb = StringBuffer('- $label：');
    // 取最近 5 根，输出 "日期:收" 摘要。
    final recent = klines.length > 5
        ? klines.sublist(klines.length - 5)
        : klines;
    sb.write(recent.map((k) => '${k.date}:${_fmt(k.close)}').join(' → '));
    if (klines.isNotEmpty) {
      final high = klines.map((k) => k.high).reduce((a, b) => a > b ? a : b);
      final low = klines.map((k) => k.low).reduce((a, b) => a < b ? a : b);
      sb.write('（区间高 ${_fmt(high)} / 低 ${_fmt(low)}）');
    }
    return sb.toString();
  }

  static String _overviewSection(MarketOverview overview) {
    if (overview.isEmpty) return '## 大盘环境\n- 数据获取失败\n';
    final sb = StringBuffer('## 大盘环境\n');
    for (final idx in overview.indices) {
      sb.writeln('- ${idx.name}：${_fmt(idx.price)}'
          '（${idx.changePercent >= 0 ? "+" : ""}'
          '${(idx.changePercent * 100).toStringAsFixed(2)}%）');
    }
    if (overview.topSectors.isNotEmpty) {
      sb.writeln();
      sb.writeln('## 板块涨跌（今日）');
      sb.write('- 涨幅前${overview.topSectors.length}：');
      sb.write(overview.topSectors
          .map((s) => '${s.name}(${_pct(s.changePercent)})')
          .join('、'));
      sb.writeln();
      if (overview.bottomSectors.isNotEmpty) {
        sb.write('- 跌幅前${overview.bottomSectors.length}：');
        sb.write(overview.bottomSectors
            .map((s) => '${s.name}(${_pct(s.changePercent)})')
            .join('、'));
        sb.writeln();
      }
    }
    return sb.toString();
  }

  static String _pct(double v) =>
      '${v >= 0 ? "+" : ""}${(v * 100).toStringAsFixed(2)}%';
}
