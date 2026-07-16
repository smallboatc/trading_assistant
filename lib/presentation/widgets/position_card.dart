import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/position.dart';
import '../../core/models/strategy_config.dart';
import '../../state/app_store.dart';
import '../screens/chat_screen.dart';
import '../theme/app_theme.dart';

/// 持仓卡片（iOS 风格）。展示字段来自产品设计文档 3.5 持仓卡片信息。
class PositionCard extends StatelessWidget {
  const PositionCard({super.key, required this.position, this.onTap});

  final Position position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusOf(position);
    final pnl = position.floatingPnl;
    final pnlPct = position.floatingPnlPercent * 100;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        color: AppTheme.cardBackground,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, status),
                const SizedBox(height: 16),
                _priceRow(pnl, pnlPct),
                const SizedBox(height: 16),
                _linesRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, _CardStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 名称行：左侧名称+徽章（Expanded 占满），右侧按钮，垂直居中对齐。
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(position.name,
                        style: AppTextStyles.cardTitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  if (status != _CardStatus.normal) ...[
                    const SizedBox(width: 8),
                    _statusBadge(status),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(CupertinoIcons.chat_bubble, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              visualDensity: VisualDensity.compact,
              tooltip: '问 AI',
              color: AppTheme.systemBlue,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(position: position),
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(CupertinoIcons.ellipsis, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              color: AppTheme.systemGray,
              itemBuilder: (context) => [
                if (position.handled)
                  const PopupMenuItem(
                    value: 'reopen',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.arrow_clockwise, size: 18,
                            color: AppTheme.systemBlue),
                        SizedBox(width: 8),
                        Text('恢复监控'),
                      ],
                    ),
                  )
                else ...[
                  const PopupMenuItem(
                    value: 'addFill',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.add_circled, size: 18,
                            color: AppTheme.systemBlue),
                        SizedBox(width: 8),
                        Text('加仓'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.pencil, size: 18,
                            color: AppTheme.systemBlue),
                        SizedBox(width: 8),
                        Text('编辑持仓'),
                      ],
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.delete, size: 18,
                          color: AppTheme.nearStop),
                      SizedBox(width: 8),
                      Text('删除持仓'),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'reopen':
                    context.read<AppStore>().reopenPosition(position.id);
                  case 'addFill':
                    _showAddFillDialog(context);
                  case 'edit':
                    _showEditDialog(context);
                  case 'delete':
                    _showDeleteConfirm(context);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Flexible(
              child: Text(
                '${position.code} · ${position.remainingQuantity}股',
                style: AppTextStyles.subtitle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showDeleteConfirm(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('删除 ${position.name}？'),
        content: const Text('删除后无法恢复，确认删除？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              context.read<AppStore>().removePosition(position.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 加仓：追加一笔买入，成本价自动按加权重算。
  void _showAddFillDialog(BuildContext context) {
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    var error = '';
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => CupertinoAlertDialog(
          title: Text('加仓 ${position.name}'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  placeholder: '本次买入价',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  placeholder: '数量(股，100 的倍数)',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.nearStop)),
                  ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final p = double.tryParse(priceCtrl.text.trim());
                final q = int.tryParse(qtyCtrl.text.trim());
                if (p == null || p <= 0) {
                  setState(() => error = '请输入大于 0 的有效价格');
                  return;
                }
                if (q == null || q <= 0) {
                  setState(() => error = '请输入有效数量');
                  return;
                }
                if (q % 100 != 0) {
                  setState(() => error = 'A 股数量需为 100 的倍数');
                  return;
                }
                context.read<AppStore>().addFill(position.id, price: p, quantity: q);
                Navigator.of(ctx).pop();
              },
              child: const Text('加仓'),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑持仓：覆盖成本/数量/策略。
  void _showEditDialog(BuildContext context) {
    final priceCtrl = TextEditingController(
      text: position.costPrice.toStringAsFixed(2),
    );
    final qtyCtrl = TextEditingController(
      text: position.totalQuantity.toString(),
    );
    var preset = position.strategy.preset ?? PresetPlan.swingStandard;
    var error = '';
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => CupertinoAlertDialog(
          title: Text('编辑 ${position.name}'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  placeholder: '成本价',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  placeholder: '数量(股，100 的倍数)',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoSegmentedControl<PresetPlan>(
                  groupValue: preset,
                  onValueChanged: (v) => setState(() => preset = v),
                  children: const {
                    PresetPlan.swingStandard: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('波段'),
                    ),
                    PresetPlan.trendConservative: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('趋势-守'),
                    ),
                    PresetPlan.trendAggressive: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('趋势-激'),
                    ),
                  },
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.nearStop)),
                  ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final p = double.tryParse(priceCtrl.text.trim());
                final q = int.tryParse(qtyCtrl.text.trim());
                if (p == null || p <= 0) {
                  setState(() => error = '请输入大于 0 的有效成本价');
                  return;
                }
                if (q == null || q <= 0) {
                  setState(() => error = '请输入有效数量');
                  return;
                }
                if (q % 100 != 0) {
                  setState(() => error = 'A 股数量需为 100 的倍数');
                  return;
                }
                context.read<AppStore>().updatePosition(position.id,
                    price: p, quantity: q, strategy: StrategyConfig.fromPreset(preset));
                Navigator.of(ctx).pop();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(double pnl, double pnlPct) {
    final cur = position.currentPrice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          cur == null ? '—' : cur.toStringAsFixed(2),
          style: AppTextStyles.numberLg,
        ),
        if (position.priceStale) ...[
          const SizedBox(width: 6),
          _badge('延迟', AppTheme.systemGray),
        ],
        if (position.marketClosed) ...[
          const SizedBox(width: 6),
          _badge('收盘', AppTheme.systemGray2),
        ],
        if (position.stopBreachSince != null &&
            position.distanceToStop != null &&
            position.distanceToStop! < 0) ...[
          const SizedBox(width: 6),
          _badge('确认中', AppTheme.nearTakeProfit),
        ],
        const SizedBox(width: 8),
        // 成本：普通 Text，与当前价同为 Text，end 对齐下文字底齐平。
        Flexible(
          child: Text(
            '成本 ${position.costPrice.toStringAsFixed(2)}',
            style: AppTextStyles.caption,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(0)}',
              style: AppTextStyles.numberMd.copyWith(
                color: AppTheme.pnlColor(position.floatingPnlPercent),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.pnlColor(position.floatingPnlPercent),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 紧凑状态小标（价格行内）。padding 垂直方向用 1，文字 height 撑开，
  /// 使文字底边尽量贴近 Container 底，与当前价文字底在 end 对齐下齐平。
  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.5)),
    );
  }

  Widget _linesRow() {
    final stop = position.stopPrice;
    final tp = position.takeProfitPrice;
    return Row(
      children: [
        Flexible(child: _lineChip('止损', stop, AppTheme.nearStop)),
        const SizedBox(width: 8),
        Flexible(child: _lineChip('止盈', tp, AppTheme.nearTakeProfit)),
        const SizedBox(width: 8),
        Text('持${position.holdingDays}天', style: AppTextStyles.caption),
      ],
    );
  }

  Widget _lineChip(String label, double? value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        '$label ${value == null ? '—' : value.toStringAsFixed(2)}',
        style: AppTextStyles.chip.copyWith(color: color),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _statusBadge(_CardStatus status) {
    if (status == _CardStatus.normal) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(status),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }

  // ---- 状态推断（简化版，V1 基于距离阈值）----
  _CardStatus _statusOf(Position p) {
    if (p.handled) return _CardStatus.closed;
    if (p.lastAlertId != null) return _CardStatus.triggered;
    if (p.breakevenStageReached > 0) return _CardStatus.protected;
    final dStop = p.distanceToStop;
    if (dStop != null && dStop < 0.03) return _CardStatus.nearStop;
    final dTp = p.distanceToTakeProfit;
    if (dTp != null && dTp < 0.03) return _CardStatus.nearTakeProfit;
    return _CardStatus.normal;
  }

  Color _statusColor(_CardStatus s) => switch (s) {
        _CardStatus.normal => AppTheme.normal,
        _CardStatus.nearStop => AppTheme.nearStop,
        _CardStatus.nearTakeProfit => AppTheme.nearTakeProfit,
        _CardStatus.triggered => AppTheme.triggered,
        _CardStatus.protected => AppTheme.systemBlue,
        _CardStatus.closed => AppTheme.closed,
      };

  String _statusLabel(_CardStatus s) => switch (s) {
        _CardStatus.normal => '正常',
        _CardStatus.nearStop => '接近止损',
        _CardStatus.nearTakeProfit => '接近止盈',
        _CardStatus.triggered => '待确认',
        _CardStatus.protected => '已保本',
        _CardStatus.closed => '已平仓',
      };
}

enum _CardStatus { normal, nearStop, nearTakeProfit, triggered, protected, closed }
