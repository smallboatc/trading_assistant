import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/alert.dart';
import '../../state/app_store.dart';
import '../theme/app_theme.dart';

/// 提醒列表。详见产品设计文档 3.4 提醒系统。
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提醒'),
        actions: [
          Consumer<AppStore>(
            builder: (context, store, _) {
              final hasHandled = store.alerts
                  .any((a) => a.action != AlertAction.pending);
              if (!hasHandled) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(CupertinoIcons.trash, size: 20),
                tooltip: '清除已处理',
                onPressed: () => _showClearConfirm(context, store),
              );
            },
          ),
        ],
      ),
      body: Consumer<AppStore>(
        builder: (context, store, _) {
          if (store.alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.bell_slash,
                      size: 64, color: AppTheme.systemGray3),
                  const SizedBox(height: 16),
                  const Text('暂无提醒', style: AppTextStyles.subtitle),
                ],
              ),
            );
          }
          return ListView(
            children: [
              const SizedBox(height: 8),
              ...store.alerts.map((a) => _AlertTile(alert: a)),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  void _showClearConfirm(BuildContext context, AppStore store) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清除已处理提醒？'),
        content: const Text('已确认/已忽略的提醒将被清除，未处理提醒保留。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              store.clearHandledAlerts();
              Navigator.of(ctx).pop();
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        color: AppTheme.cardBackground,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.bell_fill,
                      color: AppTheme.triggered, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${alert.stockName} ${alert.stockCode}',
                        style: AppTextStyles.cardTitle),
                  ),
                  Text(_timeStr(alert.triggeredAt),
                      style: AppTextStyles.caption),
                ],
              ),
              const SizedBox(height: 12),
              Text(alert.message, style: AppTextStyles.body),
              const SizedBox(height: 6),
              Text(alert.suggestion,
                  style: AppTextStyles.body
                      .copyWith(color: AppTheme.nearTakeProfit)),
              const SizedBox(height: 14),
              if (alert.action == AlertAction.pending)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: () => store.ignoreAlert(alert.id),
                      child: const Text('忽略'),
                    ),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () => store.confirmAlert(alert.id),
                      child: const Text('已确认'),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        alert.action == AlertAction.confirmed
                            ? CupertinoIcons.checkmark_seal_fill
                            : CupertinoIcons.xmark_circle_fill,
                        size: 14,
                        color: alert.action == AlertAction.confirmed
                            ? AppTheme.normal
                            : AppTheme.systemGray2,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        alert.action == AlertAction.confirmed ? '已确认' : '已忽略',
                        style: TextStyle(
                          fontSize: 12,
                          color: alert.action == AlertAction.confirmed
                              ? AppTheme.normal
                              : AppTheme.systemGray2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeStr(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
