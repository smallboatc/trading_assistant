import 'dart:math';

import '../models/alert.dart';
import '../models/kline.dart';
import '../models/position.dart';
import '../models/strategy_config.dart';
import 'atr.dart';

/// 策略评估结果：本次监控周期算出的止盈止损线与（可能的）触发提醒。
class StrategyEvaluation {
  const StrategyEvaluation({
    this.stopPrice,
    this.takeProfitPrice,
    this.alert,
  });

  final double? stopPrice;
  final double? takeProfitPrice;
  final Alert? alert;
}

/// 策略评估器：根据持仓状态与行情，计算当前止盈止损线并检测触发。
///
/// 实现范围：固定比例硬止损 + ATR 止损（含波动率自适应倍数）+ 保本止损
/// （浮盈达标上移）+ 钱德勒移动止盈 / 分批止盈 + 止损维持N分钟确认。
/// 跨 tick 状态（初始止损、保本阶段、破位计时、分批档数）存于 [Position]。
/// 均线止盈、目标位止盈、时间止损、结构性止损见 TODO，留待后续。
class StrategyEvaluator {
  StrategyEvaluator(this.position);

  final Position position;

  /// 评估当前周期。
  ///
  /// [klines] 为该股票最近若干日 K 线（用于 ATR），[currentPrice] 为最新价。
  /// [immediate] 为 true 时绕过止损「维持N分钟确认」立即触发（人工输价场景）；
  /// 默认 false（自动 tick 走确认）。
  StrategyEvaluation evaluate({
    required List<Kline> klines,
    required double currentPrice,
    required String alertId,
    bool immediate = false,
    bool detect = true,
  }) {
    final cfg = position.strategy;
    final cost = position.costPrice;

    // 更新持仓期间最高价（用于钱德勒止损 / 移动止盈）。
    // 用「建仓日及之后」的日K最高价回填，避免 App 未运行时漏掉中间最高价
    // （tick 实时爬会丢失 App 关闭期间的日内最高）。日K high 是交易所真实数据。
    // 只取建仓日之后的K线，避免把建仓前的历史高点算进持仓期间最高价。
    if (position.highestPrice == 0) {
      position.highestPrice = cost;
    }
    // 建仓日按北京时间折算（与交易时段判断一致），避免时区漂移取错K线。
    final bj = position.createdAt.toUtc().add(const Duration(hours: 8));
    final boughtDate =
        '${bj.year}-${bj.month.toString().padLeft(2, '0')}-${bj.day.toString().padLeft(2, '0')}';
    // 建仓次日起的K线参与 highestPrice 回填。建仓当天的K线不参与——
    // 日K含全天高低，若下午建仓、早上冲高，会把建仓前的高点算进来（如早上246、
    // 下午建仓价217，highestPrice 误取246）。建仓当天的最高价由实时 tick 决定。
    final holdingKlines =
        klines.where((k) => k.date.compareTo(boughtDate) > 0).toList();
    if (holdingKlines.isNotEmpty) {
      final klineHigh =
          holdingKlines.map((k) => k.high).reduce((a, b) => a > b ? a : b);
      if (klineHigh > position.highestPrice) {
        position.highestPrice = klineHigh;
      }
    }
    if (currentPrice > position.highestPrice) {
      position.highestPrice = currentPrice;
    }

    // ---- ATR ----
    final atr = calculateAtr(klines, period: cfg.atrPeriod);

    // ---- ATR 倍数自适应：按归一化波动率 atr/cost 分档覆盖 ----
    var effectiveMultiple = cfg.atrMultiple;
    if (cfg.atrAdaptive && atr != null && cost > 0) {
      final vol = atr / cost;
      effectiveMultiple = vol < 0.02 ? 2.0 : (vol < 0.05 ? 2.5 : 3.5);
    }

    // ---- 第一层：硬止损（固定比例，兜底）----
    final hardStop = cost * (1 - cfg.hardStopPercent);

    // ---- 第二层：ATR 止损 ----
    final atrStop = atr == null ? null : cost - atr * effectiveMultiple;

    // 基础止损 = 硬止损与 ATR 止损中更紧者（更高 = 更早触发 = 亏得更少）。
    final baseCandidates = [hardStop, ?atrStop];
    final baseStop = baseCandidates.reduce((a, b) => a > b ? a : b);

    // ---- 记录进场初始止损（首次，用于保本风险额度，防漂移）----
    if (position.initialStopPrice == null && atr != null) {
      position.initialStopPrice = baseStop;
    }

    // ---- 第三层：保本止损（浮盈达标后止损线上移）----
    double? breakevenStopPrice;
    AlertType? breakevenPromotedType; // 保本阶段提升的告知提醒
    if (cfg.breakevenEnabled && position.initialStopPrice != null) {
      final riskPerShare = cost - position.initialStopPrice!;
      if (riskPerShare > 0) {
        final profitPerShare = currentPrice - cost;
        final profitMultiple = profitPerShare / riskPerShare;
        // 按阶段 riskMultiple 升序，找出当前浮盈达到的最高阶段。
        final stages = List<BreakevenStage>.of(cfg.breakevenStages)
          ..sort((a, b) => a.riskMultiple.compareTo(b.riskMultiple));
        int targetStage = 0;
        for (final stage in stages) {
          if (profitMultiple >= stage.riskMultiple) {
            targetStage = stage.riskMultiple > targetStage
                ? stage.riskMultiple.toInt()
                : targetStage;
          }
        }
        // 阶段只升不降：达到新阶段时发告知提醒。
        if (targetStage > position.breakevenStageReached) {
          position.breakevenStageReached = targetStage;
          breakevenPromotedType = AlertType.breakevenStop;
        }
        // 用已达到的最高阶段算保本止损线（防浮盈回落后线回撤）。
        final reachedStage = stages.firstWhere(
          (s) => s.riskMultiple.toInt() == position.breakevenStageReached,
          orElse: () => stages.first,
        );
        if (position.breakevenStageReached > 0) {
          breakevenStopPrice = cost + reachedStage.lockRatio * riskPerShare;
        }
      }
    }

    // ---- 最终止损线 = max(基础止损, 保本止损线) ----
    final stopCandidates = [baseStop, ?breakevenStopPrice];
    final stopPrice = stopCandidates.reduce((a, b) => a > b ? a : b);

    // 触发类型判定：保本线更紧则 breakevenStop；否则按基础止损的起作用线。
    final AlertType stopType;
    if (breakevenStopPrice != null && breakevenStopPrice > baseStop) {
      stopType = AlertType.breakevenStop;
    } else if (atr == null || hardStop >= (atrStop ?? double.negativeInfinity)) {
      stopType = AlertType.hardStop;
    } else {
      stopType = AlertType.atrStop;
    }

    // ---- 第四层：止盈 ----
    // 钱德勒移动止盈 = highestPrice - atr×倍数（从最高价往下减，回撤到此价才卖）。
    // 高波动股 atr 大，裸值会远低于现价、甚至吐光利润（如 ATR 占价 8% 时 3 倍回撤=24%）。
    // 故移动止盈设「利润锁定下限」= max(止损线+缓冲, 成本+锁定利润)，锁定利润取
    // max(已实现最高浮盈×60%, 成本×8%)，保证：① 止盈永远高于止损；② 已盈利时
    // 至少锁定六成浮盈或 8% 利润，不被高波动回撤吐光。
    // 未盈利时（highestPrice≤cost）不设移动止盈线（返回 null），避免建仓即误触发。
    // 分批止盈走目标价（成本+盈亏比×风险），不受此限。
    double? takeProfitPrice;
    AlertType? takeProfitType;
    if (atr != null) {
      if (cfg.takeProfitStrategy == TakeProfitStrategy.batchAndTrailing) {
        // 分批止盈：跳过已触发档，取下一档目标价；全触发后剩余仓位用移动止盈。
        // 小仓位（≤300股/3手）退化为移动止盈全平，因分批比例算出非整手无法实际卖出。
        final totalQty = position.totalQuantity;
        final riskPerShare = position.initialStopPrice != null
            ? (cost - position.initialStopPrice!)
            : null;
        final remaining = cfg.takeProfitTargets
            .skip(position.triggeredTpCount)
            .toList();
        if (totalQty > 300 &&
            riskPerShare != null &&
            riskPerShare > 0 &&
            remaining.isNotEmpty) {
          final nextTarget = remaining.first;
          takeProfitPrice = cost + nextTarget.riskRewardRatio * riskPerShare;
          takeProfitType = AlertType.takeProfitTarget;
        }
      }
      // 移动止盈（trailingOnly 直接用；batchAndTrailing 分批档全触发后兜底）：
      // 仅在已盈利时生效，否则不设移动止盈线。
      final useTrailing = cfg.takeProfitStrategy == TakeProfitStrategy.trailingOnly ||
          (cfg.takeProfitStrategy == TakeProfitStrategy.batchAndTrailing &&
              (position.initialStopPrice == null ||
                  position.triggeredTpCount >=
                      cfg.takeProfitTargets.length));
      if (useTrailing) {
        final realizedGain = position.highestPrice - cost;
        // 仅当浮盈超过 1 个 ATR（趋势明确）才设移动止盈，避免建仓当天盘中
        // 冲高回落的最高价导致建仓即误触发。
        if (realizedGain > atr) {
          final lockedProfit = max(realizedGain * 0.6, cost * 0.08);
          final tpFloor = max(stopPrice + atr * 0.5, cost + lockedProfit);
          final raw = position.highestPrice - atr * cfg.trailingMultiple;
          var tp = raw < tpFloor ? tpFloor : raw;
          // 止盈线必须高于当前价：若算出的止盈线 ≤ 现价（如建仓当天冲高后回落
          // 到现价附近），不设止盈线，避免建仓即触发。
          if (tp > currentPrice) {
            takeProfitPrice = tp;
            takeProfitType = AlertType.trailingTakeProfit;
          }
        }
      }
    }

    // ---- 触发检测 ----
    // detect=false（盘后）时只算止损止盈线，不检测触发、不推进确认计时，
    // 避免盘后收盘价在止损线下方时「确认中」标签常驻却无告警。
    Alert? alert;

    if (detect) {
    // 1) 止损触发（含维持N分钟确认）
    if (currentPrice <= stopPrice) {
      final confirmed = _checkStopConfirmation(immediate, cfg.stopConfirmMinutes);
      if (confirmed) {
        alert = Alert(
          id: alertId,
          positionId: position.id,
          type: stopType,
          triggeredAt: DateTime.now(),
          stockCode: position.code,
          stockName: position.name,
          currentPrice: currentPrice,
          floatingPnl: position.floatingPnl,
          message: '止损触发：当前价 ${_fmt(currentPrice)} 元，'
              '止损线 ${_fmt(stopPrice)} 元',
          suggestion: '建议卖出全部剩余仓位',
        );
      }
      // 未达确认时长：不产生 alert，但保留 stopBreachSince（已在 _check 内记录）。
    } else {
      // 价格回升脱离止损线：清空破位计时。
      position.stopBreachSince = null;

      // 2) 保本阶段提升告知（优先于止盈，因止损线已上移属重要状态变化）。
      if (breakevenPromotedType != null) {
        final stageLabel = _breakevenStageLabel(position.breakevenStageReached);
        alert = Alert(
          id: alertId,
          positionId: position.id,
          type: AlertType.breakevenStop,
          triggeredAt: DateTime.now(),
          stockCode: position.code,
          stockName: position.name,
          currentPrice: currentPrice,
          floatingPnl: position.floatingPnl,
          message: '$stageLabel：止损线已上移至 ${_fmt(stopPrice)} 元',
          suggestion: '无需操作，止损线自动保护利润',
        );
      } else if (takeProfitPrice != null && takeProfitType != null) {
        // 3) 止盈触发
        if (takeProfitType == AlertType.takeProfitTarget &&
            currentPrice >= takeProfitPrice) {
          // 分批档到价：递增已触档数（确认时据此累加 closedQuantity）。
          position.triggeredTpCount++;
          alert = Alert(
            id: alertId,
            positionId: position.id,
            type: AlertType.takeProfitTarget,
            triggeredAt: DateTime.now(),
            stockCode: position.code,
            stockName: position.name,
            currentPrice: currentPrice,
            floatingPnl: position.floatingPnl,
            message: '分批止盈第${position.triggeredTpCount}档触发：目标价 '
                '${_fmt(takeProfitPrice)} 元，当前价 ${_fmt(currentPrice)} 元',
            suggestion: _batchSellSuggestion(position),
          );
        } else if (takeProfitType == AlertType.trailingTakeProfit &&
            currentPrice <= takeProfitPrice) {
          alert = Alert(
            id: alertId,
            positionId: position.id,
            type: AlertType.trailingTakeProfit,
            triggeredAt: DateTime.now(),
            stockCode: position.code,
            stockName: position.name,
            currentPrice: currentPrice,
            floatingPnl: position.floatingPnl,
            message: '移动止盈触发：最高价 ${_fmt(position.highestPrice)} 元，'
                '当前价 ${_fmt(currentPrice)} 元',
            suggestion: '建议卖出剩余仓位',
          );
        }
      }
    }
    } else {
      // 盘后不检测触发：清空破位计时，避免「确认中」常驻。
      position.stopBreachSince = null;
    }

    return StrategyEvaluation(
      stopPrice: stopPrice,
      takeProfitPrice: takeProfitPrice,
      alert: alert,
    );
  }

  /// 止损维持N分钟确认。返回 true 表示可触发告警。
  /// [immediate]=true（人工输价）直接放行；否则按 stopConfirmMinutes 计时。
  bool _checkStopConfirmation(bool immediate, int confirmMinutes) {
    if (immediate || confirmMinutes <= 0) return true;
    final now = DateTime.now();
    position.stopBreachSince ??= now;
    return now.difference(position.stopBreachSince!).inMinutes >= confirmMinutes;
  }

  String _breakevenStageLabel(int stage) {
    switch (stage) {
      case 1:
        return '已保本';
      case 2:
        return '已锁定50%利润';
      case 3:
        return '已锁定70%利润';
      default:
        return '保本止损生效';
    }
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  /// 分批止盈档到价时的卖出建议：算出本档应卖股数（按 sellRatio，向下取整到整手）。
  String _batchSellSuggestion(Position pos) {
    final targets = pos.strategy.takeProfitTargets;
    final targetIdx = (pos.triggeredTpCount - 1).clamp(0, targets.length - 1);
    final ratio = targets[targetIdx].sellRatio;
    final rawQty = pos.totalQuantity * ratio;
    // A股按手卖，向下取整到 100 的倍数。
    final sellQty = (rawQty ~/ 100) * 100;
    final remaining = pos.totalQuantity - pos.closedQuantity - sellQty;
    if (sellQty <= 0) {
      return '本档比例不足1手，建议等下一档或手动处理';
    }
    return '建议卖出 $sellQty 股，剩余 $remaining 股继续监控';
  }
}
