import 'fill.dart';

/// 止损策略类型。详见产品设计文档第四章。
enum StopLossStrategy {
  /// 4.1 ATR 波动率止损（核心推荐）。
  atr,

  /// 4.2 钱德勒止损 / 吊灯止损（锚点为持仓期间最高价）。
  chandelier,

  /// 4.3 保本止损 / 盈亏比锁定止损（辅助层，浮盈达标后上移止损）。
  breakeven,

  /// 4.4 结构性止损 / 关键位止损。
  structural,

  /// 4.5 固定比例止损（兜底层）。
  fixedPercent,

  /// 4.6 时间止损（辅助提醒，不强制执行）。
  time,
}

/// 止盈策略类型。详见产品设计文档第五章。
enum TakeProfitStrategy {
  /// 5.1 分批止盈 + 移动止盈组合（核心推荐）。
  batchAndTrailing,

  /// 5.2 纯移动止盈 / 钱德勒止盈。
  trailingOnly,

  /// 5.3 均线止盈 / 右侧出局。
  movingAverage,

  /// 5.4 目标位止盈 / 左侧止盈。
  targetPrice,

  /// 5.5 波动率自适应止盈（进阶）。
  volatilityAdaptive,
}

/// 预设方案。详见产品设计文档 3.2 / 第六章组合推荐。
enum PresetPlan {
  /// 趋势-保守：钱德勒止损 + 纯移动止盈，ATR 倍数偏大。
  trendConservative,

  /// 趋势-激进：ATR 止损倍数偏小，让利润奔跑。
  trendAggressive,

  /// 波段-标准：分批止盈 + 移动止盈组合 + 固定比例兜底。
  swingStandard,
}

/// 保本止损 / 盈亏比锁定止损的分阶段配置。详见 4.3。
///
/// [riskMultiple] 为相对「风险额度」的倍数：1=保本，2=锁定一半利润，
/// 3=锁定 70% 利润。[lockRatio] 为该阶段锁定的利润比例（0~1）。
class BreakevenStage {
  const BreakevenStage({
    required this.riskMultiple,
    required this.lockRatio,
  });

  /// 文档默认三阶段：1 倍保本、2 倍锁半、3 倍锁 70%。
  static const List<BreakevenStage> defaultStages = [
    BreakevenStage(riskMultiple: 1, lockRatio: 0.0),
    BreakevenStage(riskMultiple: 2, lockRatio: 0.5),
    BreakevenStage(riskMultiple: 3, lockRatio: 0.7),
  ];

  final double riskMultiple;
  final double lockRatio;
}

/// 分批止盈的一档目标。详见 5.1。
class TakeProfitTarget {
  const TakeProfitTarget({
    required this.riskRewardRatio,
    required this.sellRatio,
  });

  /// 相对风险的盈亏比（如 2.0 表示盈亏比 2:1 的目标价）。
  final double riskRewardRatio;

  /// 到价后卖出的仓位比例（0~1，所有档位之和不超过 1）。
  final double sellRatio;
}

/// 一个持仓绑定的完整止盈止损规则。对应文档第六章三层组合 + 辅助层。
///
/// V1 仅实现固定比例止损 + ATR 止损 + 钱德勒移动止盈；其余策略字段已预留，
/// 评估逻辑见 core/strategy 下的占位与 TODO。
class StrategyConfig {
  const StrategyConfig({
    this.preset,
    required this.hardStopPercent,
    this.structuralLevel,
    required this.atrPeriod,
    required this.atrMultiple,
    required this.breakevenEnabled,
    this.breakevenStages = BreakevenStage.defaultStages,
    required this.takeProfitStrategy,
    this.takeProfitTargets = const [
      TakeProfitTarget(riskRewardRatio: 2.0, sellRatio: 0.4),
      TakeProfitTarget(riskRewardRatio: 4.0, sellRatio: 0.3),
    ],
    this.trailingMultiple = 3.0,
    this.maPeriod = 20,
    this.timeStopDays = 0,
    this.timeStopProfitThreshold = 0.0,
    this.atrAdaptive = true,
    this.stopConfirmMinutes = 5,
  });

  /// 由预设方案生成默认配置。详见 [PresetPlan]。
  factory StrategyConfig.fromPreset(PresetPlan preset) {
    switch (preset) {
      case PresetPlan.trendConservative:
        return const StrategyConfig(
          preset: PresetPlan.trendConservative,
          hardStopPercent: 0.12,
          atrPeriod: 22,
          atrMultiple: 3.0,
          breakevenEnabled: true,
          takeProfitStrategy: TakeProfitStrategy.trailingOnly,
          trailingMultiple: 3.0,
        );
      case PresetPlan.trendAggressive:
        return const StrategyConfig(
          preset: PresetPlan.trendAggressive,
          hardStopPercent: 0.10,
          atrPeriod: 14,
          atrMultiple: 2.0,
          breakevenEnabled: true,
          takeProfitStrategy: TakeProfitStrategy.trailingOnly,
          trailingMultiple: 2.5,
        );
      case PresetPlan.swingStandard:
        return const StrategyConfig(
          preset: PresetPlan.swingStandard,
          hardStopPercent: 0.10,
          atrPeriod: 14,
          atrMultiple: 2.5,
          breakevenEnabled: true,
          takeProfitStrategy: TakeProfitStrategy.batchAndTrailing,
          trailingMultiple: 3.0,
        );
    }
  }

  /// 快速模式的预设标签；自定义模式下为 null。
  final PresetPlan? preset;

  // ---- 第一层：硬止损（兜底层）----

  /// 固定比例硬止损（如 0.05 = 买入价下方 5%）。永远存在，不可关闭。
  final double hardStopPercent;

  /// 结构性止损关键位（可选）。设为「硬止损」时与固定比例取更紧者。详见 4.4。
  final double? structuralLevel;

  // ---- 第二层：动态止损（核心层）----

  /// ATR 计算周期（日）。文档推荐 14（钱德勒推荐 22）。
  final int atrPeriod;

  /// ATR 止损倍数。文档推荐 2~3。
  final double atrMultiple;

  /// 是否开启保本止损 / 盈亏比锁定。详见 4.3。
  final bool breakevenEnabled;
  final List<BreakevenStage> breakevenStages;

  // ---- 第三层：止盈（核心层）----

  final TakeProfitStrategy takeProfitStrategy;

  /// 分批止盈的目标档位。详见 [TakeProfitTarget]。
  final List<TakeProfitTarget> takeProfitTargets;

  /// 移动止盈 / 钱德勒止盈的 ATR 倍数。文档推荐 2.5~3。
  final double trailingMultiple;

  /// 均线止盈的均线周期。详见 5.3。
  final int maPeriod;

  // ---- 辅助层：时间止损提醒 ----

  /// 进场后多少天触发时间止损提醒；0 表示关闭。详见 4.6。
  final int timeStopDays;

  /// 时间止损的浮盈阈值（小数）。进场 N 天后浮盈低于该值则提醒。
  final double timeStopProfitThreshold;

  // ---- 自适应与确认开关 ----

  /// 是否开启 ATR 倍数自适应：按归一化波动率(ATR/成本)分档覆盖 [atrMultiple]。
  /// <2% 用 2.0、2-5% 用 2.5、>5% 用 3.5。关闭则用固定 [atrMultiple]。
  final bool atrAdaptive;

  /// 止损确认时长（分钟）：价格跌破止损线后需维持此时长才真触发告警，
  /// 过滤插针。0 表示关闭确认、立即触发。
  final int stopConfirmMinutes;

  /// 计算单笔风险额度（用于保本止损/盈亏比锁定）。
  /// 风险额度 = 成本价 - 止损价，再乘以数量。
  double riskAmount(List<Fill> fills, double stopPrice) {
    final cost = weightedCost(fills);
    final qty = fills.fold<int>(0, (s, f) => s + f.quantity);
    return (cost - stopPrice).clamp(0.0, double.infinity) * qty;
  }

  /// 加权成本价。详见 3.1 分批建仓。
  static double weightedCost(List<Fill> fills) {
    if (fills.isEmpty) return 0;
    double totalValue = 0;
    int totalQty = 0;
    for (final f in fills) {
      totalValue += f.price * f.quantity;
      totalQty += f.quantity;
    }
    return totalQty == 0 ? 0 : totalValue / totalQty;
  }
}
